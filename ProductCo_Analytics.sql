/* =====================================================================
   PRODUCTCO 360 ANALYTICS  -  SQL Server (2017+)
   Product-based company: Beverages, Snacks, Personal Care, Home Care
   Modules: Sales | Inventory | Production Quality | Suppliers | Returns
   Run the whole script in SSMS. Data is randomly generated (~20k orders,
   ~40k order lines, 1,500 production batches, 2,000 purchase orders).
   Currency: INR.  Data period: 2024-10-01 to 2026-09-30.

   Planted "stories" for you to discover with SQL:
     - Products 29 & 30 (Glass Cleaner, Scrub Pad): no sales since May-2026, huge stock  -> dead stock
     - Products 5 & 12 (Energy Drink, Namkeen Mix): high defect + return rate            -> quality problem
     - Suppliers 6-8: increasingly late deliveries                                        -> supplier risk
     - Sales skewed to low ProductIDs                                                     -> Pareto effect
   ===================================================================== */

/* ---------- 0. DATABASE ---------- */
USE master;
GO
IF DB_ID('ProductCoAnalytics') IS NOT NULL
BEGIN
    ALTER DATABASE ProductCoAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ProductCoAnalytics;
END
GO
CREATE DATABASE ProductCoAnalytics;
GO
USE ProductCoAnalytics;
GO

/* ---------- 1. SCHEMA ---------- */
CREATE TABLE Products (
    ProductID    INT IDENTITY(1,1) PRIMARY KEY,
    ProductName  VARCHAR(60)   NOT NULL,
    Category     VARCHAR(30)   NOT NULL,
    UnitCost     DECIMAL(10,2) NOT NULL,
    UnitPrice    DECIMAL(10,2) NOT NULL,
    ReorderLevel INT           NOT NULL
);

CREATE TABLE Customers (
    CustomerID   INT IDENTITY(1,1) PRIMARY KEY,
    CustomerName VARCHAR(60) NOT NULL,
    Region       VARCHAR(20) NOT NULL,
    Channel      VARCHAR(20) NOT NULL   -- Retail / Distributor / Online
);

CREATE TABLE Warehouses (
    WarehouseID   INT IDENTITY(1,1) PRIMARY KEY,
    WarehouseName VARCHAR(40) NOT NULL,
    City          VARCHAR(30) NOT NULL
);

CREATE TABLE Inventory (
    ProductID   INT NOT NULL REFERENCES Products(ProductID),
    WarehouseID INT NOT NULL REFERENCES Warehouses(WarehouseID),
    StockQty    INT NOT NULL,
    LastUpdated DATETIME NOT NULL DEFAULT GETDATE(),
    PRIMARY KEY (ProductID, WarehouseID)
);

CREATE TABLE SalesOrders (
    OrderID    INT IDENTITY(1,1) PRIMARY KEY,
    OrderDate  DATETIME NOT NULL,
    CustomerID INT NOT NULL REFERENCES Customers(CustomerID)
);

CREATE TABLE SalesOrderItems (
    OrderItemID INT IDENTITY(1,1) PRIMARY KEY,
    OrderID     INT NOT NULL REFERENCES SalesOrders(OrderID),
    ProductID   INT NOT NULL REFERENCES Products(ProductID),
    Qty         INT NOT NULL,
    UnitPrice   DECIMAL(10,2) NOT NULL,      -- price snapshot at time of sale
    Discount    DECIMAL(4,2)  NOT NULL DEFAULT 0
);

CREATE TABLE ProductionBatches (
    BatchID     INT IDENTITY(1,1) PRIMARY KEY,
    ProductID   INT NOT NULL REFERENCES Products(ProductID),
    BatchDate   DATE NOT NULL,
    PlannedQty  INT NOT NULL,
    ProducedQty INT NOT NULL,
    DefectQty   INT NOT NULL
);

CREATE TABLE Suppliers (
    SupplierID   INT IDENTITY(1,1) PRIMARY KEY,
    SupplierName VARCHAR(60) NOT NULL,
    City         VARCHAR(30) NOT NULL
);

CREATE TABLE PurchaseOrders (
    POID         INT IDENTITY(1,1) PRIMARY KEY,
    SupplierID   INT NOT NULL REFERENCES Suppliers(SupplierID),
    PODate       DATE NOT NULL,
    PromisedDate DATE NOT NULL,
    ReceivedDate DATE NOT NULL,
    Qty          INT NOT NULL,
    UnitCost     DECIMAL(10,2) NOT NULL
);

