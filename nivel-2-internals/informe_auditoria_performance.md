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

### 2.3 Hallazgo: densidad de filas dispar

Se identificó una diferencia significativa en bytes/fila entre tablas:

- `film`: ~727 bytes/fila (11 filas por página)
- `film_actor`: ~44 bytes/fila (182 filas por página)
- `inventory`: ~45 bytes/fila (183 filas por página)

**Causa:** `film` contiene columnas `TEXT` (`description`), `TEXT[]` (`special_features`) y
`TSVECTOR` (`fulltext`) que inflan el tamaño de fila. `film_actor` e `inventory` solo contienen
columnas numéricas y timestamp.

**Impacto:** Un sequential scan sobre `film` es ~16x más costoso por fila
que uno sobre `film_actor` o `inventory`, debido al menor número de filas que caben por
página de 8kB.

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
39 índices distribuidos en 15 tablas.

### 3.2 Índices con mayor utilización
