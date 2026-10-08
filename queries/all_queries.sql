-- ================================================================
-- Project : E-Commerce Sales Analysis (Olist, Brazil)
-- Dataset : Brazilian E-Commerce Public Dataset by Olist (Kaggle)
-- Author  : Umang
-- Engine  : MySQL 8+ (tested in DBeaver)
-- ================================================================
-- ASSUMPTIONS
--   * All money values are in Brazilian reais (BRL), not USD.
--   * "Revenue" = payments from DELIVERED orders only (cancelled /
--     unavailable / unfinished orders are excluded).
--   * "Customers" = DISTINCT customer_unique_id. In Olist, customer_id
--     is generated per order, so COUNT(customer_id) counts orders.
--   * Dataset covers Sep 2016 - Oct 2018; the first and last months
--     are nearly empty and are excluded from trend interpretation.
-- ================================================================


-- ================================================================
-- SECTION 0: DATA QUALITY CHECKS
-- ================================================================

-- DQ1: row counts per table (compare with the Kaggle CSVs)
-- Expected: customers 99,441 | orders 99,441 | order_items 112,650
--           payments 103,886 | reviews 99,224 | products 32,951
SELECT 'customers'   AS tbl, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'orders',      COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'payments',    COUNT(*) FROM payments
UNION ALL SELECT 'reviews',     COUNT(*) FROM reviews
UNION ALL SELECT 'products',    COUNT(*) FROM products;

-- DQ2: order status mix (why we filter to 'delivered')
SELECT order_status, COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;
-- delivered = 96,478 of 99,441; ~3% are canceled / unavailable / in progress

-- DQ3: customer_id is per-order, customer_unique_id is the real customer
SELECT
    COUNT(DISTINCT customer_id)        AS customer_ids,      -- 99,441
    COUNT(DISTINCT customer_unique_id) AS real_customers     -- 96,096
FROM customers;

-- DQ4: some orders have more than one review (join can slightly inflate counts)
SELECT COUNT(*) AS review_rows, COUNT(DISTINCT order_id) AS orders_reviewed
FROM reviews;
-- 99,224 rows vs 98,673 distinct orders

-- DQ5: products with no category
SELECT COUNT(*) AS products_without_category
FROM products
WHERE product_category_name IS NULL OR product_category_name = '';
-- 610


-- ================================================================
-- SECTION 1: BASIC KPIs
-- ================================================================

-- Q1: Total revenue (delivered orders), plus the item vs freight split
SELECT
    ROUND(SUM(p.payment_value), 2) AS payment_value_delivered_brl
FROM orders o
JOIN payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered';
-- ~15.42M BRL (the all-status total of ~16.0M includes cancelled orders)

SELECT
    ROUND(SUM(i.price), 2)         AS product_sales_brl,
    ROUND(SUM(i.freight_value), 2) AS freight_brl
FROM orders o
JOIN order_items i ON o.order_id = i.order_id
WHERE o.order_status = 'delivered';
-- ~13.22M product sales + ~2.20M freight


-- Q2: Average review score
SELECT ROUND(AVG(review_score), 2) AS avg_review_score,
       COUNT(*)                    AS reviews
FROM reviews;
-- 4.09 across 99,224 reviews


-- Q3: Top 10 products by units sold (delivered orders)
SELECT
    i.product_id,
    COUNT(*)                AS units_sold,
    ROUND(SUM(i.price), 2)  AS product_sales_brl
FROM order_items i
JOIN orders o ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY i.product_id
ORDER BY units_sold DESC
LIMIT 10;


-- Q4: Real customers by state (DISTINCT customer_unique_id)
SELECT
    customer_state,
    COUNT(DISTINCT customer_unique_id) AS customers
FROM customers
GROUP BY customer_state
ORDER BY customers DESC
LIMIT 10;
-- SP 40,302 | RJ 12,384 | MG 11,259
-- (COUNT(*) gives 41,746 for SP, which is orders, not customers)


-- ================================================================
-- SECTION 2: JOINS
-- ================================================================

-- Q5: Revenue by state (customers -> orders -> payments, delivered only)
SELECT
    c.customer_state,
    ROUND(SUM(p.payment_value), 2) AS revenue_brl,
    ROUND(100 * SUM(p.payment_value) / SUM(SUM(p.payment_value)) OVER (), 1) AS pct_of_total
FROM customers c
JOIN orders   o ON c.customer_id = o.customer_id
JOIN payments p ON o.order_id    = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue_brl DESC
LIMIT 10;
-- SP ~5.77M BRL = ~37% of delivered revenue


-- Q6: Customer satisfaction by state (minimum 100 orders to avoid small-sample noise)
SELECT
    c.customer_state,
    ROUND(AVG(r.review_score), 2)  AS avg_review_score,
    COUNT(DISTINCT o.order_id)     AS orders_reviewed
