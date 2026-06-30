# Auditoria Técnica de Performance - DVD Rental DB

## Resumen Ejecutivo

Este informe documenta una auditoría de rendimiento sobre la base de datos DVD Rental (PostgreSQL 16),
cubriendo análisis de almacenamiento físico, uso real de índices, viabilidad de particionamiento, optimización
de queries analíticas y estado de salud transaccional.

**Hallazgos principales:**

- La tabla `rental` carece de índice dedicado sobre `customer_id`,
  forzando sequential scans en consultas frecuentes de negocio.
- 3 índices existentes (`idx_last_name`, `idx_title`, `idx_actor_last_name`)
  presentan 0 usos en el período auditado.
- El particionamiento por rango de fecha en `payment` demuestra mejoras
  de hasta 13x en queries que combinan filtro temporal + filtro de cliente.
- No se detectó bloat significativo en el estado actual de la base de datos.

## 2. Análisis de almacenamiento

### 2.1 Metodología

Se consultó `pg_stat_user_tables` y `pg_class` para obtener tamaños
físicos y distribución de páginas. **Mediciones tomadas con fecha de 19/06/2026.**

### 2.2 Tablas por tamaño físico

| Tabla         | Tamaño datos | Tamaño índices | Filas  | Páginas | Filas por Página |
| ------------- | ------------ | -------------- | ------ | ------- | ---------------- |
| rental        | 1,200 kB     | 1,288 kB       | 16,044 | 150     | 107              |
| payment       | 864 kB       | 952 kB         | 14,596 | 108     | 135              |
| film          | 704 kB       | 232 kB         | 1,000  | 88      | 11               |
| film_actor    | 240 kB       | 248 kB         | 5,462  | 30      | 182              |
| inventory     | 200 kB       | 240 kB         | 4,581  | 25      | 183              |
| customer      | 72 kB        | 136 kB         | 599    | 9       | 66               |
| address       | 64 kB        | 88 kB          | 603    | 8       | 75               |
| film_category | 48 kB        | 64 kB          | 1,000  | 6       | 166              |
| city          | 40 kB        | 72 kB          | 600    | 5       | 120              |
| actor         | 16 kB        | 56 kB          | 200    | 2       | 100              |
| staff         | 8.192 kB     | 24 kB          | 2      | 1       | 2                |
| country       | 8.192 kB     | 16 kB          | 109    | 1       | 109              |
| language      | 8.192 kB     | 16 kB          | 6      | 1       | 6                |
| store         | 8.192 kB     | 32 kB          | 2      | 1       | 2                |
| category      | 8.192 kB     | 16 kB          | 12     | 1       | 12               |

### 2.3 Hallazgo: paradoja de tamaño vs volumen de filas

Se identificó una disparidad significativa entre el número de filas y
el espacio físico ocupado entre tablas:

| Tabla      | Filas | Páginas | Bytes/fila |
| ---------- | ----- | ------- | ---------- |
| film       | 1,000 | 88      | ~727       |
| film_actor | 5,462 | 30      | ~44        |
| inventory  | 4,581 | 25      | ~45        |

A pesar de tener **5x menos filas**, `film` ocupa casi **3x más páginas**
que `film_actor` debido a una densidad de filas radicalmente dispar:
en `film` caben solo 11 filas por página de 8 Kb, mientras que en `film_actor`
e `inventory` caben 182 filas por página.

**Causa:** `film` contiene columnas de tipo `TEXT` (`description`), `TEXT[]` (`special_features`) y
`TSVECTOR` (`fulltext`) que inflan el tamaño de cada fila. `film_actor` e `inventory` solo contienen
principalmente columnas numéricas y timestamps.

**Impacto:** Un sequential scan sobre `film` requiere leer 88 páginas para 1000 filas,
mientras que un sequential scan sobre `film_actor` lee solo 30 páginas para 5462 filas.
Esto significa que **en términos de I/O, escanear `film` completamente es ~3x más costoso que escanear `film_actor`**,
a pesar de tener muchas menos filas.

