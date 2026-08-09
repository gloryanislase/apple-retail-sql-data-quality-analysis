-- Analysis 9: Time-to-Failure
SELECT
    c.category_name,
    ROUND(AVG(w.claim_date - s.sale_date),2) AS avg_days_to_failure,
    COUNT(w.claim_id) AS claims_used
FROM warranty w
JOIN sales s ON w.sale_id = s.sale_id
JOIN products p ON s.product_id = p.product_id
JOIN category c ON p.category_id = c.category_id
WHERE w.claim_date >= s.sale_date                              -- exclude klaim tidak valid
  AND c.category_name NOT IN ('Subscription Service','Streaming Device')  -- exclude kategori non-fisik
GROUP BY c.category_name
ORDER BY avg_days_to_failure ASC;

-- Analysis 10 : Store Anomaly Detection
WITH StoreIdentity AS (
    -- Menggabungkan store_id yang merujuk ke toko fisik sama (nama+kota+negara identik)
    SELECT store_id, store_name, city, country,
           MIN(store_id) OVER (PARTITION BY store_name, city, country) AS canonical_store_id
    FROM stores
),
StoreSales AS (
    SELECT si.canonical_store_id, si.store_name, si.country, SUM(s.quantity) AS total_units_sold
    FROM sales s
    JOIN StoreIdentity si ON s.store_id = si.store_id
    GROUP BY si.canonical_store_id, si.store_name, si.country
),
StoreWarranty AS (
    SELECT si.canonical_store_id, COUNT(w.claim_id) AS total_claims
    FROM warranty w
    JOIN sales s ON w.sale_id = s.sale_id
    JOIN StoreIdentity si ON s.store_id = si.store_id
    WHERE w.claim_date >= s.sale_date
    GROUP BY si.canonical_store_id
)
SELECT
    ss.store_name, ss.country, ss.total_units_sold,
    COALESCE(sw.total_claims, 0) AS total_claims,
    ROUND((COALESCE(sw.total_claims,0)*100.0)/ss.total_units_sold,2) AS warranty_claim_ratio
FROM StoreSales ss
LEFT JOIN StoreWarranty sw ON ss.canonical_store_id = sw.canonical_store_id
ORDER BY warranty_claim_ratio DESC;

-- Analysis 11: Cost Assessment (Free Repairs)
SELECT
    p.product_name,
    COUNT(w.claim_id) AS total_free_repairs,
    SUM(p.price) AS estimated_cost_burden
FROM warranty w
JOIN sales s ON w.sale_id = s.sale_id
JOIN products p ON s.product_id = p.product_id
JOIN category c ON p.category_id = c.category_id
WHERE w.repair_status NOT IN ('Warranty Void','Paid Repaired')
  AND w.claim_date >= s.sale_date
  AND c.category_name NOT IN ('Subscription Service','Streaming Device')
GROUP BY p.product_name
ORDER BY estimated_cost_burden DESC;

-- Analysis 12a : Launch Batch Quality
WITH SalesCohorts AS (
    SELECT
        s.sale_id, s.sale_date, p.product_name,
        (s.sale_date - p.launch_date) AS days_since_launch,
        CASE
            WHEN (s.sale_date - p.launch_date) <= 30 THEN 'The First 30 Days'
            WHEN (s.sale_date - p.launch_date) > 90 THEN 'After 3 Months'
            ELSE 'Lainnya'
        END AS launch_cohort
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    WHERE s.sale_date >= p.launch_date
),
CohortClaims AS(
    SELECT
        sc.product_name, sc.launch_cohort,
        COUNT(sc.sale_id) AS total_sales,
        COUNT(w.claim_id) AS total_claims
    FROM SalesCohorts sc
    LEFT JOIN warranty w ON sc.sale_id = w.sale_id AND w.claim_date >= sc.sale_date
    WHERE sc.launch_cohort IN ('The First 30 Days', 'After 3 Months')
    GROUP BY sc.product_name, sc.launch_cohort
)
SELECT
    product_name, launch_cohort, total_sales, total_claims,
    ROUND((total_claims * 100.0)/NULLIF(total_sales,0),2) AS claim_ratio
FROM CohortClaims
ORDER BY product_name, launch_cohort;

-- Analysis 12b: Summary — rata-rata claim ratio per cohort (across all products)
WITH SalesCohorts AS (
    SELECT
        s.sale_id, s.sale_date, p.product_name,
        CASE
            WHEN (s.sale_date - p.launch_date) <= 30 THEN 'The First 30 Days'
            WHEN (s.sale_date - p.launch_date) > 90 THEN 'After 3 Months'
            ELSE 'Lainnya'
        END AS launch_cohort
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    WHERE s.sale_date >= p.launch_date
),
CohortClaims AS(
    SELECT
        sc.product_name, sc.launch_cohort,
        COUNT(sc.sale_id) AS total_sales,
        COUNT(w.claim_id) AS total_claims
    FROM SalesCohorts sc
    LEFT JOIN warranty w ON sc.sale_id = w.sale_id AND w.claim_date >= sc.sale_date
    WHERE sc.launch_cohort IN ('The First 30 Days', 'After 3 Months')
    GROUP BY sc.product_name, sc.launch_cohort
)
SELECT
    launch_cohort,
    SUM(total_sales) AS total_sales_all_products,
    SUM(total_claims) AS total_claims_all_products,
    ROUND(SUM(total_claims) * 100.0 / SUM(total_sales), 2) AS overall_claim_ratio
FROM CohortClaims
GROUP BY launch_cohort;

-- Diagnostic 1: Apakah ada klaim garansi untuk sale_date > claim_date (klaim sebelum beli)?
SELECT COUNT(*) AS invalid_claims,
       (SELECT COUNT(*) FROM warranty) AS total_claims,
       ROUND(COUNT(*)*100.0/(SELECT COUNT(*) FROM warranty),2) AS pct_invalid
FROM warranty w
JOIN sales s ON w.sale_id = s.sale_id
WHERE w.claim_date < s.sale_date;

-- Diagnostic 2: Berapa banyak klaim garansi terkait kategori non-fisik (Subscription Service, Streaming Device)?
SELECT c.category_name, COUNT(w.claim_id) AS claim_count
FROM warranty w
JOIN sales s ON w.sale_id = s.sale_id
JOIN products p ON s.product_id = p.product_id
JOIN category c ON p.category_id = c.category_id
WHERE c.category_name IN ('Subscription Service', 'Streaming Device')
GROUP BY c.category_name;


-- Diagnostic 3 : Apakah toko dengan nama sama juga punya city/country sama persis (indikasi duplikat)?
SELECT store_name, city, country, COUNT(*) AS occurrence, STRING_AGG(store_id::text, ', ') AS store_ids
FROM stores
WHERE store_name IN (
    'Apple The Dubai Mall', 'Apple Champs-Elysees', 'Apple Orchard Road',
    'Apple Central World', 'Apple Covent Garden', 'Apple Chadstone'
)
GROUP BY store_name, city, country
ORDER BY store_name;