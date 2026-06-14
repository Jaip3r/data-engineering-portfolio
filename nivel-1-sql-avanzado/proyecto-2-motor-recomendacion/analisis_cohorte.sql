WITH user_cohort_month AS (
	-- Paso 1: Ubicar el mes en que cada cliente realizó su primer alquiler
	SELECT customer_id,
		DATE_TRUNC('month', MIN(rental_date)) AS cohort
	FROM rental
	GROUP BY customer_id
),
cohort_relative_user_count AS (
	-- Paso 2: Conteo de clientes únicos por mes relativo y cohorte
	SELECT TO_CHAR(ucm.cohort, 'YYYY-MM') AS cohort_month,
		(EXTRACT(YEAR FROM r.rental_date) - EXTRACT(YEAR FROM ucm.cohort)) * 12
		+ (EXTRACT(MONTH FROM r.rental_date) - EXTRACT(MONTH FROM ucm.cohort)) AS relative_month,
		COUNT(DISTINCT r.customer_id) AS unique_customers
	FROM rental r
	INNER JOIN user_cohort_month ucm
		ON r.customer_id = ucm.customer_id
	GROUP BY cohort_month, relative_month
)

-- Reporte pivotado para los primeros 4 meses
SELECT cohort_month,
	SUM(CASE WHEN relative_month = 0 THEN unique_customers ELSE 0 END) AS month_0,
	SUM(CASE WHEN relative_month = 1 THEN unique_customers ELSE 0 END) AS month_1,
	SUM(CASE WHEN relative_month = 2 THEN unique_customers ELSE 0 END) AS month_2,
	SUM(CASE WHEN relative_month = 3 THEN unique_customers ELSE 0 END) AS month_3,
	SUM(CASE WHEN relative_month = 4 THEN unique_customers ELSE 0 END) AS month_4
FROM cohort_relative_user_count
GROUP BY cohort_month
ORDER BY cohort_month;