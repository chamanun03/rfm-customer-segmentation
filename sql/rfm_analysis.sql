-- RFM Customer Segmentation
-- Dataset: UCI Online Retail II
-- ใช้ MySQL Workbench


--   1 สร้าง Database + Import 

CREATE DATABASE IF NOT EXISTS rfm_project;
USE rfm_project;

DROP TABLE IF EXISTS online_retail;

CREATE TABLE online_retail (
    Invoice       VARCHAR(20),
    StockCode     VARCHAR(20),
    Description   VARCHAR(255),
    Quantity      INT,
    InvoiceDate   DATETIME,
    Price         DECIMAL(10,2),
    CustomerID    INT,
    Country       VARCHAR(50)
);

-- import csv 
LOAD DATA LOCAL INFILE 'C:/Users/kowpod/Downloads/projects/ucl online retail/online_retail_II.csv'
INTO TABLE online_retail
FIELDS TERMINATED BY ','
OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(Invoice, StockCode, Description, Quantity, InvoiceDate, Price, @cid, Country)
SET CustomerID = NULLIF(@cid, '');



--   2 สำรวจข้อมูล

-- ดูภาพรวมคร่าวๆ
SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT Invoice) AS unique_invoices,
    COUNT(DISTINCT StockCode) AS unique_products,
    COUNT(DISTINCT CustomerID) AS unique_customers,
    COUNT(DISTINCT Country) AS unique_countries
FROM online_retail;

-- ดูช่วงวันที่
SELECT MIN(InvoiceDate) AS earliest, MAX(InvoiceDate) AS latest
FROM online_retail;


