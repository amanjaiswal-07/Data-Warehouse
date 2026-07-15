/*
===============================================================================
View: gold.vw_product_360  (Corrected)
===============================================================================
Purpose:
    Provides a 360-degree analytical view of every product.

Business Value:
    - Product Profile
    - Sales Performance
    - Customer Insights
    - Product Profitability
    - Product Segmentation
===============================================================================
*/

IF OBJECT_ID('gold.vw_product_360','V') IS NOT NULL
    DROP VIEW gold.vw_product_360;
GO

CREATE VIEW gold.vw_product_360
AS

/*===========================================================================
Base Data
   -- Joins gold.dim_customers directly (not vw_customer_360) to avoid
      nesting one aggregated view inside another.
===========================================================================*/

WITH base_data AS
(
    SELECT

        p.product_key,
        p.product_id,
        p.product_number,
        p.product_name,
        p.category,
        p.subcategory,
        p.product_line,
        p.maintenance,
        p.cost,
        p.start_date,

        c.customer_key,
        CONCAT(c.first_name,' ',c.last_name) AS customer_name,
        c.country,

        f.order_number,
        f.order_date,
        f.quantity,
        f.sales_amount,
        f.price

    FROM gold.dim_products p

    LEFT JOIN gold.fact_sales f
        ON p.product_key = f.product_key

    LEFT JOIN gold.dim_customers c
        ON f.customer_key = c.customer_key
),

/*===========================================================================
Product Metrics
===========================================================================*/

product_metrics AS
(
SELECT

    product_key,
    product_id,
    product_number,
    product_name,

    category,
    subcategory,
    product_line,
    maintenance,

    cost,
    start_date,

    MIN(order_date) AS first_sale_date,

    MAX(order_date) AS last_sale_date,

    -- +1 so a single-sale product shows a 1-month lifespan, not 0
    CASE
        WHEN MIN(order_date) IS NULL THEN NULL
        ELSE DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) + 1
    END AS product_lifespan_months,

    CASE
        WHEN MAX(order_date) IS NULL THEN NULL
        ELSE DATEDIFF(MONTH, MAX(order_date), GETDATE())
    END AS recency_months,

    COUNT(DISTINCT order_number) AS total_orders,

    COUNT(DISTINCT customer_key) AS total_customers,

    ISNULL(SUM(quantity), 0) AS total_quantity,

    ISNULL(SUM(sales_amount), 0) AS total_revenue,

    -- Quantity-weighted selling price, not a plain AVG(price)
    CAST
    (
        SUM(sales_amount) * 1.0
        / NULLIF(SUM(quantity), 0)
        AS DECIMAL(12,2)
    ) AS average_selling_price,

    CAST
    (
        SUM(sales_amount) * 1.0
        / NULLIF(COUNT(DISTINCT order_number), 0)
        AS DECIMAL(12,2)
    ) AS average_order_revenue,

    CASE
        WHEN MIN(order_date) IS NULL THEN NULL
        ELSE
            CAST
            (
                SUM(sales_amount) * 1.0
                / (DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) + 1)
                AS DECIMAL(12,2)
            )
    END AS average_monthly_revenue,

    -- SUM(A) - SUM(B) instead of SUM(A-B): safe when either column has
    -- NULLs on individual rows
    SUM(sales_amount) - SUM(quantity * cost) AS estimated_profit,

    CAST
    (
        (SUM(sales_amount) - SUM(quantity * cost)) * 100.0
        / NULLIF(SUM(sales_amount), 0)
        AS DECIMAL(10,2)
    ) AS profit_margin

FROM base_data

GROUP BY

    product_key,
    product_id,
    product_number,
    product_name,

    category,
    subcategory,
    product_line,
    maintenance,

    cost,
    start_date

),
/*===========================================================================
Top Customer
===========================================================================*/

top_customer AS
(
    SELECT

        product_key,

        customer_name,

        SUM(sales_amount) AS total_sales,

        ROW_NUMBER() OVER
        (
            PARTITION BY product_key
            ORDER BY
                SUM(sales_amount) DESC,
                customer_name
        ) AS rn

    FROM base_data

    WHERE customer_name IS NOT NULL

    GROUP BY

        product_key,
        customer_name
),

/*===========================================================================
Top Country
===========================================================================*/

top_country AS
(
    SELECT

        product_key,

        country,

        SUM(sales_amount) AS total_sales,

        ROW_NUMBER() OVER
        (
            PARTITION BY product_key
            ORDER BY
                SUM(sales_amount) DESC,
                country
        ) AS rn

    FROM base_data

    WHERE country IS NOT NULL

    GROUP BY

        product_key,
        country
),

/*===========================================================================
Best Selling Month
===========================================================================*/

best_month AS
(
    SELECT

        product_key,

        DATENAME(MONTH,order_date) AS month_name,

        SUM(sales_amount) AS total_sales,

        ROW_NUMBER() OVER
        (
            PARTITION BY product_key
            ORDER BY
                SUM(sales_amount) DESC
        ) AS rn

    FROM base_data

    WHERE order_date IS NOT NULL

    GROUP BY

        product_key,
        DATENAME(MONTH,order_date)
),

/*===========================================================================
Best Selling Weekday
===========================================================================*/

best_weekday AS
(
    SELECT

        product_key,

        DATENAME(WEEKDAY,order_date) AS weekday_name,

        SUM(sales_amount) AS total_sales,

        ROW_NUMBER() OVER
        (
            PARTITION BY product_key
            ORDER BY
                SUM(sales_amount) DESC
        ) AS rn

    FROM base_data

    WHERE order_date IS NOT NULL

    GROUP BY

        product_key,
        DATENAME(WEEKDAY,order_date)
),
/*===========================================================================
Revenue Ranking
===========================================================================*/

