/*
===============================================================================
Stored Procedure: Load Gold Layer (Silver -> Gold)
===============================================================================
Script Purpose:
    This stored procedure performs the ETL (Extract, Transform, Load) process
    to populate the 'gold' schema tables from the 'silver' schema.

    Actions Performed:
        - Truncates Gold tables.
        - Inserts business-ready dimensional and fact data.

Parameters:
    None.

Usage Example:
    EXEC gold.load_gold;
===============================================================================
*/

CREATE OR ALTER PROCEDURE gold.load_gold
AS
BEGIN

    DECLARE
          @start_time DATETIME
        , @end_time DATETIME
        , @batch_start_time DATETIME
        , @batch_end_time DATETIME;

    BEGIN TRY

        SET @batch_start_time = GETDATE();

        PRINT '================================================';
        PRINT 'Loading Gold Layer';
        PRINT '================================================';

        PRINT '------------------------------------------------';
        PRINT 'Loading Dimension Tables';
        PRINT '------------------------------------------------';

        /*=====================================================================
        Load gold.dim_customers
        =====================================================================*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: gold.dim_customers';

        TRUNCATE TABLE gold.dim_customers;

        PRINT '>> Inserting Data Into: gold.dim_customers';

        INSERT INTO gold.dim_customers
        (
            customer_key,
            customer_id,
            customer_number,
            first_name,
            last_name,
            country,
            marital_status,
            gender,
            birthdate,
            create_date
        )

        SELECT

            ROW_NUMBER() OVER
            (
                ORDER BY cst_id
            ) AS customer_key,

            ci.cst_id,

            ci.cst_key,

            ci.cst_firstname,

            ci.cst_lastname,

            la.cntry,

            ci.cst_marital_status,

            CASE

                WHEN ci.cst_gndr <> 'n/a'

                    THEN ci.cst_gndr

                ELSE COALESCE(ca.gen,'n/a')

            END,

            ca.bdate,

            ci.cst_create_date

        FROM silver.crm_cust_info ci

        LEFT JOIN silver.erp_cust_az12 ca

            ON ci.cst_key = ca.cid

        LEFT JOIN silver.erp_loc_a101 la

            ON ci.cst_key = la.cid;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND,@start_time,@end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> -------------';
        /*=====================================================================
        Load gold.dim_products
        =====================================================================*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: gold.dim_products';

        TRUNCATE TABLE gold.dim_products;

        PRINT '>> Inserting Data Into: gold.dim_products';

        INSERT INTO gold.dim_products
        (
            product_key,
            product_id,
            product_number,
            product_name,
            category_id,
            category,
            subcategory,
            maintenance,
            cost,
            product_line,
            start_date
        )

        SELECT

            ROW_NUMBER() OVER
            (
                ORDER BY
                    pn.prd_start_dt,
                    pn.prd_key
            ) AS product_key,

            pn.prd_id,

            pn.prd_key,

            pn.prd_nm,

            pn.cat_id,

            pc.cat,

            pc.subcat,

            pc.maintenance,

            pn.prd_cost,

            pn.prd_line,

            pn.prd_start_dt

        FROM silver.crm_prd_info pn

        LEFT JOIN silver.erp_px_cat_g1v2 pc

            ON pn.cat_id = pc.id

        WHERE pn.prd_end_dt IS NULL;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND,@start_time,@end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> -------------';
        PRINT '------------------------------------------------';
        PRINT 'Loading Fact Table';
        PRINT '------------------------------------------------';

        /*=====================================================================
        Load gold.fact_sales
        =====================================================================*/

        SET @start_time = GETDATE();

        PRINT '>> Truncating Table: gold.fact_sales';

        TRUNCATE TABLE gold.fact_sales;

        PRINT '>> Inserting Data Into: gold.fact_sales';

        INSERT INTO gold.fact_sales
        (
            order_number,
            product_key,
            customer_key,
            order_date,
            shipping_date,
            due_date,
            sales_amount,
            quantity,
            price
        )

        SELECT

            sd.sls_ord_num,

            dp.product_key,

            dc.customer_key,

            sd.sls_order_dt,

            sd.sls_ship_dt,

            sd.sls_due_dt,

            sd.sls_sales,

            sd.sls_quantity,

            sd.sls_price

        FROM silver.crm_sales_details sd

        LEFT JOIN gold.dim_products dp

            ON sd.sls_prd_key = dp.product_number

        LEFT JOIN gold.dim_customers dc

            ON sd.sls_cust_id = dc.customer_id;

        SET @end_time = GETDATE();

        PRINT '>> Load Duration: '
            + CAST(DATEDIFF(SECOND,@start_time,@end_time) AS NVARCHAR)
            + ' seconds';

        PRINT '>> -------------';
        SET @batch_end_time = GETDATE();

        PRINT '==========================================';
        PRINT 'Loading Gold Layer is Completed';
        PRINT '   - Total Load Duration: '
            + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR)
            + ' seconds';
        PRINT '==========================================';

    END TRY

    BEGIN CATCH

        PRINT '==========================================';
        PRINT 'ERROR OCCURRED DURING LOADING GOLD LAYER';
        PRINT 'Error Message : ' + ERROR_MESSAGE();
        PRINT 'Error Number  : ' + CAST(ERROR_NUMBER() AS NVARCHAR);
        PRINT 'Error State   : ' + CAST(ERROR_STATE() AS NVARCHAR);
        PRINT '==========================================';

    END CATCH

END;
GO