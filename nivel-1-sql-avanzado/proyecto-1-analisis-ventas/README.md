# Proyecto 1: Dashboard de Análisis de Ventas

## Contexto de negocio

Análisis completo del comportamiento de clientes y rendimiento
de inventario para una cadena de videoclubs, respondiendo
preguntas clave de negocio mediante SQL analítico avanzado.

## Reportes

| Archivo                             | Descripción                                      | Conceptos clave                     |
| ----------------------------------- | ------------------------------------------------ | ----------------------------------- |
| `reporte_clientes_vip.sql`          | Top 20% clientes por gasto con evolución mensual | PERCENT_RANK, LAG, running total    |
| `reporte_rendimiento_geografia.sql` | Ingresos por país y ciudad con subtotales        | ROLLUP, GROUPING()                  |
| `reporte_peliculas_estrella.sql`    | Top 3 películas más rentables por categoría      | LATERAL, porcentaje de contribución |
| `reporte_habitos_alquiler.sql`      | Últimos 2 alquileres de clientes VIP             | LATERAL, LAG, EXISTS                |

## Desiciones de diseño destacadas

**PERCENT_RANK sobre clientes únicos**
El ranking VIP se calcula sobre una CTE con un cliente
por fila, no sobre el dataset mensual. Evita distorsión
del percentil por filas duplicadas.

**ROLLUP sobre GROUPING SETS**
El reporte geográfico usa ROLLUP porque pais -> ciudad
forma una jerarquía perfecta. GROUPING SETS se reservaría
para combinaciones fuera de la jerarquía.

## Cómo ejecutar

Requiere el dataset DVD Rental instalado.
→ [Instrucciones](../dataset/setup.md)

```bash
psql -d dvdrental -f reporte_clientes_vip.sql
psql -d dvdrental -f reporte_geografia.sql
psql -d dvdrental -f reporte_peliculas_estrella.sql
psql -d dvdrental -f reporte_habitos_alquiler.sql
```
