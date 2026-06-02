-- Reporte de rendimiento por geografia
SELECT CASE WHEN GROUPING(co.country) = 1 THEN 'ALL COUNTRIES' ELSE co.country END AS country,
	CASE WHEN GROUPING(ci.city) = 1 THEN 'ALL CITIES' ELSE ci.city END AS city,
	SUM(p.amount) AS total_revenue
FROM payment p
INNER JOIN customer c
	ON p.customer_id = c.customer_id
INNER JOIN address a
	ON c.address_id = a.address_id
INNER JOIN city ci
	ON a.city_id = ci.city_id
INNER JOIN country co
	ON ci.country_id = co.country_id
GROUP BY ROLLUP(co.country, ci.city)
ORDER BY GROUPING(co.country), co.country, GROUPING(ci.city), ci.city;