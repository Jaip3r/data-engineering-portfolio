-- Reporte clientes VIP
WITH customer_totals AS (
	-- Paso 1: Total gastado por cliente
	SELECT customer_id, SUM(amount) AS total_spent
    FROM payment
    GROUP BY customer_id
),
customer_spent_rank AS (
	-- Paso 2: Ranking de clientes en base al total gastado
	SELECT customer_id,
		total_spent,
		DENSE_RANK() OVER r AS spent_rank,
		PERCENT_RANK() OVER r AS spent_percent_rank
	FROM customer_totals
	WINDOW r AS (ORDER BY total_spent DESC)
),
vip_only AS (
	-- Paso 3: Clientes VIP (Top 20% por gasto total) 
	SELECT customer_id, 
		total_spent, 
		spent_rank 
	FROM customer_spent_rank
	WHERE spent_percent_rank <= 0.20
),
vip_monthly_stats AS (
	-- Paso 4: Total gastado por cliente y mes (solo VIPs)
	SELECT customer_id, 
        DATE_TRUNC('month', payment_date) AS month,
        SUM(amount) AS monthly_spent
    FROM payment p
	WHERE EXISTS (
		SELECT 1 
		FROM vip_only vo
		WHERE vo.customer_id = p.customer_id
	)
    GROUP BY customer_id, DATE_TRUNC('month', payment_date)
)

-- Tendencia respecto al mes anterior y gasto acumulado mes a mes
SELECT vms.customer_id,
	c.first_name || ' ' || c.last_name AS full_name,
	vms.month,
	vms.monthly_spent AS curr_monthly_spent,
	LAG(vms.monthly_spent, 1, 0) OVER w AS prev_monthly_spent,
	CASE
		WHEN vms.monthly_spent > LAG(vms.monthly_spent) OVER w THEN 'SUBE'
		WHEN vms.monthly_spent < LAG(vms.monthly_spent) OVER w THEN 'BAJA'
		WHEN vms.monthly_spent = LAG(vms.monthly_spent) OVER w THEN 'IGUAL'
		ELSE 'PRIMER PAGO'
	END AS trend,
	SUM(vms.monthly_spent) OVER w AS running_total,
	vo.total_spent,
	vo.spent_rank
FROM vip_monthly_stats vms
INNER JOIN vip_only vo
	ON vms.customer_id = vo.customer_id
INNER JOIN customer c
	ON vms.customer_id = c.customer_id
WINDOW w AS (PARTITION BY vms.customer_id ORDER BY vms.month)
ORDER BY vo.spent_rank, vms.month;