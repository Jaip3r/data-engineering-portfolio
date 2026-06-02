# Nivel 1: SQL Avanzado

Proyectos que cubren técnicas avanzadas de SQL analítico
sobre el dataset DVD Rental de PostgreSQL.

## Conceptos cubiertos

### Window Functions

- PARTITION BY, ORDER BY y frames explícitos (ROWS BETWEEN)
- Funciones de navegación: LAG, LEAD, FIRST_VALUE
- Cláusula WINDOW para reutilización de definiciones
- Tiebreakers para resultados determinísticos

### Agregaciones Multidimensionales

- GROUPING SETS, ROLLUP y CUBE
- Función GROUPING() para distinguir NULLs generados
- Ordenamiento semántico en reportes jerárquicos

### PIVOT / UNPIVOT

- PIVOT manual con CASE WHEN + agregación
- Modificador FILTER (PostgreSQL moderno)
- UNPIVOT con LATERAL + VALUES
- Distinción semántica entre ELSE 0 y ELSE NULL

### LATERAL JOIN

- Top-N por grupo con LIMIT dentro de LATERAL
- CROSS JOIN LATERAL vs LEFT JOIN LATERAL
- Cálculos dependientes de fila
- Comparación de rendimiento vs Window Functions

## Proyectos

1. [Dashboard de Análisis de Ventas](./proyecto-1-analisis-ventas)
2. [Motor de Recomendación SQL](./proyecto-2-motor-recomendacion)

## Dataset

→ [Instrucciones de instalación](./dataset/setup.md)
