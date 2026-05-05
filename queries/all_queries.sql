-- ================================================
-- Project: E-Commerce Sales Analysis
-- Dataset: Brazilian E-Commerce - Olist (Kaggle)
-- Author: Umang
-- Tool: MySQL + DBeaver
-- Date: April 2026
-- ================================================

-- I started by exploring the payments table to understand
-- the overall scale of the business


-- Q1: what is the total revenue generated on this platform?
SELECT 
    ROUND(SUM(payment_value), 2) AS total_revenue
FROM payments;
-- Result: ~16 million BRL -- much bigger than I expected


-- Q2: how happy are customers overall?
-- checking average review score across all orders
SELECT 
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM reviews;
-- 4.09 out of 5 -- pretty decent customer satisfaction


-- Q3: which products sell the most?
-- wanted to find the top 10 products by number of orders
SELECT 
    product_id,
    COUNT(*) AS total_sales
FROM order_items
GROUP BY product_id
ORDER BY total_sales DESC
LIMIT 10;
-- top product sold 527 times, interesting how big the gap is


-- Q4: which states have the most customers?
-- brazil is huge so I expected SP to dominate
SELECT 
    customer_state,
    COUNT(*) AS total_customers
FROM customers
GROUP BY customer_state
ORDER BY total_customers DESC
LIMIT 10;
-- SP has 41k customers, RJ is second with only 12k
-- massive gap between 1st and 2nd place


-- ----------------------------------------
-- joining tables to get deeper insights
-- ----------------------------------------

-- Q5: revenue by state -- needed to join 3 tables for this
-- customers -> orders -> payments
SELECT 
    c.customer_state,
    ROUND(SUM(p.payment_value), 2) AS total_revenue
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN payments p ON o.order_id = p.order_id
GROUP BY c.customer_state
ORDER BY total_revenue DESC
LIMIT 10;
-- SP alone brings in 6 million BRL which is ~37% of total revenue
-- this makes sense given it has the most customers too


-- Q6: which state gives the best ratings?
-- joined customers, orders and reviews
SELECT 
    c.customer_state,
    ROUND(AVG(r.review_score), 2) AS avg_review_score
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN reviews r ON o.order_id = r.order_id
GROUP BY c.customer_state
ORDER BY avg_review_score DESC
LIMIT 10;
-- AM (Amazonas) has the highest ratings at 4.29
-- interesting because AM also has longer delivery times


-- Q7: how did revenue grow month by month?
-- used YEAR() and MONTH() to break down the timestamp
SELECT 
    YEAR(o.order_purchase_timestamp) AS year,
    MONTH(o.order_purchase_timestamp) AS month,
    ROUND(SUM(p.payment_value), 2) AS monthly_revenue
FROM orders o
JOIN payments p ON o.order_id = p.order_id
GROUP BY year, month
ORDER BY year, month;
-- platform started slow in late 2016
-- revenue exploded through 2017 -- clear growth trend


-- ----------------------------------------
-- advanced queries using CTEs and window functions
-- learned these recently and wanted to practice
-- ----------------------------------------

-- Q8: cumulative revenue over time
-- used a CTE to first get monthly revenue
-- then used SUM() OVER to get running total
WITH monthly AS (
    SELECT 
        YEAR(o.order_purchase_timestamp) AS year,
        MONTH(o.order_purchase_timestamp) AS month,
        ROUND(SUM(p.payment_value), 2) AS revenue
    FROM orders o
    JOIN payments p ON o.order_id = p.order_id
    GROUP BY year, month
)
SELECT 
    year,
    month,
    revenue,
    ROUND(SUM(revenue) OVER (ORDER BY year, month), 2) AS cumulative_revenue
FROM monthly
ORDER BY year, month;
-- by mid 2017 the platform had already crossed 3 million BRL total
-- shows how fast things picked up after the first few months


-- Q9: which states have the worst delivery performance?
-- used DATEDIFF to calculate delivery time
-- CASE WHEN to flag orders that arrived after estimated date
WITH delivery AS (
    SELECT 
        c.customer_state,
        DATEDIFF(
            o.order_delivered_customer_date,
            o.order_purchase_timestamp
        ) AS delivery_days,
        CASE 
            WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date 
            THEN 1 
            ELSE 0 
        END AS is_late
    FROM orders o
    JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_delivered_customer_date IS NOT NULL
)
SELECT 
    customer_state,
    ROUND(AVG(delivery_days), 1) AS avg_delivery_days,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_rate_pct
FROM delivery
GROUP BY customer_state
ORDER BY late_rate_pct DESC
LIMIT 10;
-- AL has the worst late delivery rate at 23.93%
-- nearly 1 in 4 orders arrives late in northern states
-- probably because of long distances and poor logistics


-- Q10: ranking sellers by total revenue
-- used RANK() window function with a subquery
-- wanted to see who the top performers are
SELECT 
    seller_id,
    total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
FROM (
    SELECT 
        seller_id,
        ROUND(SUM(price), 2) AS total_revenue
    FROM order_items
    GROUP BY seller_id
) AS seller_totals
LIMIT 10;
-- top seller made 229k BRL
-- gap between rank 1 and rank 2 is almost 7000 BRL
-- shows how dominant the top seller is on this platform