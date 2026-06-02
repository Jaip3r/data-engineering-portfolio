# Dataset: DVD Rental

Dataset estándar de PostgreSQL que simula una cadena de videoclubs.

## Características

- 15 tablas relacionadas
- ~16,000 registros de alquileres
- Datos temporales: Mayo 2005 - Agosto 2006

## Instalación

### Con Docker

```bash
docker run --name postgres-learning \
  -e POSTGRES_PASSWORD=learning123 \
  -e POSTGRES_DB=sandbox \
  -p 5432:5432 \
  -d postgres:16
```

### Restaurar el dataset

1. Descarga dvdrental.tar desde:
   https://neon.com/postgresql/postgresql-getting-started/postgresql-sample-database
2. Crea una base de datos llamada `dvdrental`
3. Restaura con pgAdmin: clic derecho → Restore → selecciona el .tar
