/*
===============================================================================
View: gold.vw_customer_360  (Corrected)
===============================================================================
Purpose:
    Provides a 360-degree analytical view of every customer, including
    customers who have never placed an order.

Business Value:
    - Customer Profile
    - Purchase Behaviour
    - Financial KPIs
    - Customer Preferences
    - Customer Segmentation
    - Seasonality (favourite purchase month)
    - Behaviour drift (last purchased category vs favourite category)

===============================================================================
*/

IF OBJECT_ID('gold.vw_customer_360','V') IS NOT NULL
    DROP VIEW gold.vw_customer_360;
GO

CREATE VIEW gold.vw_customer_360
AS

/*===========================================================================
Base Data
   -- Starts from dim_customers so every customer is represented, even
      those with zero orders. No WHERE filter here; NULLs from the LEFT
      JOINs are handled by the aggregates below (COUNT/SUM ignore NULLs).
===========================================================================*/

WITH base_data AS
(
    SELECT

        c.customer_key,
        c.customer_id,
        c.customer_number,

        CONCAT(c.first_name,' ',c.last_name) AS customer_name,

        c.first_name,
        c.last_name,

        c.gender,
        c.country,
        c.marital_status,
        c.birthdate,
        c.create_date,

        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.product_line,

        f.order_number,
        f.order_date,
        f.sales_amount,
        f.quantity,
        f.price

    FROM gold.dim_customers c

    LEFT JOIN gold.fact_sales f
        ON f.customer_key = c.customer_key

    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
),

/*===========================================================================
Customer Metrics
===========================================================================*/

customer_metrics AS
(

SELECT

    customer_key,
    customer_id,
    customer_number,
    customer_name,
    first_name,
    last_name,
    gender,
    country,
    marital_status,
    birthdate,
    create_date,

    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,

    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS customer_lifespan_months,

    DATEDIFF(DAY, MIN(order_date), MAX(order_date)) AS customer_lifespan_days,

    -- NULL last_order_date (no orders) -> recency stays NULL rather than
    -- comparing GETDATE() to nothing
    CASE
        WHEN MAX(order_date) IS NULL THEN NULL
        ELSE DATEDIFF(MONTH, MAX(order_date), GETDATE())
    END AS recency_months,

    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT product_key) AS total_products,

    ISNULL(SUM(quantity), 0) AS total_quantity,
    ISNULL(SUM(sales_amount), 0) AS total_sales,

    AVG(price) AS average_unit_price,

    CAST(ISNULL(SUM(sales_amount), 0) * 1.0 /
         NULLIF(COUNT(DISTINCT order_number), 0)
         AS DECIMAL(12,2)) AS average_order_value,

    CAST(ISNULL(SUM(quantity), 0) * 1.0 /
         NULLIF(COUNT(DISTINCT order_number), 0)
         AS DECIMAL(12,2)) AS average_items_per_order

FROM base_data

GROUP BY
    customer_key,
    customer_id,
    customer_number,
    customer_name,
    first_name,
    last_name,
    gender,
    country,
    marital_status,
    birthdate,
    create_date

),

/*===========================================================================
Customer Category Preference (favourite, all-time, by revenue)
===========================================================================*/

customer_category AS
(
    SELECT
        customer_key,
        category,
        SUM(sales_amount) AS total_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY SUM(sales_amount) DESC, category
        ) AS rn
    FROM base_data
    WHERE category IS NOT NULL
    GROUP BY customer_key, category
),

/*===========================================================================
Customer Subcategory Preference
===========================================================================*/

customer_subcategory AS
(
    SELECT
        customer_key,
        subcategory,
        SUM(sales_amount) AS total_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY SUM(sales_amount) DESC, subcategory
        ) AS rn
    FROM base_data
    WHERE subcategory IS NOT NULL
    GROUP BY customer_key, subcategory
),

/*===========================================================================
Customer Product Line Preference
===========================================================================*/

customer_product_line AS
(
    SELECT
        customer_key,
        product_line,
        SUM(sales_amount) AS total_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY SUM(sales_amount) DESC, product_line
        ) AS rn
    FROM base_data
    WHERE product_line IS NOT NULL
    GROUP BY customer_key, product_line
),

/*===========================================================================
Customer Favourite Product
   -- Ranked by revenue (sales_amount), not quantity, so a low-volume /
      high-value item correctly outranks a high-volume / low-value one.
===========================================================================*/

customer_favourite_product AS
(
    SELECT
        customer_key,
        product_name,
        SUM(sales_amount) AS total_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY SUM(sales_amount) DESC, product_name
        ) AS rn
    FROM base_data
    WHERE product_name IS NOT NULL
    GROUP BY customer_key, product_name
),

/*===========================================================================
Customer Favourite Purchase Month (seasonality)
===========================================================================*/

customer_month AS
(
    SELECT
        customer_key,
        MONTH(order_date) AS order_month,
        DATENAME(MONTH, order_date) AS month_name,
        SUM(sales_amount) AS total_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY SUM(sales_amount) DESC, MONTH(order_date)
        ) AS rn
    FROM base_data
    WHERE order_date IS NOT NULL
    GROUP BY customer_key, MONTH(order_date), DATENAME(MONTH, order_date)
),

