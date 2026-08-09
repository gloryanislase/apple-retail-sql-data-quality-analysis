-- Analysis 1a : Total Revenue by Product Category
SELECT
    c.category_name,
    SUM(s.quantity*p.price) AS total_revenue
FROM sales s
JOIN products p ON s.product_id = p.product_id
JOIN category c ON p.category_id = c.category_id
GROUP BY c.category_name
ORDER BY total_revenue DESC;

-- Analysis 1b : Which category grew the fastest?
-- Ranked by average YoY growth 2021-2024 (2024 growth uses annualized revenue for fairness)
WITH YearlyRevenue AS (
    SELECT
        c.category_name,
        EXTRACT(YEAR FROM s.sale_date) AS sales_year,
        SUM(s.quantity * p.price) AS revenue
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    JOIN category c ON p.category_id = c.category_id
    GROUP BY c.category_name, EXTRACT(YEAR FROM s.sale_date)
),
Adjusted AS (
    SELECT
        category_name,
        sales_year,
        CASE WHEN sales_year = 2024 THEN ROUND(revenue / 317.0 * 366, 0) ELSE revenue END AS revenue_for_comparison
    FROM YearlyRevenue
),
GrowthByYear AS (
    SELECT
        category_name,
        sales_year,
        revenue_for_comparison,
        ROUND(
            (revenue_for_comparison - LAG(revenue_for_comparison) OVER (PARTITION BY category_name ORDER BY sales_year)) /
            NULLIF(LAG(revenue_for_comparison) OVER (PARTITION BY category_name ORDER BY sales_year), 0) * 100, 2
        ) AS growth_percentage
    FROM Adjusted
)
SELECT
    category_name,
    ROUND(AVG(growth_percentage), 2) AS avg_yearly_growth_pct,
    RANK() OVER (ORDER BY AVG(growth_percentage) DESC) AS growth_rank
FROM GrowthByYear
WHERE growth_percentage IS NOT NULL
GROUP BY category_name
ORDER BY avg_yearly_growth_pct DESC;

-- Analysis 2a : Global Monthly Sales Trend
-- Excludes 2024 (partial year, only through Nov 12) to keep monthly comparison fair across full years only
SELECT
    EXTRACT(MONTH FROM sale_date) AS month,
    SUM(quantity) AS total_units_sold
FROM sales
WHERE sale_date < '2024-01-01'
GROUP BY EXTRACT(MONTH FROM sale_date)
ORDER BY total_units_sold DESC;

-- Analysis 2b (Extended): Top 3 months per country instead of single peak
WITH MonthlySalesCountry AS (
    SELECT
        st.country, 
        EXTRACT(MONTH FROM s.sale_date) AS month,
        SUM(s.quantity) AS total_units
    FROM sales s
    JOIN stores st ON s.store_id = st.store_id
    WHERE s.sale_date < '2024-01-01'
    GROUP BY st.country, EXTRACT(MONTH FROM s.sale_date)
),
RankedMonths AS (
    SELECT
        country, month, total_units,
        RANK() OVER (PARTITION BY country ORDER BY total_units DESC) AS rank,
        SUM(total_units) OVER (PARTITION BY country) AS country_total
    FROM MonthlySalesCountry
)
SELECT
    country,
    month,
    total_units,
    ROUND(total_units * 100.0 / country_total, 1) AS pct_of_country_total,
    rank
FROM RankedMonths
WHERE rank <= 3
ORDER BY country, rank;

-- Analysis 3a : Stores with declining sales for 2 consecutive years (excludes 2024)
WITH StoreYearlySales AS (
    SELECT 
        st.store_id,
        st.store_name,
        st.city,
        st.country,
        EXTRACT(YEAR FROM s.sale_date) AS sales_year,
        SUM(s.quantity) AS total_units
    FROM sales s
    JOIN stores st ON s.store_id = st.store_id
    WHERE EXTRACT(YEAR FROM s.sale_date) < 2024
    GROUP BY st.store_id, st.store_name, st.city, st.country, EXTRACT(YEAR FROM s.sale_date)
),
SalesComparison AS (
    SELECT 
        store_id,          
        store_name,
        city,
        country,
        sales_year,
        total_units,
        LAG(total_units, 1) OVER(PARTITION BY store_id ORDER BY sales_year) AS prev_year_1,  
        LAG(total_units, 2) OVER(PARTITION BY store_id ORDER BY sales_year) AS prev_year_2   
    FROM StoreYearlySales
)
SELECT 
        store_id,
        store_name,
        city,
        country,
        sales_year,
        prev_year_2 AS units_two_years_ago,
        prev_year_1 AS units_last_year,
        total_units AS units_this_year
FROM SalesComparison
WHERE prev_year_2 IS NOT NULL 
  AND prev_year_1 < prev_year_2 
  AND total_units < prev_year_1
ORDER BY country, city;

-- Analysis 3b (Validation Check): What % of total stores fall into the declining pattern above?
WITH StoreYearlySales AS (
    SELECT 
        st.store_id, st.store_name, st.city, st.country,
        EXTRACT(YEAR FROM s.sale_date) AS sales_year,
        SUM(s.quantity) AS total_units
    FROM sales s
    JOIN stores st ON s.store_id = st.store_id
    WHERE EXTRACT(YEAR FROM s.sale_date) < 2024
    GROUP BY st.store_id, st.store_name, st.city, st.country, EXTRACT(YEAR FROM s.sale_date)
),
SalesComparison AS (
    SELECT 
        store_id, store_name, city, country, sales_year, total_units,
        LAG(total_units, 1) OVER(PARTITION BY store_id ORDER BY sales_year) AS prev_year_1,
        LAG(total_units, 2) OVER(PARTITION BY store_id ORDER BY sales_year) AS prev_year_2
    FROM StoreYearlySales
),
DecliningStores AS (
    SELECT DISTINCT store_id, store_name, city, country
    FROM SalesComparison
    WHERE prev_year_2 IS NOT NULL 
      AND prev_year_1 < prev_year_2 
      AND total_units < prev_year_1
)
SELECT 
    COUNT(*) AS unique_declining_stores,
    (SELECT COUNT(DISTINCT store_id) FROM stores) AS total_stores,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(DISTINCT store_id) FROM stores), 1) AS pct_of_total_stores
FROM DecliningStores;

-- Analysis 4 : Geographic Price Preference (Percentage of Premium Product Sales)
WITH GlobalAverage AS(
    SELECT AVG(price) AS avg_price
    FROM products
),
PremiumSales AS (
    SELECT
        st.country,
        s.sale_id,
        CASE WHEN p.price > (SELECT avg_price FROM GlobalAverage) THEN 1 ELSE 0 END AS is_premium
    FROM sales s
    JOIN products p ON s.product_id = p.product_id
    JOIN stores st ON s.store_id = st.store_id
)
SELECT
    country,
    COUNT(sale_id) AS total_transactions,
    SUM(is_premium) AS premium_transactions,
    ROUND((SUM(is_premium)*100.0)/COUNT(sale_id),2) AS premium_percentage
FROM PremiumSales
GROUP BY country
ORDER BY premium_percentage DESC;