-- หา null
SELECT
    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_customer,
    ROUND(SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS pct_null
FROM online_retail;
-- CustomerID หายไป 243,007 rows 22.8% 

-- cancelled orders = invoice ที่ขึ้นต้นด้วย C
SELECT COUNT(*) AS cancelled_rows FROM online_retail WHERE Invoice LIKE 'C%';
-- 19,494 rows

-- ดูตัวอย่าง cancelled order
SELECT * FROM online_retail WHERE Invoice LIKE 'C%' LIMIT 5;
-- Quantity เป็นติดลบ เพราะเป็นการคืนสินค้า

-- เช็ค quantity ผิดปกติ
SELECT
    SUM(CASE WHEN Quantity < 0 THEN 1 ELSE 0 END) AS negative_qty,
    SUM(CASE WHEN Quantity = 0 THEN 1 ELSE 0 END) AS zero_qty
FROM online_retail;

-- เช็ค price
SELECT
    SUM(CASE WHEN Price = 0 THEN 1 ELSE 0 END) AS zero_price,
    SUM(CASE WHEN Price < 0 THEN 1 ELSE 0 END) AS negative_price
FROM online_retail;
-- price=0 มี 6,202 rows 

-- stockcode ที่ไม่ใช่สินค้าจริง
SELECT StockCode, Description, COUNT(*) AS cnt
FROM online_retail
WHERE StockCode IN ('POST','DOT','M','BANK CHARGES','D','S','AMAZONFEE','B','C2','CRUK','PADS')
   OR StockCode LIKE 'ADJUST%'
GROUP BY StockCode, Description
ORDER BY cnt DESC;



-- 3 Data Cleaning 

-- สรุปปัญหาที่เจอ:
-- 1. CustomerID เป็น NULL  ลบ
-- 2. Invoice ขึ้นต้น C = cancelled  ลบ
-- 3. Quantity <= 0  ลบ
-- 4. Price <= 0  ลบ
-- 5. StockCode ที่ไม่ใช่สินค้า  ลบ

DROP TABLE IF EXISTS retail_clean;

CREATE TABLE retail_clean AS
SELECT
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CAST(CustomerID AS UNSIGNED) AS CustomerID,
    Country,
    ROUND(Quantity * Price, 2) AS TotalAmount
FROM online_retail
WHERE
    CustomerID IS NOT NULL
    AND Invoice NOT LIKE 'C%'
    AND Quantity > 0
    AND Price > 0
    AND StockCode NOT IN ('POST','DOT','M','BANK CHARGES','D','S',
                          'AMAZONFEE','B','C2','CRUK','PADS')
    AND StockCode NOT LIKE 'ADJUST%';

-- เทียบก่อน-หลัง
SELECT 'before_cleaning' AS stage, COUNT(*) AS total FROM online_retail
UNION ALL
SELECT 'after_cleaning' AS stage, COUNT(*) AS total FROM retail_clean;
-- 1,067,371 -> 802,644 ลบไปประมาณ 25%


--  4 คำนวณ RFM 

-- หาวันสุดท้ายในข้อมูล ใช้เป็นจุดอ้างอิง
SELECT MAX(InvoiceDate) FROM retail_clean;
-- 2011-12-09 -> ใช้ 2011-12-10 เป็น rencency

DROP TABLE IF EXISTS rfm_raw;

CREATE TABLE rfm_raw AS
SELECT
    CustomerID,
    DATEDIFF('2011-12-10', MAX(InvoiceDate)) AS Recency,      -- ห่างหายกี่วัน
    COUNT(DISTINCT Invoice) AS Frequency,                       -- ซื้อกี่ครั้ง
    ROUND(SUM(TotalAmount), 2) AS Monetary                     -- ใช้จ่ายรวมเท่าไหร่
FROM retail_clean
GROUP BY CustomerID;

SELECT * FROM rfm_raw ORDER BY Monetary DESC LIMIT 10;


--  5 ให้คะแนน RFM 1-5 

-- ใช้ NTILE(5) แบ่งเป็น 5 กลุ่มเท่าๆ กัน
-- Recency เรียง DESC เยิ่งน้อยยิ่งดี 
-- Frequency, Monetary เรียง ASC ยิ่งมากยิ่งดี

DROP TABLE IF EXISTS rfm_scores;

CREATE TABLE rfm_scores AS
SELECT
    CustomerID, Recency, Frequency, Monetary,
    NTILE(5) OVER (ORDER BY Recency DESC) AS R_Score,
    NTILE(5) OVER (ORDER BY Frequency ASC) AS F_Score,
    NTILE(5) OVER (ORDER BY Monetary ASC) AS M_Score
FROM rfm_raw;

SELECT *, CONCAT(R_Score, F_Score, M_Score) AS RFM_Combined
FROM rfm_scores ORDER BY Monetary DESC LIMIT 10;
-- ลูกค้าที่ใช้จ่ายเยอะ+ซื้อบ่อย+เพิ่งซื้อ ได้ 555 = ถูก


-- 6 แบ่งกลุ่มลูกค้า

DROP TABLE IF EXISTS customer_segments;

CREATE TABLE customer_segments AS
SELECT
    *,
    CONCAT(R_Score, F_Score, M_Score) AS RFM_Combined,
    CASE
        WHEN R_Score >= 4 AND F_Score >= 4 AND M_Score >= 4 THEN 'Champions'
        WHEN F_Score >= 4 AND M_Score >= 3                  THEN 'Loyal Customers'
        WHEN R_Score >= 4 AND F_Score BETWEEN 2 AND 4       THEN 'Potential Loyalists'
        WHEN R_Score >= 4 AND F_Score <= 2                  THEN 'New Customers'
        WHEN R_Score BETWEEN 2 AND 3 AND F_Score >= 3       THEN 'At Risk'
        WHEN R_Score = 3 AND F_Score BETWEEN 2 AND 3        THEN 'Need Attention'
        WHEN R_Score <= 2 AND F_Score <= 2                  THEN 'Hibernating'
        WHEN R_Score <= 1 AND F_Score <= 1                  THEN 'Lost'
        ELSE 'Others'
    END AS Segment
FROM rfm_scores;


-- 7  ดูผลลัพธ์ 

SELECT
    Segment,
    COUNT(*) AS customers,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_segments), 1) AS pct,
    ROUND(AVG(Recency), 0) AS avg_recency,
    ROUND(AVG(Frequency), 1) AS avg_orders,
    ROUND(AVG(Monetary), 0) AS avg_revenue,
    ROUND(SUM(Monetary), 0) AS total_revenue
FROM customer_segments
GROUP BY Segment
ORDER BY total_revenue DESC;

-- ดูว่าแต่ละ กลุ่ม สร้างรายได้กี่ เปอร์เซ็น
SELECT
    Segment,
    ROUND(SUM(Monetary) * 100.0 / (SELECT SUM(Monetary) FROM customer_segments), 1) AS revenue_pct
FROM customer_segments
GROUP BY Segment
ORDER BY revenue_pct DESC;
-- Champions มีแค่ 22.8% ของลูกค้า แต่สร้างรายได้ 68.8%
