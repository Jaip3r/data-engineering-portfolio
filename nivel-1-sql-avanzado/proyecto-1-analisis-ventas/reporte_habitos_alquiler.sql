-- Reporte de hábitos de alquiler
WITH customer_spent_stats AS (
	-- Paso 1: Total gastado por cliente
	SELECT customer_id,
		SUM(amount) AS total_spent
	FROM payment
	GROUP BY customer_id
),
customer_spent_percent AS (
	-- Paso 2: Ranking de clientes en base al total gastado
	SELECT customer_id,
		total_spent,
		PERCENT_RANK() OVER(ORDER BY total_spent DESC) AS spent_percent_rank
	FROM customer_spent_stats
),
vip_customers AS (
	-- Paso 3: Clientes VIP (Top 20% por gasto total)
	SELECT customer_id
	FROM customer_spent_percent
	WHERE spent_percent_rank <= 0.2
)

-- Diferencia de dias entre los 2 pagos mas recientes de cada cliente VIP
SELECT vc.customer_id,
    recent.payment_id,
    recent.amount,
    recent.payment_date,
    recent.days_elapsed
FROM vip_customers vc
CROSS JOIN LATERAL (
	SELECT p.payment_id,
		p.amount,
		p.payment_date,
		p.payment_date - LAG(p.payment_date) OVER (
			PARTITION BY p.customer_id 
			ORDER BY p.payment_date, p.payment_id
		) AS days_elapsed
	FROM payment p
	WHERE p.customer_id = vc.customer_id
	ORDER BY p.payment_id DESC
	LIMIT 2
) recent;