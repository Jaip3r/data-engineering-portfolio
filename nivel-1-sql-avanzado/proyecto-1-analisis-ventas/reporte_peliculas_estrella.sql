-- Reporte de peliculas estrella
WITH film_rentals_stats AS (
	-- Paso 1: Número de rentas por pelicula y categoria
	SELECT f.film_id,
		f.title AS film_title,
		fc.category_id,
		COUNT(r.rental_id) AS total_rentals
	FROM rental r
	INNER JOIN inventory i
		ON r.inventory_id = i.inventory_id
	INNER JOIN film f
		ON i.film_id = f.film_id
	INNER JOIN film_category fc
		ON f.film_id = fc.film_id
	GROUP BY f.film_id, f.title, fc.category_id
)

-- Top 3 peliculas más rentables y su porcentaje de contribución a la categoria
SELECT c.name AS category_name,
	best.film_title,
	best.total_rentals,
	best.pct_of_category
FROM category c
CROSS JOIN LATERAL (
	SELECT frs.film_title,
		frs.total_rentals,
		ROUND(100.0 * frs.total_rentals / SUM(frs.total_rentals) OVER(), 2) AS pct_of_category
	FROM film_rentals_stats frs
	WHERE frs.category_id = c.category_id
	ORDER BY frs.total_rentals DESC, frs.film_id
	LIMIT 3
) best;