-- Benchmark Query
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

-- Reset Environment
DROP INDEX IF EXISTS IX_fact_sales_customer_key
ON gold.fact_sales_table;
GO

DROP INDEX IF EXISTS IX_fact_sales_product_key
ON gold.fact_sales_table;
GO

DROP INDEX IF EXISTS IX_fact_sales_order_date
ON gold.fact_sales_table;
GO

DROP INDEX IF EXISTS CCI_fact_sales
ON gold.fact_sales_table;
GO

-- Verify
SELECT
    name,
    type_desc
FROM sys.indexes
WHERE object_id = OBJECT_ID('gold.fact_sales_table');

-- Stage 1 — Baseline || Turn on Actual Execution Plan (Ctrl + M).
SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- Stage 2 — Nonclustered Indexes
CREATE NONCLUSTERED INDEX IX_fact_sales_customer_key
ON gold.fact_sales_table(customer_key);
GO

CREATE NONCLUSTERED INDEX IX_fact_sales_product_key
ON gold.fact_sales_table(product_key);
GO

CREATE NONCLUSTERED INDEX IX_fact_sales_order_date
ON gold.fact_sales_table(order_date);
GO

-- Stage 3 — Covering Index
DROP INDEX IX_fact_sales_customer_key
ON gold.fact_sales_table;
GO

DROP INDEX IX_fact_sales_product_key
ON gold.fact_sales_table;
GO

DROP INDEX IX_fact_sales_order_date
ON gold.fact_sales_table;
GO

CREATE NONCLUSTERED INDEX IX_fact_sales_covering
ON gold.fact_sales_table(order_date)
INCLUDE
(
    customer_key,
    product_key,
    sales_amount
);
GO

-- Stage 4 — Clustered Columnstore Index
DROP INDEX IF EXISTS IX_fact_sales_covering
ON gold.fact_sales_table;
GO
CREATE CLUSTERED COLUMNSTORE INDEX CCI_fact_sales
ON gold.fact_sales_table;
GO