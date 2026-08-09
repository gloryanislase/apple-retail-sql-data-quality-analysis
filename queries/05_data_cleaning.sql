-- detect duplicate data in sales table
SELECT sale_id, COUNT(*) AS duplicate_count
FROM sales
GROUP BY sale_id
HAVING COUNT(*)>1;

--detect duplicate data in stores table
SELECT store_id, COUNT(*) AS duplicate_store
FROM stores
GROUP BY store_id
HAVING COUNT(*)>1;

--detect duplicate data in products table
SELECT product_id, COUNT(*) AS duplicate_product
FROM products
GROUP BY product_id
HAVING COUNT(*)>1;

-- Checking for missing data for stores, products, and date in sales table
SELECT
    SUM(CASE WHEN store_id IS NULL THEN 1 ELSE 0 END) AS missing_store,
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END) AS missing_product,
    SUM(CASE WHEN sale_date IS NULL THEN 1 ELSE 0 END) AS missing_sale_date
FROM sales;

-- Checking for empty rows in warranty table
SELECT 
    SUM(CASE WHEN claim_date IS NULL THEN 1 ELSE 0 END) AS missing_claim_date,
    SUM(CASE WHEN sale_id IS NULL THEN 1 ELSE 0 END) AS missing_sale_id
FROM warranty;