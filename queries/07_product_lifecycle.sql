-- Analysis 5 : New Product Dependency Analysis, excluding invalid pre-launch transactions
WITH Sales2023 AS (
    SELECT
        s.quantity * p.price AS revenue,
        EXTRACT(YEAR FROM p.launch_date) AS launch_year
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    WHERE EXTRACT(YEAR FROM s.sale_date) = 2023
      AND s.sale_date >= p.launch_date
),
ProductStatus AS (
    SELECT
        CASE WHEN launch_year = 2023 THEN 'New Product in 2023' ELSE 'Legacy Product (<2023)' END AS product_group,
        revenue
    FROM Sales2023
),
GroupedRevenue AS (
    SELECT product_group, SUM(revenue) AS total_revenue
    FROM ProductStatus GROUP BY product_group
),
GlobalRevenue2023 AS (
    SELECT SUM(total_revenue) AS grand_total FROM GroupedRevenue
)
SELECT g.product_group, g.total_revenue, ROUND((g.total_revenue*100.0)/t.grand_total,2) AS percentage_contribution
FROM GroupedRevenue g CROSS JOIN GlobalRevenue2023 t;

-- Analysis 6a: Product Adoption Speed - Detail per Product
-- Excludes pre-launch invalid transactions (sale_date < launch_date)
-- Excludes products launched <6 months before data cutoff (2024-11-12) to avoid right-censoring bias
WITH MonthlyProductSales AS (
    SELECT
        p.product_name, p.launch_date,
        EXTRACT(YEAR FROM s.sale_date) AS sales_year,
        EXTRACT(MONTH FROM s.sale_date) AS sales_month,
        SUM(s.quantity) AS total_sold
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    WHERE s.sale_date >= p.launch_date
      AND p.launch_date <= '2024-05-12'
    GROUP BY p.product_name, p.launch_date, EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
),
RankedSales AS (
    SELECT
        product_name, launch_date, sales_year, sales_month, total_sold,
        RANK() OVER(PARTITION BY product_name ORDER BY total_sold DESC) AS rank_sales
    FROM MonthlyProductSales
)
SELECT
    product_name, launch_date, sales_year AS peak_year, sales_month AS peak_month,
    total_sold AS peak_sales_volume,
    ((sales_year - EXTRACT(YEAR FROM launch_date)) * 12) + (sales_month - EXTRACT(MONTH FROM launch_date)) AS months_to_peak
FROM RankedSales
WHERE rank_sales = 1
ORDER BY months_to_peak ASC;


-- Analysis 6b: Product Adoption Speed - Summary Statistics
-- Same filtering logic as 6a, aggregated into overall adoption speed metrics
WITH MonthlyProductSales AS (
    SELECT
        p.product_name, p.launch_date,
        EXTRACT(YEAR FROM s.sale_date) AS sales_year,
        EXTRACT(MONTH FROM s.sale_date) AS sales_month,
        SUM(s.quantity) AS total_sold
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    WHERE s.sale_date >= p.launch_date
      AND p.launch_date <= '2024-05-12'
    GROUP BY p.product_name, p.launch_date, EXTRACT(YEAR FROM s.sale_date), EXTRACT(MONTH FROM s.sale_date)
),
RankedSales AS (
    SELECT
        product_name, launch_date, sales_year, sales_month, total_sold,
        RANK() OVER(PARTITION BY product_name ORDER BY total_sold DESC) AS rank_sales
    FROM MonthlyProductSales
),
FinalResult AS (
    SELECT
        product_name,
        ((sales_year - EXTRACT(YEAR FROM launch_date)) * 12) + (sales_month - EXTRACT(MONTH FROM launch_date)) AS months_to_peak
    FROM RankedSales
    WHERE rank_sales = 1
)
SELECT
    ROUND(AVG(months_to_peak), 1) AS avg_months_to_peak,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY months_to_peak) AS median_months_to_peak,
    MIN(months_to_peak) AS fastest,
    MAX(months_to_peak) AS slowest
FROM FinalResult;