CREATE TABLE Returns (
    ReturnID    INT IDENTITY(1,1) PRIMARY KEY,
    OrderItemID INT NOT NULL REFERENCES SalesOrderItems(OrderItemID),
    ProductID   INT NOT NULL REFERENCES Products(ProductID),
    ReturnQty   INT NOT NULL,
    Reason      VARCHAR(30) NOT NULL,
    ReturnDate  DATE NOT NULL
);

CREATE TABLE Alerts (
    AlertID     INT IDENTITY(1,1) PRIMARY KEY,
    ProductID   INT NOT NULL,
    AlertType   VARCHAR(30) NOT NULL,
    Message     VARCHAR(200) NOT NULL,
    CreatedAt   DATETIME NOT NULL DEFAULT GETDATE(),
    IsResolved  BIT NOT NULL DEFAULT 0
);
GO

/* ---------- 2. MASTER DATA ---------- */
INSERT INTO Products (ProductName, Category, UnitCost, UnitPrice, ReorderLevel) VALUES
-- Beverages (1-7)
('Mango Juice 1L','Beverages',45,70,400),('Orange Juice 1L','Beverages',42,65,400),
('Cola 500ml','Beverages',12,20,1500),('Lemon Soda 300ml','Beverages',8,15,1500),
('Energy Drink 250ml','Beverages',30,60,600),('Green Tea 25 bags','Beverages',60,110,300),
('Coconut Water 200ml','Beverages',20,40,500),
-- Snacks (8-15)
('Potato Chips 50g','Snacks',8,20,2000),('Masala Peanuts 100g','Snacks',14,30,1200),
('Cream Biscuits 100g','Snacks',9,20,2000),('Choco Cookies 150g','Snacks',25,50,800),
('Namkeen Mix 200g','Snacks',30,55,900),('Granola Bar','Snacks',15,35,700),
('Caramel Popcorn 80g','Snacks',18,40,600),('Rice Crackers 90g','Snacks',16,35,500),
-- Personal Care (16-22)
('Herbal Shampoo 200ml','Personal Care',70,140,500),('Aloe Face Wash 100ml','Personal Care',55,120,500),
('Sandal Soap 100g','Personal Care',14,30,1800),('Toothpaste 150g','Personal Care',35,75,1200),
('Body Lotion 250ml','Personal Care',90,185,400),('Deodorant 150ml','Personal Care',80,175,400),
('Hand Wash 250ml','Personal Care',40,90,700),
-- Home Care (23-30)
('Dish Wash Liquid 500ml','Home Care',40,85,800),('Floor Cleaner 1L','Home Care',65,130,600),
('Detergent Powder 1kg','Home Care',70,120,1000),('Fabric Softener 500ml','Home Care',60,125,400),
('Toilet Cleaner 500ml','Home Care',45,95,600),('Air Freshener 250ml','Home Care',70,150,350),
('Glass Cleaner 500ml','Home Care',50,105,300),('Scrub Pad 3-pack','Home Care',18,40,500);

INSERT INTO Warehouses (WarehouseName, City) VALUES
('Hyderabad Central WH','Hyderabad'),('Mumbai West WH','Mumbai'),('Delhi North WH','Delhi');

INSERT INTO Suppliers (SupplierName, City) VALUES
('Apex Packaging','Pune'),('GreenLeaf Agro','Nashik'),('PureChem Industries','Vadodara'),
('Sunrise Plastics','Chennai'),('Metro Cartons','Hyderabad'),('Delta Ingredients','Ahmedabad'),
('Nova Fragrances','Bengaluru'),('Kisan Raw Foods','Indore');

-- 200 customers
INSERT INTO Customers (CustomerName, Region, Channel)
SELECT TOP (200)
       CONCAT('Customer ', n),
       CHOOSE(1 + n % 4, 'North','South','East','West'),
       CHOOSE(1 + n % 3, 'Retail','Distributor','Online')
FROM (SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
      FROM sys.all_columns a CROSS JOIN sys.all_columns b) t;
GO

