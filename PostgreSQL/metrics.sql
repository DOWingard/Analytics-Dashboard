-- ==========================================================
--  metrics.sql  —  Business Metrics Table Schema
-- ==========================================================

-- Drop existing table and trigger if you’re resetting the schema
DROP TRIGGER IF EXISTS trg_update_funds ON metrics;
DROP FUNCTION IF EXISTS update_funds_running_sum();
DROP TABLE IF EXISTS metrics;

-- ==========================================================
--  Table Definition
-- ==========================================================
CREATE TABLE IF NOT EXISTS metrics (
    id SERIAL PRIMARY KEY,
    record_date DATE NOT NULL UNIQUE,
    funds REAL NOT NULL DEFAULT 0,                 -- running total
    costs REAL NOT NULL,
    gross REAL NOT NULL,
    revenue REAL GENERATED ALWAYS AS (gross - costs) STORED,
    users REAL NOT NULL,
    new_users REAL NOT NULL,
    churned_users REAL NOT NULL,
    revenue_per_user REAL GENERATED ALWAYS AS (
        CASE WHEN users > 0 THEN (gross - costs) / users ELSE 0 END
    ) STORED,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_metrics_date ON metrics(record_date);

-- ==========================================================
--  Trigger Function: maintain running total of funds
-- ==========================================================
CREATE OR REPLACE FUNCTION update_funds_running_sum()
RETURNS TRIGGER AS $$
BEGIN
    -- Only compute automatically if funds not supplied manually
    IF NEW.funds IS NULL OR NEW.funds = 0 THEN
        SELECT COALESCE(SUM(revenue), 0)
          INTO NEW.funds
          FROM metrics
          WHERE record_date < NEW.record_date;

        NEW.funds := NEW.funds + (NEW.gross - NEW.costs);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ==========================================================
--  Trigger Definition
-- ==========================================================
CREATE TRIGGER trg_update_funds
BEFORE INSERT ON metrics
FOR EACH ROW
EXECUTE FUNCTION update_funds_running_sum();

-- ==========================================================
--  Example Usage
-- ==========================================================
-- INSERT INTO metrics (record_date, costs, gross, users, new_users, churned_users, notes)
-- VALUES ('2025-10-27', 200, 1200, 150, 20, 5, 'steady growth week');
--
-- SELECT * FROM metrics ORDER BY record_date;
