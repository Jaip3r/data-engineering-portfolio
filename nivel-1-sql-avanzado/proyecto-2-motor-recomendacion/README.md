# Proyecto 2: Motor de Recomendación SQL

## Contexto de negocio

Sistema de recomendación de películas construido
integramente en SQL para una cadena de videoclubs.

## Archivos

| Archivo                          | Descripción                                               | Conceptos clave                           |
| -------------------------------- | --------------------------------------------------------- | ----------------------------------------- |
| `perfil_cliente.sql`             | Categoría favorita, actor favorito y ventana de actividad | LATERAL Top-1, base compartida optimizada |
| `sistema_recomendacion.sql`      | 5 recomendaciones por cliente                             | LATERAL + NOT EXISTS + Top-N              |
| `analisis_cohortes.sql`          | Retención mensual por cohorte de entrada                  | Mes relativo, COUNT DISTINCT, PIVOT       |
| `reporte_ingresos_mensuales.sql` | Ingresos por categoría en los últimos 6 meses             | PIVOT dinámico, CROSS JOIN escalar        |

## Decisiones de diseño destacadas

**Base compartida optimizada:**
La cadena rental→inventory→film_category se ejecuta una
sola vez y alimenta tanto el perfil de cliente como el
ranking global, evitando escaneos duplicados costosos.

**Top-20 por categoría (no global):**
Se eligió Top-20 dentro de cada categoría para garantizar
recomendaciones disponibles para todos los clientes,
independientemente de su categoría favorita.

**CROSS JOIN LATERAL intencional:**
Excluye clientes sin historial de alquileres. En este
dataset todos los clientes tienen al menos un alquiler.

**Mes relativo en análisis de cohortes:**
Se usa diferencia de años\*12 + diferencia de meses para
calcular la posición relativa de cada alquiler respecto
al mes de entrada del cliente, independientemente del
año calendario.

**PIVOT dinámico con CROSS JOIN escalar:**
El reporte de ingresos usa el mes máximo del dataset como
ancla, haciendo el reporte robusto ante cambios en el
rango temporal de los datos.

## Cómo ejecutar

```bash
psql -d dvdrental -f perfil_cliente.sql
psql -d dvdrental -f sistema_recomendacion.sql
psql -d dvdrental -f analisis_cohortes.sql
psql -d dvdrental -f reporte_ingresos_mensuales.sql
```