/* ---------- 3. TRANSACTION DATA (generated) ---------- */
-- 3.1 Sales orders: 20,000 orders over 730 days
INSERT INTO SalesOrders (OrderDate, CustomerID)
SELECT TOP (20000)
       DATEADD(MINUTE, ABS(CHECKSUM(NEWID())) % 1440,
       DATEADD(DAY,    ABS(CHECKSUM(NEWID())) % 730, CAST('2024-10-01' AS DATETIME))),
       1 + ABS(CHECKSUM(NEWID())) % 200
FROM sys.all_columns a CROSS JOIN sys.all_columns b;
GO

-- 3.2 Order items: 1-3 lines per order, sales skewed toward lower ProductIDs (Pareto)
SELECT o.OrderID,
       1 + CAST(30 * POWER(RAND(CHECKSUM(NEWID())), 1.8) AS INT) AS ProductID,
       5 + ABS(CHECKSUM(NEWID())) % 46                           AS Qty,
       CAST((ABS(CHECKSUM(NEWID())) % 4) * 0.05 AS DECIMAL(4,2)) AS Discount
INTO #RawItems
FROM SalesOrders o
CROSS JOIN (VALUES (1),(2),(3)) v(n)
WHERE v.n <= 1 + (o.OrderID % 3);

INSERT INTO SalesOrderItems (OrderID, ProductID, Qty, UnitPrice, Discount)
SELECT r.OrderID, r.ProductID, r.Qty, p.UnitPrice, r.Discount
FROM #RawItems r JOIN Products p ON p.ProductID = r.ProductID;

DROP TABLE #RawItems;

-- Story: Glass Cleaner (29) and Scrub Pad (30) stopped selling after 1-May-2026 (dead stock)
DELETE i
FROM SalesOrderItems i JOIN SalesOrders o ON o.OrderID = i.OrderID
WHERE i.ProductID IN (29, 30) AND o.OrderDate >= '2026-05-01';
GO

-- 3.3 Inventory: 3 warehouses x 30 products
INSERT INTO Inventory (ProductID, WarehouseID, StockQty)
SELECT p.ProductID, w.WarehouseID,
       CASE WHEN p.ProductID IN (29, 30) THEN 4000 + ABS(CHECKSUM(NEWID())) % 1000   -- dead stock story
            ELSE ABS(CHECKSUM(NEWID())) % (p.ReorderLevel * 2) END
FROM Products p CROSS JOIN Warehouses w;
GO

-- 3.4 Production batches (1,500)
INSERT INTO ProductionBatches (ProductID, BatchDate, PlannedQty, ProducedQty, DefectQty)
SELECT TOP (1500)
       1 + ABS(CHECKSUM(NEWID())) % 30,
       DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 730, CAST('2024-10-01' AS DATE)),
       500 + ABS(CHECKSUM(NEWID())) % 4501, 0, 0
FROM sys.all_columns a CROSS JOIN sys.all_columns b;

UPDATE ProductionBatches
SET ProducedQty = CAST(PlannedQty * (90 + ABS(CHECKSUM(NEWID())) % 11) / 100.0 AS INT);

-- normal defect rate 0.5%-5%; products 5 and 12 get +4% (quality story)
UPDATE ProductionBatches
SET DefectQty = CAST(ProducedQty *
        (0.5 + (ABS(CHECKSUM(NEWID())) % 450) / 100.0 + CASE WHEN ProductID IN (5,12) THEN 4 ELSE 0 END)
        / 100.0 AS INT);
GO

-- 3.5 Purchase orders (2,000). Higher SupplierID = less reliable
SELECT TOP (2000)
       1 + ABS(CHECKSUM(NEWID())) % 8                                   AS SupplierID,
       DATEADD(DAY, ABS(CHECKSUM(NEWID())) % 730, CAST('2024-10-01' AS DATE)) AS PODate,
       7 + ABS(CHECKSUM(NEWID())) % 15                                  AS LeadDays,
       0                                                                AS DelayDays,
       1000 + ABS(CHECKSUM(NEWID())) % 9000                             AS Qty,
       5 + ABS(CHECKSUM(NEWID())) % 60                                  AS UnitCost
INTO #po
FROM sys.all_columns a CROSS JOIN sys.all_columns b;

UPDATE #po SET DelayDays = ABS(CHECKSUM(NEWID())) % (3 + 2 * SupplierID) - 2;

INSERT INTO PurchaseOrders (SupplierID, PODate, PromisedDate, ReceivedDate, Qty, UnitCost)
SELECT SupplierID, PODate,
       DATEADD(DAY, LeadDays, PODate),
       DATEADD(DAY, LeadDays + DelayDays, PODate),
       Qty, UnitCost