revenue_rank AS
(
    SELECT

        product_key,

        DENSE_RANK() OVER
        (
            ORDER BY total_revenue DESC
        ) AS revenue_rank

    FROM product_metrics
),

/*===========================================================================
Quantity Ranking
===========================================================================*/

quantity_rank AS
(
    SELECT

        product_key,

        DENSE_RANK() OVER
        (
            ORDER BY total_quantity DESC
        ) AS quantity_rank

    FROM product_metrics
),

/*===========================================================================
Profit Ranking
===========================================================================*/

profit_rank AS
(
    SELECT

        product_key,

        DENSE_RANK() OVER
        (
            ORDER BY estimated_profit DESC
        ) AS profit_rank

    FROM product_metrics
),

/*===========================================================================
Product Performance
   -- Now considers total_customers alongside revenue/recency, so a
      product's revenue tier reflects how broadly it's adopted, not just
      how much it made.
===========================================================================*/

product_performance AS
(
    SELECT

        product_key,

        CASE

            WHEN total_orders = 0
            THEN 'No Sales'

            WHEN total_revenue >= 100000
                 AND recency_months <= 3
                 AND total_customers >= 20
            THEN 'Star Product'

            WHEN total_revenue >= 100000
                 AND recency_months <= 3
            THEN 'Star Product (Concentrated)'

            WHEN total_revenue >= 50000
                 AND recency_months <= 6
                 AND total_customers >= 10
            THEN 'High Performer'

            WHEN total_revenue >= 50000
                 AND recency_months <= 6
            THEN 'High Performer (Concentrated)'

            WHEN total_revenue >= 10000
            THEN 'Growth Product'

            WHEN total_revenue > 0
            THEN 'Stable Product'

            ELSE 'No Sales'

        END AS performance_segment,

        -- Separates "huge revenue on 1000 customers" from
        -- "huge revenue resting on 1-2 customers"
        CASE
            WHEN total_orders = 0 THEN 'N/A'
            WHEN total_customers <= 1 THEN 'Single Customer Dependency'
            WHEN total_customers <= 5 THEN 'Concentrated'
            ELSE 'Diversified'
        END AS customer_concentration

    FROM product_metrics
),

/*===========================================================================
Product Health
   -- Checks total_orders = 0 first so unsold products are labelled
      'No Sales' instead of 'Inactive'.
===========================================================================*/

product_health AS
(
    SELECT

        product_key,

        CASE

            WHEN total_orders = 0
            THEN 'No Sales'

            WHEN recency_months <= 3
            THEN 'Healthy'

            WHEN recency_months <= 6
            THEN 'Slow Moving'

            WHEN recency_months <= 12
            THEN 'Needs Promotion'

            ELSE 'Inactive'

        END AS health_status

    FROM product_metrics
)
/*===========================================================================
Final Product 360 View
===========================================================================*/

SELECT

    pm.product_key,
    pm.product_id,
    pm.product_number,
    pm.product_name,

    pm.category,
    pm.subcategory,
    pm.product_line,
    pm.maintenance,

    pm.cost,
    pm.start_date,

    ------------------------------------------------------------
    -- Sales KPIs
    ------------------------------------------------------------

    pm.first_sale_date,
    pm.last_sale_date,

    pm.product_lifespan_months,
    pm.recency_months,

    pm.total_orders,
    pm.total_customers,
    pm.total_quantity,

    pm.total_revenue,

    pm.average_selling_price,
    pm.average_order_revenue,
    pm.average_monthly_revenue,

    ------------------------------------------------------------
    -- Profitability
    ------------------------------------------------------------

    pm.estimated_profit,
    pm.profit_margin,

    ------------------------------------------------------------
    -- Customer Insights
    ------------------------------------------------------------

    tc.customer_name     AS top_customer,
    tco.country          AS top_country,

    ------------------------------------------------------------
    -- Time Intelligence
    ------------------------------------------------------------

    bm.month_name        AS best_selling_month,
    bw.weekday_name      AS best_selling_weekday,

    ------------------------------------------------------------
    -- Rankings
    ------------------------------------------------------------

    rr.revenue_rank,
    qr.quantity_rank,
    pr.profit_rank,

    CASE
        WHEN rr.revenue_rank <= 10
        THEN 'Yes'
        ELSE 'No'
    END AS top_10_product,

    ------------------------------------------------------------
    -- Business Intelligence
    ------------------------------------------------------------

    pp.performance_segment,
    pp.customer_concentration,

    ph.health_status

FROM product_metrics pm

LEFT JOIN top_customer tc
ON pm.product_key = tc.product_key
AND tc.rn = 1

LEFT JOIN top_country tco
ON pm.product_key = tco.product_key
AND tco.rn = 1

LEFT JOIN best_month bm
ON pm.product_key = bm.product_key
AND bm.rn = 1

LEFT JOIN best_weekday bw
ON pm.product_key = bw.product_key
AND bw.rn = 1

LEFT JOIN revenue_rank rr
ON pm.product_key = rr.product_key

LEFT JOIN quantity_rank qr
ON pm.product_key = qr.product_key

LEFT JOIN profit_rank pr
ON pm.product_key = pr.product_key

LEFT JOIN product_performance pp
ON pm.product_key = pp.product_key

LEFT JOIN product_health ph
ON pm.product_key = ph.product_key;
GO