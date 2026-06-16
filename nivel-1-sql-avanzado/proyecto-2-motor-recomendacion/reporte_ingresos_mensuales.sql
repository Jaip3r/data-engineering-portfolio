WITH category_monthly_revenue AS (
	-- Paso 1: Ingresos totales de cada categoria por mes
	SELECT fc.category_id,
		c.name AS category,
		DATE_TRUNC('month', p.payment_date) AS month,
		SUM(p.amount) AS total_revenue
	FROM rental r
	INNER JOIN payment p
		ON r.rental_id = p.rental_id
	INNER JOIN inventory i
		ON r.inventory_id = i.inventory_id
	INNER JOIN film_category fc
		ON i.film_id = fc.film_id
	INNER JOIN category c
		ON fc.category_id = c.category_id
	GROUP BY fc.category_id, c.name, DATE_TRUNC('month', p.payment_date)
), 
last_month AS (
	-- Paso 2: Ubicar el mes del último pago realizado
    SELECT DATE_TRUNC('month', MAX(payment_date)) AS last_month
    FROM payment
)

-- Reporte correspondiente a los últimos 6 meses respecto al mes del último pago realizado
SELECT category,
	MAX(total_revenue) FILTER (WHERE month = last_month - INTERVAL '5 month') AS "Feb 2006",
	MAX(total_revenue) FILTER (WHERE month = last_month - INTERVAL '4 month') AS "Mar 2006",
	MAX(total_revenue) FILTER (WHERE month = last_month - INTERVAL '3 month') AS "Apr 2006",
	MAX(total_revenue) FILTER (WHERE month = last_month - INTERVAL '2 month') AS "May 2006",
	MAX(total_revenue) FILTER (WHERE month = last_month - INTERVAL '1 month') AS "Jun 2006",
	MAX(total_revenue) FILTER (WHERE month = last_month) AS "Jul 2006"
FROM category_monthly_revenue
CROSS JOIN last_month
GROUP BY category;