FROM #po;
DROP TABLE #po;
GO

-- 3.6 Returns: ~3% of lines (9% for products 5 and 12)
INSERT INTO Returns (OrderItemID, ProductID, ReturnQty, Reason, ReturnDate)
SELECT i.OrderItemID, i.ProductID, 1 + i.Qty / 5,
       CHOOSE(1 + ABS(CHECKSUM(NEWID())) % 4, 'Damaged','Expired','Quality Issue','Wrong Item'),
       DATEADD(DAY, 3 + ABS(CHECKSUM(NEWID())) % 20, CAST(o.OrderDate AS DATE))
FROM SalesOrderItems i
JOIN SalesOrders o ON o.OrderID = i.OrderID
WHERE o.OrderDate < '2026-09-10'
  AND ABS(CHECKSUM(NEWID())) % 100 < CASE WHEN i.ProductID IN (5,12) THEN 9 ELSE 3 END;
GO

/* ---------- 4. INDEXES ---------- */
CREATE INDEX IX_SalesOrders_Date     ON SalesOrders (OrderDate) INCLUDE (CustomerID);
CREATE INDEX IX_Items_Order          ON SalesOrderItems (OrderID) INCLUDE (ProductID, Qty, UnitPrice, Discount);
CREATE INDEX IX_Items_Product        ON SalesOrderItems (ProductID) INCLUDE (OrderID, Qty, UnitPrice, Discount);
CREATE INDEX IX_Batches_Product      ON ProductionBatches (ProductID, BatchDate);
CREATE INDEX IX_PO_Supplier          ON PurchaseOrders (SupplierID) INCLUDE (PromisedDate, ReceivedDate);
GO

/* ---------- 5. VIEWS (reporting layer for Power BI) ---------- */
CREATE VIEW vw_ProductProfitability AS
SELECT p.ProductID, p.ProductName, p.Category,
       ISNULL(SUM(i.Qty), 0) AS UnitsSold,
       ISNULL(SUM(i.Qty * i.UnitPrice * (1 - i.Discount)), 0) AS Revenue,
       ISNULL(SUM(i.Qty * (i.UnitPrice * (1 - i.Discount) - p.UnitCost)), 0) AS GrossProfit,
       100.0 * SUM(i.Qty * (i.UnitPrice * (1 - i.Discount) - p.UnitCost))
             / NULLIF(SUM(i.Qty * i.UnitPrice * (1 - i.Discount)), 0) AS MarginPct
FROM Products p
LEFT JOIN SalesOrderItems i ON i.ProductID = p.ProductID
GROUP BY p.ProductID, p.ProductName, p.Category;
GO

CREATE VIEW vw_InventoryHealth AS
WITH s AS (
    SELECT i.ProductID, SUM(i.Qty) / 30.0 AS AvgDailySales
    FROM SalesOrderItems i
    JOIN SalesOrders o ON o.OrderID = i.OrderID
    WHERE o.OrderDate >= DATEADD(DAY, -30, CAST(GETDATE() AS DATE))
    GROUP BY i.ProductID
),
st AS (
    SELECT ProductID, SUM(StockQty) AS TotalStock FROM Inventory GROUP BY ProductID
)
SELECT p.ProductID, p.ProductName, p.Category, p.ReorderLevel, p.UnitCost,
       st.TotalStock,
       CAST(ISNULL(s.AvgDailySales, 0) AS DECIMAL(10,2)) AS AvgDailySales,
       CAST(st.TotalStock / NULLIF(s.AvgDailySales, 0) AS DECIMAL(10,1)) AS DaysOfCover,
       st.TotalStock * p.UnitCost AS StockValue,
       CASE WHEN ISNULL(s.AvgDailySales, 0) = 0                  THEN 'DEAD / NO SALES'
            WHEN st.TotalStock / s.AvgDailySales < 7             THEN 'STOCKOUT RISK'
            WHEN st.TotalStock / s.AvgDailySales > 90            THEN 'OVERSTOCK'
            ELSE 'HEALTHY' END AS StockStatus
FROM Products p
JOIN st ON st.ProductID = p.ProductID
LEFT JOIN s ON s.ProductID = p.ProductID;
GO