-- Analysis 7 : Product Cannibalization, excluding pre-launch invalid transactions
WITH LaunchData AS(
    SELECT
        product_id AS new_product_id, product_name AS new_product_name, category_id, launch_date,
        (EXTRACT(YEAR FROM launch_date)*12) + EXTRACT(MONTH FROM launch_date) AS abs_launch_month
    FROM products
),
LegacySales AS(
    SELECT
        ld.new_product_id,
        ((EXTRACT(YEAR FROM s.sale_date)*12)+EXTRACT(MONTH FROM s.sale_date)) AS abs_sale_month,
        SUM(s.quantity) AS legacy_units_sold
    FROM LaunchData ld
    JOIN products p_legacy ON ld.category_id = p_legacy.category_id AND p_legacy.launch_date < ld.launch_date
    JOIN sales s ON p_legacy.product_id = s.product_id AND s.sale_date >= p_legacy.launch_date
    GROUP BY ld.new_product_id, ((EXTRACT(YEAR FROM s.sale_date)*12) + EXTRACT(MONTH FROM s.sale_date))
),
ImpactAnalysis AS (
    SELECT
        ld.new_product_name, ld.launch_date,
        COALESCE(MAX(CASE WHEN ls.abs_sale_month=ld.abs_launch_month-1 THEN ls.legacy_units_sold END),0) AS sales_before,
        COALESCE(MAX(CASE WHEN ls.abs_sale_month=ld.abs_launch_month+1 THEN ls.legacy_units_sold END),0) AS sales_after
    FROM LaunchData ld
    LEFT JOIN LegacySales ls ON ld.new_product_id = ls.new_product_id
    GROUP BY ld.new_product_name, ld.launch_date, ld.abs_launch_month
)
SELECT
    new_product_name, launch_date, sales_before, sales_after,
    CASE WHEN sales_before = 0 THEN 0 ELSE ROUND(((sales_after-sales_before)*100.0)/sales_before,2) END AS cannibalization_percentage
FROM ImpactAnalysis
WHERE sales_before > 0 OR sales_after > 0
ORDER BY cannibalization_percentage ASC;

--Analysis 8: Local Product Failures (Top 5 in one country, Bottom 10 in another)
WITH CountryProductSales AS(
    SELECT
        st.country,
        p.product_name,
        SUM(s.quantity) AS total_sold
    FROM sales s
    JOIN stores st ON s.store_id = st.store_id
    JOIN products p ON s.product_id = p.product_id
    GROUP BY st.country, p.product_name
),
RankedProducts AS (
    SELECT
        country,
        product_name,
        total_sold,
        RANK() OVER(PARTITION BY country ORDER BY total_sold DESC) AS rank_top,
        RANK() OVER(PARTITION BY country ORDER BY total_sold ASC) AS rank_bottom
    FROM CountryProductSales
),
TopSellers AS (
    SELECT
        country AS top_country,
        product_name,
        total_sold AS top_sold,
        rank_top
    FROM RankedProducts
    WHERE rank_top <= 5
),
BottomSellers AS (
    SELECT
        country AS bottom_country,
        product_name,
        total_sold AS bottom_sold,
        rank_bottom
    FROM RankedProducts
    WHERE rank_bottom <= 10
)
SELECT
    t.product_name,
    t.top_country,
    t.rank_top,
    t.top_sold,
    b.bottom_country,
    b.rank_bottom,
    b.bottom_sold
FROM TopSellers t
JOIN BottomSellers b ON t.product_name = b.product_name
WHERE t.top_country != b.bottom_country
ORDER BY t.product_name, t.top_country;


-- Diagnostic: Berapa % transaksi sales yang terjadi SEBELUM launch_date produknya?
SELECT
    COUNT(*) AS invalid_sales_count,
    (SELECT COUNT(*) FROM sales) AS total_sales_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM sales), 2) AS pct_invalid
FROM sales s
JOIN products p ON s.product_id = p.product_id
WHERE s.sale_date < p.launch_date;

-- Diagnostic: Apakah ada penjualan 2023 untuk produk yang launch_date-nya di 2024 atau lebih baru?
SELECT p.product_name, p.launch_date, COUNT(*) AS invalid_2023_sales
FROM sales s
JOIN products p ON s.product_id = p.product_id
WHERE EXTRACT(YEAR FROM s.sale_date) = 2023 
  AND p.launch_date > s.sale_date
GROUP BY p.product_name, p.launch_date
ORDER BY invalid_2023_sales DESC;

-- Diagnostic: Berapa revenue 2023 yang berasal dari transaksi TIDAK VALID (launch_date > sale_date)?
SELECT
    SUM(s.quantity * p.price) AS invalid_revenue_2023,
    (SELECT SUM(s2.quantity * p2.price) 
     FROM sales s2 JOIN products p2 ON s2.product_id = p2.product_id
     WHERE EXTRACT(YEAR FROM s2.sale_date) = 2023) AS total_revenue_2023,
    ROUND(
        SUM(s.quantity * p.price) * 100.0 / 
        (SELECT SUM(s2.quantity * p2.price) 
         FROM sales s2 JOIN products p2 ON s2.product_id = p2.product_id
         WHERE EXTRACT(YEAR FROM s2.sale_date) = 2023), 2
    ) AS pct_of_2023_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
WHERE EXTRACT(YEAR FROM s.sale_date) = 2023 
  AND p.launch_date > s.sale_date;