### 2.4 Verificación de orden físico vs lógico

```sql
SELECT ctid, customer_id, first_name FROM customer LIMIT 5;
```

Resultado: la fila con `customer_id=524` se encontró en la posición
física `(0,1)`, confirmando que PostgreSQL no mantiene orden físico
correlacionado con la clave primaria (a diferencia de motores con clustered index
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

El patrón general observado: **Los índices más usados son consistentementes los de claves primarias y foráneas que participan en JOINs**,
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

```text
Seq Scan on rental (cost=0.00..350.55 rows=8040)
Filter: (customer_id = 100)
Rows Removed by Filter: 16020
Execution Time: 1.817 ms
```

**Corrección aplicada:**

```sql
CREATE INDEX idx_rental_customer_id ON rental(customer_id);
```

**Evidencia (después de la corrección):**

```text
Bitmap Heap Scan on rental
Heap Blocks: exact=22 (vs 150 páginas del sequential scan)
Execution Time: 0.075 ms
```

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

## 4. Caso de Particionamiento

### 4.1 Hipótesis

Se evaluó si el particionamieto de la tabla `payment` por rango de `payment_date` mejora
el rendimiento de consultas que combinan filtro temporal y filtro de cliente, comparado
con la tabla `payment` original (sin particionar).

### 4.2 Metodología

Se creó `payment_partitioned`, particionada por mes (`RANGE`), con 5 particiones (Enero-Mayo 2007),
poblada con los mismos datos de `payment`. Se indexó `customer_id` en la tabla particionada.

### 4.3 Consultas de prueba

**Consulta A:**

```sql
EXPLAIN ANALYZE
SELECT *
FROM payment_partitioned
WHERE payment_date >= '2007-03-01' AND payment_date < '2007-04-01';
```

**Consulta B:**

```sql
EXPLAIN ANALYZE
SELECT *
FROM payment_partitioned
WHERE customer_id = 100;
```

**Consulta C:**

```sql
EXPLAIN ANALYZE
SELECT *
FROM payment_partitioned
WHERE payment_date >= '2007-03-01' AND payment_date < '2007-04-01'
    AND customer_id = 100;
```

### 4.4 Resultados comparativos

| Consulta | Filtro              | Particiones consultadas | Tiempo ejecución |
| -------- | ------------------- | ----------------------- | ---------------- |
| A        | Solo fecha          | 1 de 5                  | 0.609 ms         |
| B        | Solo customer_id    | 5 de 5                  | 0.918 ms         |
| C        | Fecha + customer_id | 1 de 5                  | 0.068 ms         |

### 4.5 Análsis de resultados

**Consulta A** confirma partition pruning efectivo: Con filtro de fecha, PostgreSQL
descartó 4 de 5 particiones en tiempo de planificación, sin necesidad de leerlas.

**Consulta B** demuestra el riesgo de particionar sin disciplina de consulta: Al no
incluir la clave de particionamiento en el WHERE, las 5 particiones fueron consultadas
via operador el `Append`, que combina resultados de múltiples particiones como si fueran
una sola tabla. A diferencia de la consulta A donde el plan solo muestra una partición,
aquí el plan muestra 5 nodos hijo independientes, incluyendo `payment_p_2007_01` que no contenía
resultados (`rows=0`), representando trabajo desperdiciado.

**Consulta C** es el caso óptimo: Combina partition pruning (reduce de 14,596 a ~ 5,644
filas candidatas) con índice local sobre `customer_id` (reduce a las 5 filas exactas).
Resultado: **9x más rápida que A** y **13x más rápida que B**.

### 4.6 Conclusión

En el tamaño actual del dataset (14,596 filas), el particionamiento no se justifica por si
solo: el overhead de gestionar particiones pequeñas puede superar el beneficio. Sin embargo,
el experimento demuestra que, **a escala de producción** (millones de filas), el patrón de
fecha + índice local sería significativamente más eficiente que una tabla monolítica.

## 5. Optimización de una Consulta Real

### 5.1 Consulta auditada

Reporte de rendimiento geográfico (Proyecto 1, Nivel 1), que combina 5 tablas
via INNER JOIN con agregación ROLLUP.

### 5.2 Plan de ejecución obtenido

```text
Sort  (cost=2116.82..2153.59 rows=14706 width=122) (actual time=20.618..20.645 rows=706 loops=1)
  Sort Key: (GROUPING(co.country)), co.country, (GROUPING(ci.city)), ci.city
  Sort Method: quicksort  Memory: 75kB
  ->  MixedAggregate  (cost=66.00..1098.86 rows=14706 width=122) (actual time=19.383..19.592 rows=706 loops=1)
        Hash Key: co.country, ci.city
        Hash Key: co.country
        Group Key: ()
        Batches: 1  Memory Usage: 929kB
        ->  Hash Join  (cost=66.00..475.51 rows=14596 width=24) (actual time=1.720..12.779 rows=14596 loops=1)
              Hash Cond: (ci.country_id = co.country_id)
              ->  Hash Join  (cost=62.55..432.25 rows=14596 width=17) (actual time=1.618..10.674 rows=14596 loops=1)
                    Hash Cond: (a.city_id = ci.city_id)
                    ->  Hash Join  (cost=44.05..375.17 rows=14596 width=8) (actual time=0.973..7.710 rows=14596 loops=1)
                          Hash Cond: (c.address_id = a.address_id)
                          ->  Hash Join  (cost=22.48..315.02 rows=14596 width=8) (actual time=0.545..5.249 rows=14596 loops=1)
                                Hash Cond: (p.customer_id = c.customer_id)
                                ->  Seq Scan on payment p  (cost=0.00..253.96 rows=14596 width=8) (actual time=0.006..1.410 rows=14596 loops=1)
                                ->  Hash  (cost=14.99..14.99 rows=599 width=6) (actual time=0.511..0.511 rows=599 loops=1)
                                      Buckets: 1024  Batches: 1  Memory Usage: 31kB
                                      ->  Seq Scan on customer c  (cost=0.00..14.99 rows=599 width=6) (actual time=0.006..0.394 rows=599 loops=1)
                          ->  Hash  (cost=14.03..14.03 rows=603 width=6) (actual time=0.401..0.402 rows=603 loops=1)
                                Buckets: 1024  Batches: 1  Memory Usage: 31kB
                                ->  Seq Scan on address a  (cost=0.00..14.03 rows=603 width=6) (actual time=0.006..0.275 rows=603 loops=1)
                    ->  Hash  (cost=11.00..11.00 rows=600 width=15) (actual time=0.396..0.396 rows=600 loops=1)
                          Buckets: 1024  Batches: 1  Memory Usage: 37kB
                          ->  Seq Scan on city ci  (cost=0.00..11.00 rows=600 width=15) (actual time=0.031..0.141 rows=600 loops=1)
              ->  Hash  (cost=2.09..2.09 rows=109 width=13) (actual time=0.084..0.084 rows=109 loops=1)
                    Buckets: 1024  Batches: 1  Memory Usage: 14kB
                    ->  Seq Scan on country co  (cost=0.00..2.09 rows=109 width=13) (actual time=0.043..0.051 rows=109 loops=1)
Planning Time: 4.834 ms
Execution Time: 21.217 ms
```

### 5.3 Decisiones del optimizador identificadas

1. **Algoritmo de JOIN:** Hash Join en las 4 uniones, no nested loops ni Merge Join.
   Justificación: Todas las tablas de dimensión (`customer`, `address`, `city`, `country`) son pequeñas
   y caben como hash en memoria.

2. **Orden de evaluación:** La tabla más grande (`payment`, 14,596 filas) se mantiene como lado exterior
   en cada Hash Join; las tablas pequeñas se hashean.

3. **Patrón de cascada:** los 4 Hash Joins están anidados de forma que el resultado de cada uno alimenta al
   siguiente como lado exterior. El orden de construcción de las hash tables, de más interno a más externo, es:

   customer (599 filas, 31kB) → hash table 1
   address (603 filas, 31kB) → hash table 2
   city (600 filas, 37kB) → hash table 3
   country (109 filas, 14kB) → hash table 4

4. **MixedAggregate:** Operador específico de PostgreSQL para consultas con `ROLLUP`, `CUBE` o `GROUPING SETS`.
   En lugar de hacer múltiples pasadas por los datos (una por cada nivel de agrupación), combina todos los niveles en una sola pasada:
   - `Hash Key: co.country, ci.city` → agrupación detallada
   - `Hash Key: co.country` → subtotal por país
   - `Group Key: ()` → total general

   Esto es más eficiente que ejecutar tres `GROUP BY` separados con `UNION ALL`,
   que requeriría tres escaneos completos de los datos de entrada.

### 5.4 Costo medio

Planning Time: 4.834 ms | Execution Time: 21.217 ms

El planning time es considerablemente mayor que en consultas de una sola tabla,
esto se explica por la explosión combinatoria de posibles órdenes de JOIN para 5 tablas
(hasta 5! = 120 combinaciones para 5 tablas). Adicionalmente, la presencia de `ROLLUP`
agrega complejidad al planning porque el optimizador debe evaluar cómo combinar eficientemente
los múltiples niveles de agrupación.

### 5.5 Conclusión

El plan generado es óptimo para el tamaño actual de las tablas. No se identificaron oportunidades
de mejora mediante indices adicionales, dado que la consulta se hace sobre la totalidad de filas y
las tablas de dimensión son suficientemente pequeñas para que Seq Scan + Hash sea más eficiente que
una alternativa basada en índices.

## 6. Estado de concurrencia

### 6.1 Verificación de bloat

```sql
SELECT relname, n_live_tup, n_dead_tup,
    ROUND(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS pct_muertas
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

### 6.2 Resultados

| Tabla               | Filas Vivas | Filas Muertas | % Muertas |
| ------------------- | ----------- | ------------- | --------- |
| rental              | 16,044      | 0             | 0         |
| payment             | 14,596      | 0             | 0         |
| payment_p_2007_04   | 6,754       | 0             | 0         |
| payment_p_2007_03   | 5,644       | 0             | 0         |
| film_actor          | 5,462       | 0             | 0         |
| inventory           | 4,581       | 0             | 0         |
| payment_p_2007_02   | 2,016       | 0             | 0         |
| film                | 1,000       | 0             | 0         |
| film_category       | 1,000       | 0             | 0         |
| address             | 603         | 0             | 0         |
| city                | 600         | 0             | 0         |
| customer            | 599         | 0             | 0         |
| actor               | 200         | 0             | 0         |
| payment_p_2007_05   | 182         | 0             | 0         |
| country             | 109         | 0             | 0         |
| category            | 16          | 0             | 0         |
| language            | 6           | 0             | 0         |
| staff               | 2           | 0             | 0         |
| store               | 2           | 0             | 0         |
| payment_partitioned | 0           | 0             | 0         |
| payment_p_2007_01   | 0           | 0             | 0         |

### 6.3 Análisis

No se detectaron filas muertas (`n_dead_tup = 0`) en ninguna tabla del esquema,
lo cual es coherente con la naturaleza de las operaciones realizadas durante los Niveles 1 y 2
(operaciones mayormente de lectura con la excepción de las cargas iniciales al crear `payment_partitioned`).

En un entorno de producción con alta tasa de escrituras (`UPDATE`/`DELETE` frecuentes), este mismo chequeo sería
rutina semanal o diaria, ya que el `pct_muertas` por encima del ~20% en tablas grandes es indicador de que `autovacuum`
no está operando con suficiente frecuencia para la carga real del sistema.