CREATE VIEW vw_ProductionQuality AS
SELECT p.ProductName, p.Category,
       DATEFROMPARTS(YEAR(b.BatchDate), MONTH(b.BatchDate), 1) AS MonthStart,
       SUM(b.PlannedQty)  AS Planned,
       SUM(b.ProducedQty) AS Produced,
       SUM(b.DefectQty)   AS Defects,
       100.0 * SUM(b.ProducedQty) / SUM(b.PlannedQty) AS YieldPct,
       100.0 * SUM(b.DefectQty)   / SUM(b.ProducedQty) AS DefectPct
FROM ProductionBatches b JOIN Products p ON p.ProductID = b.ProductID
GROUP BY p.ProductName, p.Category, DATEFROMPARTS(YEAR(b.BatchDate), MONTH(b.BatchDate), 1);
GO

/* ---------- 6. STORED PROCEDURES ---------- */
CREATE PROCEDURE usp_DailySalesSummary @Date DATE
AS
BEGIN
    SET NOCOUNT ON;
    SELECT c.Channel, c.Region,
           COUNT(DISTINCT o.OrderID)                          AS Orders,
           SUM(i.Qty)                                         AS Units,
           SUM(i.Qty * i.UnitPrice * (1 - i.Discount))        AS Revenue
    FROM SalesOrders o
    JOIN SalesOrderItems i ON i.OrderID = o.OrderID
    JOIN Customers c       ON c.CustomerID = o.CustomerID
    WHERE CAST(o.OrderDate AS DATE) = @Date
    GROUP BY ROLLUP (c.Channel, c.Region);
END
GO

