-- Financial database schema

CREATE TABLE IF NOT EXISTS financial (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_date DATE NOT NULL,
    gross REAL NOT NULL,
    costs REAL NOT NULL,
    revenue REAL GENERATED ALWAYS AS (gross - costs) VIRTUAL,
    notes TEXT
);

-- Optional index to query by date faster
CREATE INDEX IF NOT EXISTS idx_financial_date ON financial (record_date);