/*===========================================================================
Customer Last Purchased Category
   -- Different from favourite_category: this is the category tied to the
      single most recent order, useful for spotting a shift in behaviour.
===========================================================================*/

customer_last_category AS
(
    SELECT
        customer_key,
        category AS last_category,
        order_date,
        ROW_NUMBER() OVER
        (
            PARTITION BY customer_key
            ORDER BY order_date DESC
        ) AS rn
    FROM base_data
    WHERE order_date IS NOT NULL
)

/*===========================================================================
Final Customer 360 View
===========================================================================*/

SELECT

    cm.customer_key,
    cm.customer_id,
    cm.customer_number,

    cm.first_name,
    cm.last_name,
    cm.customer_name,

    cm.gender,
    cm.country,
    cm.marital_status,

    cm.birthdate,

    -- Accurate Age Calculation, NULL-safe
    CASE
        WHEN cm.birthdate IS NULL THEN NULL
        ELSE
            DATEDIFF(YEAR, cm.birthdate, GETDATE())
            - CASE
                WHEN DATEADD(YEAR,
                             DATEDIFF(YEAR, cm.birthdate, GETDATE()),
                             cm.birthdate) > GETDATE()
                THEN 1
                ELSE 0
              END
    END AS age,

    cm.create_date,

    cm.first_order_date,
    cm.last_order_date,

    cm.customer_lifespan_months,

    cm.recency_months,

    cm.total_orders,
    cm.total_products,
    cm.total_quantity,

    cm.total_sales,

    cm.average_unit_price,

    cm.average_order_value,

    cm.average_items_per_order,

    ------------------------------------------------------------
    -- Average Monthly Spend
    -- NULL only when the customer has never ordered.
    -- Uses total_sales (already a same-month order) when lifespan <= 0.
    ------------------------------------------------------------
    CASE
        WHEN cm.first_order_date IS NULL THEN NULL
        WHEN cm.customer_lifespan_months <= 0 THEN cm.total_sales
        ELSE CAST(cm.total_sales * 1.0 / cm.customer_lifespan_months AS DECIMAL(12,2))
    END AS average_monthly_spend,

    ------------------------------------------------------------
    -- Customer Lifetime Value
    ------------------------------------------------------------

    cm.total_sales AS customer_lifetime_value,

    ------------------------------------------------------------
    -- Purchase Frequency (orders per ~30-day month)
    -- Day-based denominator avoids NULL/zero-division when a customer's
    -- first and last order fall in the same calendar month.
    ------------------------------------------------------------

    CASE
        WHEN cm.first_order_date IS NULL THEN NULL
        WHEN cm.customer_lifespan_days <= 0 THEN CAST(cm.total_orders AS DECIMAL(10,2))
        ELSE CAST(cm.total_orders * 1.0 / (cm.customer_lifespan_days / 30.0) AS DECIMAL(10,2))
    END AS purchase_frequency,

    ------------------------------------------------------------
    -- Customer Preferences
    ------------------------------------------------------------

    cc.category AS favourite_category,

    cs.subcategory AS favourite_subcategory,

    cpl.product_line AS favourite_product_line,

    cp.product_name AS favourite_product,

    cmo.month_name AS favourite_purchase_month,

    clc.last_category AS last_purchased_category,

    ------------------------------------------------------------
    -- Customer Segment
    -- Priority order is intentional: CASE returns the FIRST matching
    -- branch, so this is evaluated top to bottom as a tier hierarchy,
    -- not independent overlapping rules. Recency is checked first
    -- because an inactive customer shouldn't be labelled VIP/Loyal
    -- regardless of historical spend. Customers with no orders fall
    -- through to 'No Purchases' rather than being misclassified 'New'.
    ------------------------------------------------------------

    CASE

        WHEN cm.first_order_date IS NULL
            THEN 'No Purchases'

        WHEN cm.recency_months >= 12
            THEN 'Inactive'

        WHEN cm.total_sales >= 10000
            THEN 'VIP'

        WHEN cm.total_sales >= 5000
            THEN 'High Value'

        WHEN cm.total_orders >= 10
            THEN 'Loyal'

        WHEN cm.total_orders >= 5
            THEN 'Regular'

        ELSE 'New'

    END AS customer_segment

FROM customer_metrics cm

LEFT JOIN customer_category cc
    ON cm.customer_key = cc.customer_key
    AND cc.rn = 1

LEFT JOIN customer_subcategory cs
    ON cm.customer_key = cs.customer_key
    AND cs.rn = 1

LEFT JOIN customer_product_line cpl
    ON cm.customer_key = cpl.customer_key
    AND cpl.rn = 1

LEFT JOIN customer_favourite_product cp
    ON cm.customer_key = cp.customer_key
    AND cp.rn = 1

LEFT JOIN customer_month cmo
    ON cm.customer_key = cmo.customer_key
    AND cmo.rn = 1

LEFT JOIN customer_last_category clc
    ON cm.customer_key = clc.customer_key
    AND clc.rn = 1;
GO