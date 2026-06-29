# Auditoria Técnica de Performance - DVD Rental DB

## Resumen Ejecutivo

## 2. Análisis de almacenamiento

### 2.1 Metodología

Se consultó `pg_stat_user_tables` y `pg_class` para obtener tamaños
físicos y distribución de páginas. **Mediciones tomadas con fecha de 19/06/2026.**

### 2.2 Tablas por tamaño físico

| Tabla         | Tamaño datos | Tamaño índices | Filas | Páginas | Filas por Página |
| ------------- | ------------ | -------------- | ----- | ------- | ---------------- |
| rental        | 1200 kB      | 1288 kB        | 16044 | 150     | 107              |
| payment       | 864 kB       | 952 kB         | 14596 | 108     | 135              |
| film          | 704 kB       | 232 kB         | 1000  | 88      | 11               |
| film_actor    | 240 kB       | 248 kB         | 5462  | 30      | 182              |
| inventory     | 200 kB       | 240 kB         | 4581  | 25      | 183              |
| customer      | 72 kB        | 136 kB         | 599   | 9       | 66               |
| address       | 64 kB        | 88 kB          | 603   | 8       | 75               |
| film_category | 48 kB        | 64 kB          | 1000  | 6       | 166              |
| city          | 40 kB        | 72 kB          | 600   | 5       | 120              |
| actor         | 16 kB        | 56 kB          | 200   | 2       | 100              |
| staff         | 8.192 kB     | 24 kB          | 2     | 1       | 2                |
| country       | 8.192 kB     | 16 kB          | 109   | 1       | 109              |
| language      | 8.192 kB     | 16 kB          | 6     | 1       | 6                |
| store         | 8.192 kB     | 32 kB          | 2     | 1       | 2                |
| category      | 8.192 kB     | 16 kB          | 12    | 1       | 12               |

### 2.3 Hallazgo: paradoja de tamaño vs volumen de filas

Se identificó una disparidad significativa entre el número de filas y
el espacio físico ocupado entre tablas:

| Tabla      | Filas | Páginas | Bytes/fila |
| ---------- | ----- | ------- | ---------- |
| film       | 1000  | 88      | ~727       |
| film_actor | 5462  | 30      | ~44        |
| inventory  | 4851  | 25      | ~45        |

A pesar de tener **5x menos filas**, `film` ocupa casi **3x más páginas**
que `film_actor` debido a una densidad de filas radicalmente dispar:
en `film` caben solo 11 filas por página de 8 Kb, mientras que en `film_actor`
e `inventory` caben 182 filas por página.

**Causa:** `film` contiene columnas de tipo `TEXT` (`description`), `TEXT[]` (`special_features`) y
`TSVECTOR` (`fulltext`) que inflan el tamaño de cada fila. `film_actor` e `inventory` solo contienen
principalmente columnas numéricas y timestamps.

**Impacto:** Un sequential scan sobre `film` requiere leer 88 páginas para 1000 filas,
mientras que un sequential scan sobre `film_actor` lee solo 30 páginas para 5462 filas.
Esto significa que **en términos de I/O, escanear `film` completamente es ~3x más costoso que escanear `film_actor`**, a pesar de tener muchas menos filas.

### 2.4 Verificación de orden físico vs lógico

```sql
SELECT ctid, customer_id, first_name FROM customer LIMIT 5;
```

Resultado: la fila con `customer_id=524` se encontró en la posición
física `(0,1)`, confirmando que PostgreSQL no mantiene orden físico
correlacionado con la PK (a diferencia de motores con clustered index
nativo como SQL Server).

## 3. Auditoría de Índices

### 3.1 Inventario completo

Se ejecutó `pg_indexes` sobre el esquema `public`, identificando
32 índices distribuidos en 15 tablas.

### 3.2 Índices con mayor utilización

