/*
===============================================================================
DDL Script: Create Gold Tables
===============================================================================
Script Purpose:
    This script creates the physical tables in the 'gold' schema, dropping
    existing tables if they already exist.

    The Gold layer represents the Business Presentation Layer of the Data
    Warehouse.

    Unlike Gold Views, these tables physically store the dimensional model
    and fact data, allowing advanced SQL Server optimizations such as:

        - Clustered / Nonclustered Indexes
        - Clustered Columnstore Indexes
        - Table Partitioning
        - Query Performance Tuning

Notes on this revision:
    - No FOREIGN KEY constraints on gold.fact_sales. gold.load_gold uses
      TRUNCATE TABLE on the dimension tables, and SQL Server refuses to
      truncate a table that is referenced by an FK, regardless of whether
      the referencing table currently has rows. Referential integrity here
      is enforced by the ETL join logic instead of the engine. If you want
      the engine to enforce it, switch the dimension truncates to DELETE
      and re-add the FK constraints.
    - product_key / customer_key on gold.fact_sales are nullable, matching
      the LEFT JOINs in gold.load_gold: a sales record with no matching
      product or customer still loads, with a NULL key, instead of failing
      the entire batch insert.
    - fact_sales has no PRIMARY KEY. A composite key on
      (order_number, product_key, customer_key) assumes a source order
      never has two line items for the same product/customer combination
      (e.g. a split shipment or a price change mid-order) — validate that
      assumption against your actual data before adding one. Nonclustered
      indexes on the two key columns are added instead, for join
      performance without that risk.

Usage:
    Run this script once to create the Gold Tables.
===============================================================================
*/

-- =============================================================================
-- Create Table: gold.dim_customers
-- =============================================================================

IF OBJECT_ID('gold.dim_customers','U') IS NOT NULL
    DROP TABLE gold.dim_customers;
GO

CREATE TABLE gold.dim_customers
(
    customer_key       INT             NOT NULL,
    customer_id        INT             NOT NULL,
    customer_number    NVARCHAR(50),
    first_name         NVARCHAR(50),
    last_name          NVARCHAR(50),
    country            NVARCHAR(50),
    marital_status     NVARCHAR(50),
    gender             NVARCHAR(50),
    birthdate          DATE,
    create_date        DATE,

    CONSTRAINT PK_dim_customers
        PRIMARY KEY CLUSTERED (customer_key)
);
GO

-- =============================================================================
-- Create Table: gold.dim_products
-- =============================================================================

IF OBJECT_ID('gold.dim_products','U') IS NOT NULL
    DROP TABLE gold.dim_products;
GO

CREATE TABLE gold.dim_products
(
    product_key        INT             NOT NULL,
    product_id         INT             NOT NULL,
    product_number     NVARCHAR(50),
    product_name       NVARCHAR(100),
    category_id        NVARCHAR(50),
    category           NVARCHAR(50),
    subcategory        NVARCHAR(50),
    maintenance        NVARCHAR(50),
    cost               INT,
    product_line       NVARCHAR(50),
    start_date         DATE,

    CONSTRAINT PK_dim_products
        PRIMARY KEY CLUSTERED (product_key)
);
GO

-- =============================================================================
-- Create Table: gold.fact_sales
-- =============================================================================

IF OBJECT_ID('gold.fact_sales','U') IS NOT NULL
    DROP TABLE gold.fact_sales;
GO

CREATE TABLE gold.fact_sales
(
    order_number      NVARCHAR(50)    NOT NULL,
    product_key       INT             NULL,  -- nullable: LEFT JOIN in load_gold can leave this unmatched
    customer_key      INT             NULL,  -- nullable: LEFT JOIN in load_gold can leave this unmatched

    order_date        DATE,
    shipping_date     DATE,
    due_date          DATE,

    sales_amount      INT,
    quantity          INT,
    price             INT
);
GO