FROM customers c
JOIN orders  o ON c.customer_id = o.customer_id
JOIN reviews r ON o.order_id    = r.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
HAVING COUNT(DISTINCT o.order_id) >= 100
ORDER BY avg_review_score DESC;
-- Lowest: AL and MA (~3.84), the same states with the worst late-delivery rates


-- Q7: Monthly revenue (delivered orders)
SELECT
    YEAR(o.order_purchase_timestamp)  AS yr,
    MONTH(o.order_purchase_timestamp) AS mth,
    COUNT(DISTINCT o.order_id)        AS orders,
    ROUND(SUM(p.payment_value), 2)    AS monthly_revenue_brl
FROM orders o
JOIN payments p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY yr, mth
ORDER BY yr, mth;
-- Peak is Nov 2017 (Black Friday, ~1.15M BRL), then a higher plateau (~1.0-1.1M) through 2018


-- ================================================================
-- SECTION 3: CTEs AND WINDOW FUNCTIONS
-- ================================================================

-- Q8: Cumulative revenue (running total)
WITH monthly AS (
    SELECT
        YEAR(o.order_purchase_timestamp)  AS yr,
        MONTH(o.order_purchase_timestamp) AS mth,
        SUM(p.payment_value)              AS revenue
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY yr, mth
)
SELECT
    yr,
    mth,
    ROUND(revenue, 2) AS revenue_brl,
    ROUND(SUM(revenue) OVER (ORDER BY yr, mth), 2) AS cumulative_revenue_brl,
    ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY yr, mth))
          / LAG(revenue) OVER (ORDER BY yr, mth), 1) AS mom_growth_pct
FROM monthly
ORDER BY yr, mth;
-- Cumulative total ends at ~15.42M BRL in Aug 2018


-- Q9: Delivery performance by state (delivered orders with a delivery date)
WITH delivery AS (
    SELECT
        c.customer_state,
        DATEDIFF(o.order_delivered_customer_date, o.order_purchase_timestamp) AS delivery_days,
        CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
             THEN 1 ELSE 0 END AS is_late
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
      AND o.order_delivered_customer_date IS NOT NULL
)
SELECT
    customer_state,
    COUNT(*)                                   AS delivered_orders,
    ROUND(AVG(delivery_days), 1)               AS avg_delivery_days,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 2)  AS late_rate_pct
FROM delivery
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC
LIMIT 10;
-- AL 23.93% late (397 orders, 24.5 days) | MA 19.67% | PI 15.97%
-- National late rate is 8.11%, average delivery time 12.6 days


-- Q10: Seller ranking by product sales (delivered orders) with revenue share
WITH seller_totals AS (
    SELECT
        i.seller_id,
        SUM(i.price)               AS sales,
        COUNT(DISTINCT i.order_id) AS orders
    FROM order_items i
    JOIN orders o ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY i.seller_id
)
SELECT
    seller_id,
    ROUND(sales, 2) AS sales_brl,
    orders,
    RANK() OVER (ORDER BY sales DESC) AS sales_rank,
    ROUND(100 * sales / SUM(sales) OVER (), 2) AS pct_of_total_sales
FROM seller_totals
ORDER BY sales_rank
LIMIT 10;
-- Top seller ~227K BRL = only ~1.7% of sales, out of ~3,000 sellers.
-- The market is fragmented, not dominated by a few sellers.


-- ================================================================
-- SECTION 4: ADDITIONAL BUSINESS QUESTIONS
-- ================================================================

-- Q11: Does late delivery hurt reviews?
SELECT
    CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date
         THEN 'late' ELSE 'on_time' END AS delivery_status,
    COUNT(*)                            AS reviews,
    ROUND(AVG(r.review_score), 2)       AS avg_review_score
FROM orders o
JOIN reviews r ON o.order_id = r.order_id
WHERE o.order_status = 'delivered'
  AND o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;
-- on_time 4.29 vs late 2.57: delivery delays are the biggest driver of bad reviews


-- Q12: Top 10 product categories by sales (delivered orders)
SELECT
    p.product_category_name AS category,
    COUNT(*)                AS units_sold,
    ROUND(SUM(i.price), 2)  AS product_sales_brl
FROM order_items i
JOIN products p ON i.product_id = p.product_id
JOIN orders   o ON i.order_id   = o.order_id
WHERE o.order_status = 'delivered'
  AND p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY product_sales_brl DESC
LIMIT 10;
-- beleza_saude, relogios_presentes, cama_mesa_banho lead (names are in Portuguese)


-- Q13: Repeat-customer rate (delivered orders)
WITH cust AS (
    SELECT c.customer_unique_id, COUNT(DISTINCT o.order_id) AS orders
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_unique_id
)
SELECT
    COUNT(*)                                        AS customers,
    SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END)     AS repeat_customers,
    ROUND(100.0 * SUM(CASE WHEN orders > 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS repeat_rate_pct
FROM cust;
-- ~3.0%: the platform is overwhelmingly one-time buyers
