-- Sistema de recomendación
WITH rental_with_film_category AS (
	-- Paso 1: Ubicar la pelicula asociada a cada renta junto con su categoria
	SELECT r.customer_id,
		r.rental_id,
		i.film_id,
		fc.category_id
	FROM rental r
	INNER JOIN inventory i 
		ON r.inventory_id = i.inventory_id
	INNER JOIN film_category fc
		ON i.film_id = fc.film_id
),
customer_category_rentals AS (
	-- Paso 2: Total de rentas por cliente y categoria
	SELECT customer_id,
		category_id,
		COUNT(rental_id) AS total_category_rentals
	FROM rental_with_film_category
	GROUP BY customer_id, category_id
),
customer_favorite_category AS (
	-- Paso 3: Mejor categoria de cada cliente por rentas
	SELECT c.customer_id,
		fav_c.category_id AS fav_category,
		fav_c.total_category_rentals
	FROM customer c
	-- CROSS JOIN LATERAL intencional: excluye clientes sin historial de alquileres
	-- En este dataset todos los clientes tienen al menos un alquiler
	CROSS JOIN LATERAL (
		SELECT ccr.category_id, 
			ccr.total_category_rentals
		FROM customer_category_rentals ccr
		WHERE c.customer_id = ccr.customer_id
		ORDER BY ccr.total_category_rentals DESC, ccr.category_id
		LIMIT 1
	) fav_c
),
global_film_rentals AS (
	-- Paso 4: Total de rentas globales por pelicula y categoria
	SELECT film_id,
		category_id,
		COUNT(rental_id) AS global_rentals
	FROM rental_with_film_category
	GROUP BY film_id, category_id
),
top20_global_category_rentals AS (
	-- Paso 5: Top 20 global de peliculas más alquiladas por cada categoria
	SELECT top.film_id,
		top.global_rentals,
		c.category_id,
		c.name
	FROM category c
	CROSS JOIN LATERAL (
		SELECT gfr.film_id,
			gfr.global_rentals
		FROM global_film_rentals gfr
		WHERE c.category_id = gfr.category_id
		ORDER BY gfr.global_rentals DESC, gfr.film_id
		LIMIT 20
	) top
)

-- Recomendación de 5 peliculas para cada usuario del top 20 global de su categoria favorita
-- y que aún no ha alquilado
SELECT c.customer_id,
	rec.film_id, 
	rec.title, 
	rec.global_rentals,
	rec.category
FROM customer c
INNER JOIN customer_favorite_category cfc
	ON c.customer_id = cfc.customer_id
-- CROSS JOIN LATERAL intencional: excluye clientes sin recomendaciones disponibles
CROSS JOIN LATERAL (
	SELECT f.film_id, 
		f.title, 
		top_gcr.global_rentals,
		top_gcr.name AS category
	FROM top20_global_category_rentals top_gcr
	INNER JOIN film f
		ON top_gcr.film_id = f.film_id
	WHERE top_gcr.category_id = cfc.fav_category
	AND NOT EXISTS (
		SELECT 1
		FROM rental_with_film_category rwfc
		WHERE c.customer_id = rwfc.customer_id
			AND top_gcr.film_id = rwfc.film_id
	)
	ORDER BY top_gcr.global_rentals DESC, top_gcr.film_id
	LIMIT 5
) rec;