CREATE PROCEDURE usp_SupplierScorecard
AS
BEGIN
    SET NOCOUNT ON;
    WITH x AS (
        SELECT s.SupplierName,
               COUNT(*) AS TotalPOs,
               CAST(100.0 * SUM(CASE WHEN po.ReceivedDate <= po.PromisedDate THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS OnTimePct,
               CAST(AVG(CASE WHEN po.ReceivedDate > po.PromisedDate
                             THEN DATEDIFF(DAY, po.PromisedDate, po.ReceivedDate) END * 1.0) AS DECIMAL(5,1)) AS AvgDelayDays_WhenLate,
               MAX(DATEDIFF(DAY, po.PromisedDate, po.ReceivedDate)) AS WorstDelayDays,
               SUM(po.Qty * po.UnitCost) AS SpendINR
        FROM PurchaseOrders po JOIN Suppliers s ON s.SupplierID = po.SupplierID
        GROUP BY s.SupplierName
    )
    SELECT DENSE_RANK() OVER (ORDER BY OnTimePct DESC) AS Rnk, *
    FROM x ORDER BY Rnk;
END
GO

-- Simulates one live customer order. Schedule with SQL Server Agent every 1 minute.
CREATE PROCEDURE usp_SimulateLiveOrder
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @oid INT;
    INSERT INTO SalesOrders (OrderDate, CustomerID)
    VALUES (GETDATE(), 1 + ABS(CHECKSUM(NEWID())) % 200);
    SET @oid = SCOPE_IDENTITY();

    INSERT INTO SalesOrderItems (OrderID, ProductID, Qty, UnitPrice, Discount)
    SELECT TOP (1 + ABS(CHECKSUM(NEWID())) % 3)
           @oid, p.ProductID, 5 + ABS(CHECKSUM(NEWID())) % 46, p.UnitPrice, 0.05
    FROM Products p
    ORDER BY NEWID();
END
GO

/* ---------- 7. TRIGGER: live stock deduction + low-stock alert ---------- */
-- Created AFTER the bulk load so history is not re-deducted.
CREATE TRIGGER trg_Items_AfterInsert ON SalesOrderItems
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- deduct from main warehouse (Hyderabad), never below zero
    UPDATE inv
    SET StockQty = CASE WHEN inv.StockQty - s.Qty < 0 THEN 0 ELSE inv.StockQty - s.Qty END,
        LastUpdated = GETDATE()
    FROM Inventory inv
    JOIN (SELECT ProductID, SUM(Qty) AS Qty FROM inserted GROUP BY ProductID) s
      ON s.ProductID = inv.ProductID
    WHERE inv.WarehouseID = 1;

    -- raise an alert if below reorder level and no open alert exists
    INSERT INTO Alerts (ProductID, AlertType, Message)
    SELECT inv.ProductID, 'LOW_STOCK',
           CONCAT('Stock ', inv.StockQty, ' is below reorder level ', p.ReorderLevel)
    FROM Inventory inv
    JOIN Products p ON p.ProductID = inv.ProductID
    WHERE inv.WarehouseID = 1
      AND inv.StockQty < p.ReorderLevel
      AND inv.ProductID IN (SELECT ProductID FROM inserted)
      AND NOT EXISTS (SELECT 1 FROM Alerts a
                      WHERE a.ProductID = inv.ProductID AND a.AlertType = 'LOW_STOCK' AND a.IsResolved = 0);
END
GO

/* =====================================================================
   8. BUSINESS ANALYSIS QUERIES
   ===================================================================== */

-- Q1. Row counts sanity check
SELECT 'SalesOrders' AS TableName, COUNT(*) AS Rows FROM SalesOrders UNION ALL
SELECT 'SalesOrderItems', COUNT(*) FROM SalesOrderItems UNION ALL
SELECT 'ProductionBatches', COUNT(*) FROM ProductionBatches UNION ALL
SELECT 'PurchaseOrders', COUNT(*) FROM PurchaseOrders UNION ALL
SELECT 'Returns', COUNT(*) FROM Returns;

-- Q2. Monthly revenue with month-over-month and year-over-year growth
WITH m AS (
    SELECT DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1) AS MonthStart,
           SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS Revenue
    FROM SalesOrders o JOIN SalesOrderItems i ON i.OrderID = o.OrderID
    GROUP BY DATEFROMPARTS(YEAR(o.OrderDate), MONTH(o.OrderDate), 1)
)
SELECT MonthStart,
       CAST(Revenue AS DECIMAL(14,0)) AS Revenue,
       CAST(100.0 * (Revenue - LAG(Revenue)     OVER (ORDER BY MonthStart)) / NULLIF(LAG(Revenue)     OVER (ORDER BY MonthStart), 0) AS DECIMAL(6,1)) AS MoM_Pct,
       CAST(100.0 * (Revenue - LAG(Revenue, 12) OVER (ORDER BY MonthStart)) / NULLIF(LAG(Revenue, 12) OVER (ORDER BY MonthStart), 0) AS DECIMAL(6,1)) AS YoY_Pct
FROM m ORDER BY MonthStart;

-- Q3. Product profitability ranking inside each category
SELECT Category, ProductName, CAST(Revenue AS DECIMAL(14,0)) AS Revenue,
       CAST(GrossProfit AS DECIMAL(14,0)) AS GrossProfit, CAST(MarginPct AS DECIMAL(5,1)) AS MarginPct,
       RANK() OVER (PARTITION BY Category ORDER BY GrossProfit DESC) AS RankInCategory
FROM vw_ProductProfitability
ORDER BY Category, RankInCategory;

-- Q4. Pareto / ABC analysis: which products make 80% of revenue?
WITH c AS (
    SELECT ProductName, Revenue,
           SUM(Revenue) OVER (ORDER BY Revenue DESC ROWS UNBOUNDED PRECEDING) AS CumRev,
           SUM(Revenue) OVER () AS Total
    FROM vw_ProductProfitability
)
SELECT ProductName, CAST(Revenue AS DECIMAL(14,0)) AS Revenue,
       CAST(100.0 * CumRev / Total AS DECIMAL(5,1)) AS CumulativePct,
       CASE WHEN 100.0 * (CumRev - Revenue) / Total < 80 THEN 'A (top 80%)'
            WHEN 100.0 * (CumRev - Revenue) / Total < 95 THEN 'B' ELSE 'C' END AS ABC_Class
FROM c ORDER BY Revenue DESC;

-- Q5. Revenue by Channel and Region with subtotals (ROLLUP)
SELECT ISNULL(c.Channel, 'ALL CHANNELS') AS Channel, ISNULL(c.Region, 'ALL REGIONS') AS Region,
       CAST(SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS DECIMAL(14,0)) AS Revenue
FROM SalesOrders o
JOIN SalesOrderItems i ON i.OrderID = o.OrderID
JOIN Customers c ON c.CustomerID = o.CustomerID
GROUP BY ROLLUP (c.Channel, c.Region)
ORDER BY GROUPING(c.Channel), c.Channel, GROUPING(c.Region), c.Region;

-- Q6. Does discounting hurt profit? Margin by discount level
SELECT CAST(i.Discount * 100 AS INT) AS DiscountPct,
       SUM(i.Qty) AS Units,
       CAST(SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS DECIMAL(14,0)) AS Revenue,
       CAST(100.0 * SUM(i.Qty * (i.UnitPrice * (1 - i.Discount) - p.UnitCost))
            / SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS DECIMAL(5,1)) AS MarginPct
FROM SalesOrderItems i JOIN Products p ON p.ProductID = i.ProductID
GROUP BY i.Discount ORDER BY DiscountPct;

-- Q7. Customer segmentation using RFM
WITH cust AS (
    SELECT o.CustomerID,
           DATEDIFF(DAY, MAX(o.OrderDate), '2026-10-01') AS Recency,
           COUNT(DISTINCT o.OrderID) AS Frequency,
           SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS Monetary
    FROM SalesOrders o JOIN SalesOrderItems i ON i.OrderID = o.OrderID
    GROUP BY o.CustomerID
), sc AS (
    SELECT *, NTILE(4) OVER (ORDER BY Recency DESC) AS R,
              NTILE(4) OVER (ORDER BY Frequency)    AS F,
              NTILE(4) OVER (ORDER BY Monetary)     AS M
    FROM cust
)
SELECT CASE WHEN R >= 3 AND F >= 3 THEN 'Champions'
            WHEN R >= 3             THEN 'Promising'
            WHEN F >= 3             THEN 'At Risk (was loyal)'
            ELSE 'Lost / Low value' END AS Segment,
       COUNT(*) AS Customers,
       CAST(SUM(Monetary) AS DECIMAL(14,0)) AS Revenue
FROM sc GROUP BY CASE WHEN R >= 3 AND F >= 3 THEN 'Champions'
                      WHEN R >= 3             THEN 'Promising'
                      WHEN F >= 3             THEN 'At Risk (was loyal)'
                      ELSE 'Lost / Low value' END
ORDER BY Revenue DESC;

-- Q8. Top 3 customers in every region
WITH r AS (
    SELECT c.Region, c.CustomerName,
           SUM(i.Qty * i.UnitPrice * (1 - i.Discount)) AS Revenue
    FROM SalesOrders o
    JOIN SalesOrderItems i ON i.OrderID = o.OrderID
    JOIN Customers c ON c.CustomerID = o.CustomerID
    GROUP BY c.Region, c.CustomerName
), k AS (SELECT *, ROW_NUMBER() OVER (PARTITION BY Region ORDER BY Revenue DESC) AS rn FROM r)
SELECT Region, rn AS Rank_, CustomerName, CAST(Revenue AS DECIMAL(14,0)) AS Revenue FROM k WHERE rn <= 3 ORDER BY Region, rn;

-- Q9. Inventory health: stockout risk, overstock and dead stock
SELECT * FROM vw_InventoryHealth
ORDER BY CASE StockStatus WHEN 'STOCKOUT RISK' THEN 1 WHEN 'DEAD / NO SALES' THEN 2 WHEN 'OVERSTOCK' THEN 3 ELSE 4 END, DaysOfCover;

-- Q10. Money locked in dead / overstocked inventory
SELECT StockStatus, COUNT(*) AS SKUs, SUM(TotalStock) AS Units,
       CAST(SUM(StockValue) AS DECIMAL(14,0)) AS StockValueINR
FROM vw_InventoryHealth GROUP BY StockStatus ORDER BY StockValueINR DESC;

-- Q11. Reorder list: products below reorder level in the main warehouse, with suggested order qty
SELECT p.ProductName, inv.StockQty, p.ReorderLevel,
       p.ReorderLevel * 2 - inv.StockQty AS SuggestedOrderQty
FROM Inventory inv JOIN Products p ON p.ProductID = inv.ProductID
WHERE inv.WarehouseID = 1 AND inv.StockQty < p.ReorderLevel
ORDER BY inv.StockQty * 1.0 / p.ReorderLevel;

-- Q12. Production: yield and defect % per product (worst first)
SELECT p.ProductName,
       COUNT(*) AS Batches,
       CAST(100.0 * SUM(b.ProducedQty) / SUM(b.PlannedQty) AS DECIMAL(5,1)) AS YieldPct,
       CAST(100.0 * SUM(b.DefectQty) / SUM(b.ProducedQty) AS DECIMAL(5,2)) AS DefectPct,
       CAST(SUM(b.DefectQty * p.UnitCost) AS DECIMAL(14,0)) AS DefectCostINR
FROM ProductionBatches b JOIN Products p ON p.ProductID = b.ProductID
GROUP BY p.ProductName ORDER BY DefectPct DESC;

-- Q13. Batches breaching the 3% defect threshold, with a 3-batch moving average per product
WITH x AS (
    SELECT b.BatchID, p.ProductName, b.BatchDate,
           100.0 * b.DefectQty / b.ProducedQty AS DefectPct
    FROM ProductionBatches b JOIN Products p ON p.ProductID = b.ProductID
)
SELECT TOP (50) BatchID, ProductName, BatchDate,
       CAST(DefectPct AS DECIMAL(5,2)) AS DefectPct,
       CAST(AVG(DefectPct) OVER (PARTITION BY ProductName ORDER BY BatchDate ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(5,2)) AS MovingAvg3
FROM x WHERE DefectPct > 3 ORDER BY DefectPct DESC;

-- Q14. Return rate by product, and the main reason
WITH sold AS (SELECT ProductID, SUM(Qty) AS Sold FROM SalesOrderItems GROUP BY ProductID),
     ret  AS (SELECT ProductID, SUM(ReturnQty) AS Returned FROM Returns GROUP BY ProductID)
SELECT p.ProductName, s.Sold, ISNULL(r.Returned, 0) AS Returned,
       CAST(100.0 * ISNULL(r.Returned, 0) / s.Sold AS DECIMAL(5,2)) AS ReturnRatePct
FROM Products p JOIN sold s ON s.ProductID = p.ProductID LEFT JOIN ret r ON r.ProductID = p.ProductID
ORDER BY ReturnRatePct DESC;

SELECT Reason, COUNT(*) AS Returns, SUM(ReturnQty) AS Units FROM Returns GROUP BY Reason ORDER BY Units DESC;

-- Q15. Link quality: defect % vs return % (do production problems reach customers?)
WITH d AS (SELECT ProductID, 100.0 * SUM(DefectQty) / SUM(ProducedQty) AS DefectPct FROM ProductionBatches GROUP BY ProductID),
     rr AS (SELECT s.ProductID, 100.0 * ISNULL(SUM(r.ReturnQty), 0) / SUM(s.Qty) AS ReturnPct
            FROM SalesOrderItems s LEFT JOIN Returns r ON r.OrderItemID = s.OrderItemID GROUP BY s.ProductID)
SELECT p.ProductName, CAST(d.DefectPct AS DECIMAL(5,2)) AS DefectPct, CAST(rr.ReturnPct AS DECIMAL(5,2)) AS ReturnPct
FROM Products p JOIN d ON d.ProductID = p.ProductID JOIN rr ON rr.ProductID = p.ProductID
ORDER BY d.DefectPct DESC;

-- Q16. Supplier scorecard
EXEC usp_SupplierScorecard;

-- Q17. Supplier on-time trend by quarter (is it getting worse?)
SELECT s.SupplierName,
       CONCAT(YEAR(po.PODate), '-Q', DATEPART(QUARTER, po.PODate)) AS Quarter,
       CAST(100.0 * SUM(CASE WHEN po.ReceivedDate <= po.PromisedDate THEN 1 ELSE 0 END) / COUNT(*) AS DECIMAL(5,1)) AS OnTimePct
FROM PurchaseOrders po JOIN Suppliers s ON s.SupplierID = po.SupplierID
GROUP BY s.SupplierName, YEAR(po.PODate), DATEPART(QUARTER, po.PODate)
ORDER BY s.SupplierName, YEAR(po.PODate), DATEPART(QUARTER, po.PODate);

-- Q18. Daily sales summary (call the procedure)
EXEC usp_DailySalesSummary @Date = '2026-09-30';

/* =====================================================================
   9. GO LIVE: test the real-time part
   ===================================================================== */
-- Run these a few times, then check Alerts and Inventory change.
-- EXEC usp_SimulateLiveOrder;
-- SELECT TOP 10 * FROM SalesOrders ORDER BY OrderID DESC;
-- SELECT * FROM Alerts ORDER BY CreatedAt DESC;
-- SELECT * FROM vw_InventoryHealth WHERE StockStatus = 'STOCKOUT RISK';

-- SQL Server Agent job: New Job > Step type T-SQL > command: EXEC ProductCoAnalytics.dbo.usp_SimulateLiveOrder;
-- Schedule: every 1 minute. Then connect Power BI (DirectQuery) to the three vw_ views.
