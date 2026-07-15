SELECT
    c.country,
    p.category,
    YEAR(f.order_date) AS sales_year,
    SUM(f.sales_amount) AS total_sales,
    COUNT(*) AS total_orders,
    AVG(f.sales_amount) AS avg_sales
FROM gold.fact_sales_table f
JOIN gold.dim_customers_table c
    ON f.customer_key = c.customer_key
JOIN gold.dim_products_table p
    ON f.product_key = p.product_key
WHERE f.order_date >= '2012-01-01'
GROUP BY
    c.country,
    p.category,
    YEAR(f.order_date);