| Tabla      | Índice             | Usos (idx_scan) | Filas leídas |
| ---------- | ------------------ | --------------- | ------------ |
| film       | film_pkey          | 1,110,868       | 1,110,868    |
| film_actor | idx_fk_film_id     | 305,000         | 1,671,784    |
| payment    | idx_fk_customer_id | 3,326           | 683,921      |

**Análisis**: Los 3 índices más usados corresponden a claves primarias y foráneas
involucradas en JOINs frecuentes. El alto `idx_scan` de `film_pkey` (1,110,868)
refleja que prácticamente todas las consultas del nivel 1 resuelven `film_id -> film`
en algún punto de su cadena de JOINs, incluyendo el sistema de recomendación donde esta
resolución ocurre una vez por cada cliente evaluado (600 clientes) dentro de un LATERAL JOIN.

El patrón general observado: **Los índices más usados son consistentementes los de PKs y FKs que participan en JOINs**,
no los de columnas de búsqueda textual. Esto es típico de cargas de trabajo analíticas (OLAP)
donde el acceso es principalmente por relaciones entre entidades, no por filtros sobre atributos.

### 3.3 Índices sin uso detectado

| Tabla    | Índice              | Usos (idx_scan) |
| -------- | ------------------- | --------------- |
| customer | idx_last_name       | 0               |
| film     | idx_title           | 0               |
| actor    | idx_actor_last_name | 0               |

**Análisis**: Estos índices no fueron utilizados durante el periodo auditado debido
a que la carga de trabajo ejecutada (Niveles 1-2) no incluyó búsquedas textuales
puntuales (`WHERE last_name = ...`), únicamente agregaciones, JOINs y análisis temporal.

**Recomendación**: No eliminar estos índices sin antes confirmar que la aplicación real
no los necesita. En un entorno real, se recomendaría monitorear `idx_scan` durante algunas
semanas de tráfico real antes de decidir su eliminación.

### 3.4 Brecha crítica: ausencia de índice dedicado sobre `rental.customer_id`

**Problema identificado:** `rental` no contaba con un índice dedicado sobre `customer_id`. El único índice que incluye
esta columna es el compuesto `idx_unq_rental_rental_date_inventory_id_customer_id` sobre `(rental_date, inventory_id, customer_id)`.
Por la regla de prefijo izquierdo, este índice no puede ser utilizado para consultas que filtren exclusivamente por `customer_id`.

**Impacto:** Consultas de negocio frecuentes como `WHERE customer_id = X` sobre `rental` forzaban un sequential scan
completo de las 150 páginas de la tabla.

Seq Scan on rental (cost=0.00..350.55 rows=8040)
Filter: (customer_id = 100)
Rows Removed by Filter: 16020
Execution Time: 1.817 ms

**Corrección aplicada:**

```sql
CREATE INDEX idx_rental_customer_id ON rental(customer_id);
```

**Evidencia (después de la corrección):**

Bitmap Heap Scan on rental
Heap Blocks: exact=22 (vs 150 páginas del sequential scan)
Execution Time: 0.075 ms

**Resultado:** Reducción de páginas leídas de 150 a 22 (~85% menos I/O) y mejora de tiempo de ejecución
de 1.817ms a 0.075ms (~24x más rápido).

### 3.5 Hallazgo curioso: GIST en lugar de GIN

```sql
"film","film_fulltext_idx","... USING gist (fulltext)"
```

El índice de búsqueda de texto completo usa GIST en vez de GIN. Ambos
son válidos para `TSVECTOR`, pero representan un trade-off distinto:

| Aspecto                | GIN   | GIST  |
| ---------------------- | ----- | ----- |
| Velocidad de búsqueda  | Mayor | Menor |
| Velocidad de escritura | Menor | Mayor |
| Tamaño en disco        | Mayor | Menor |

Dado que `film` es un catálogo de bajo volumen de escritura y alto
volumen de lectura, **GIN sería la elección más apropiada** si se
priorizara velocidad de búsqueda sobre tamaño en disco.
