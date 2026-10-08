# E-Commerce Sales Analysis — SQL Project

SQL analysis of ~100K orders from the Brazilian Olist marketplace (2016–2018) covering revenue trends, regional performance, delivery problems, and customer satisfaction. Built with MySQL 8 and DBeaver across 6 relational tables.

> **Assumptions:** all money is in **Brazilian reais (BRL)**. "Revenue" counts only **delivered** orders. "Customers" means distinct `customer_unique_id` (Olist's `customer_id` is generated per order). The first and last months of the dataset are almost empty, so trends focus on Jan 2017 – Aug 2018.

---

## Key Metrics

| Metric | Value |
| --- | --- |
| Delivered orders | 96,478 |
| Revenue (payments, delivered orders) | R$ 15.42M |
| Product sales / freight (delivered) | R$ 13.22M / R$ 2.20M |
| Unique customers | 96,096 |
| Repeat-customer rate | ~3.0% |
| Average review score | 4.09 / 5 |
| Late deliveries (national) | 8.11% |
| Average delivery time | 12.6 days |
| Top state by customers and revenue | São Paulo — 40,302 customers, R$ 5.77M (37%) |

---

## Key Findings and Recommendations

1. **Late delivery is the biggest driver of bad reviews.** On-time orders average **4.29** stars; late orders average **2.57**. *Recommendation: prioritise delivery reliability over any other satisfaction lever.*
2. **The North-East has a logistics problem.** Alagoas has a **23.93%** late rate (24.5 days average, 397 orders), followed by Maranhão (19.67%) and Piauí (15.97%), versus 8.11% nationally. These states also have the lowest ratings (AL and MA ~3.84). *Recommendation: add regional fulfilment partners or set more realistic delivery estimates there.*
3. **Revenue is geographically concentrated.** São Paulo brings 37% of revenue; SP, RJ and MG together bring over 60%.
4. **Growth peaked at Black Friday 2017 and then plateaued.** November 2017 reached ~R$ 1.15M (delivered), and 2018 settled at a higher base of about R$ 1.0–1.1M per month rather than continuing to climb.
5. **Customer retention is weak.** Only ~3% of customers ordered more than once. *Recommendation: post-purchase campaigns and loyalty offers are an obvious growth lever.*
6. **The seller base is fragmented, not dominated.** The #1 seller made ~R$ 227K, only ~1.7% of sales out of ~3,000 sellers; the top 10 hold about 13%.
7. **Top categories by sales:** beleza_saude (health & beauty), relogios_presentes (watches & gifts), cama_mesa_banho (bed, bath & table).

---

## Queries Covered

| # | Business question | SQL concepts |
| --- | --- | --- |
| DQ1–5 | Data-quality checks (row counts, order status, duplicates) | `UNION ALL`, `COUNT(DISTINCT)` |
| 01 | Total revenue (delivered) and product/freight split | `SUM()`, `JOIN`, `WHERE` |
| 02 | Average review score | `AVG()` |
| 03 | Best-selling products | `GROUP BY`, `ORDER BY` |
| 04 | Real customers by state | `COUNT(DISTINCT)` |
| 05 | Revenue by state with % share | 3-table `JOIN`, `SUM() OVER ()` |
| 06 | Satisfaction by state (min. 100 orders) | `JOIN`, `AVG()`, `HAVING` |
| 07 | Monthly revenue trend | `YEAR()`, `MONTH()` |
| 08 | Cumulative revenue and month-over-month growth | CTE, `SUM() OVER`, `LAG()` |
| 09 | Late deliveries by state | CTE, `CASE WHEN`, `DATEDIFF()` |
| 10 | Seller ranking and revenue share | CTE, `RANK() OVER` |
| 11 | Impact of late delivery on reviews | `CASE WHEN`, `GROUP BY` |
| 12 | Top product categories | multi-table `JOIN` |
| 13 | Repeat-customer rate | CTE, conditional aggregation |

---

## Data Quality Notes

- `customer_id` is unique per order; real customers are identified by `customer_unique_id` (99,441 ids vs 96,096 people).
- 3% of orders are cancelled, unavailable or still in progress and are excluded from revenue.
- 99,224 review rows cover only 98,673 distinct orders (551 extra rows), so some orders have more than one review and review joins can be slightly inflated.
- 610 products have no category name and are excluded from the category analysis.
- Category names are in Portuguese (the Kaggle translation table is not loaded).

---

## Sample Query — Late Deliveries by State

```sql
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
    COUNT(*)                                  AS delivered_orders,
    ROUND(AVG(delivery_days), 1)              AS avg_delivery_days,
    ROUND(100.0 * SUM(is_late) / COUNT(*), 2) AS late_rate_pct
FROM delivery
GROUP BY customer_state
HAVING COUNT(*) >= 100
ORDER BY late_rate_pct DESC
LIMIT 10;
```

---

## Sample Outputs

![Revenue](screenshots/01_total_revenue.png)
![Monthly Revenue Trend](screenshots/07_monthly_revenue.png)
![Late Deliveries by State](screenshots/09_late_deliveries_by_state.png)
![Seller Rankings](screenshots/10_seller_rankings.png)

---

## Project Structure

```
ecommerce-sql-analysis/
├── queries/
│   └── all_queries.sql     # Data-quality checks + 13 analysis queries
├── schema/                 # Table definitions
├── screenshots/            # Query outputs and ERD
├── datasets/               # Raw CSVs (not committed; see Kaggle link)
└── README.md
```

---

## How to Run

1. Download the [Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) from Kaggle.
2. Create the database: `CREATE DATABASE ecommerce_analysis;`
3. Import the CSVs as tables named `customers`, `orders`, `order_items`, `payments`, `reviews`, `products` (DBeaver import wizard or `LOAD DATA INFILE`).
4. Run section 0 of `queries/all_queries.sql` and confirm the row counts match before running the analysis.

---

## Tools

| Tool | Purpose |
| --- | --- |
| MySQL 8 | Database engine |
| DBeaver | SQL editor and ERD |
| Kaggle | Dataset source |

*Dataset: Brazilian E-Commerce Public Dataset by Olist — Kaggle*
