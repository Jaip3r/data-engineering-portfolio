-- Perfil del cliente
WITH rental_with_film AS (
	-- Paso 1: Ubicar la pelicula asociada a cada renta
	SELECT r.customer_id,
		r.rental_id,
		i.film_id
	FROM rental r
	INNER JOIN inventory i ON r.inventory_id = i.inventory_id
),
customer_category_rentals AS (
	-- Paso 2: Total de rentas por cliente y categoria
	SELECT rwf.customer_id,
		fc.category_id,
		COUNT(rwf.rental_id) AS total_category_rentals
	FROM rental_with_film rwf 
	INNER JOIN film_category fc
		ON rwf.film_id = fc.film_id
	GROUP BY rwf.customer_id, fc.category_id
),
customer_actor_rentals AS (
	-- Paso 3: Total de rentas por cliente y actor
	SELECT rwf.customer_id,
		fa.actor_id,
		COUNT(rwf.rental_id) AS total_actor_rentals
	FROM rental_with_film rwf
	INNER JOIN film_actor fa
		ON rwf.film_id = fa.film_id
	GROUP BY rwf.customer_id, fa.actor_id
),
customer_favorite_category AS (
	-- Paso 4: Mejor categoria de cada cliente por rentas
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
		ORDER BY total_category_rentals DESC, category_id
		LIMIT 1
	) fav_c
),
customer_favorite_actor AS (
	-- Paso 5: Mejor actor de cada cliente por rentas
	SELECT c.customer_id,
		fav_a.actor_id AS fav_actor,
		fav_a.total_actor_rentals
	FROM customer c
	-- CROSS JOIN LATERAL intencional: excluye clientes sin historial de alquileres
	-- En este dataset todos los clientes tienen al menos un alquiler
	CROSS JOIN LATERAL (
		SELECT car.actor_id,
			car.total_actor_rentals
		FROM customer_actor_rentals car
		WHERE c.customer_id = car.customer_id
		ORDER BY car.total_actor_rentals DESC, car.actor_id
		LIMIT 1
	) fav_a
),
customer_window_activity AS (
	-- Paso 6: Dias entre el primer y último alquiler de cada cliente
	SELECT customer_id,
		MAX(rental_date) - MIN(rental_date) AS window_activity
	FROM rental
	GROUP BY customer_id
)

SELECT cfc.customer_id,
	cu.first_name || ' ' || cu.last_name AS customer_name,
	cat.name AS favorite_category,
	cfc.total_category_rentals AS favorite_category_rentals,
	act.first_name || ' ' || act.last_name AS favorite_actor,
	cfa.total_actor_rentals AS favorite_actor_rentals,
	cwa.window_activity
FROM customer_favorite_category cfc
INNER JOIN customer_favorite_actor cfa
	ON cfc.customer_id = cfa.customer_id
INNER JOIN customer_window_activity cwa
	ON cfc.customer_id = cwa.customer_id
INNER JOIN customer cu 
	ON cfc.customer_id = cu.customer_id
INNER JOIN category cat 
	ON cfc.fav_category = cat.category_id
INNER JOIN actor act 
	ON cfa.fav_actor = act.actor_id;