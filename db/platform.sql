-- Platform analytics database schema

CREATE TABLE IF NOT EXISTS platform_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    record_date DATE NOT NULL,
    active_users INTEGER NOT NULL,
    new_users INTEGER NOT NULL,
    churned_users INTEGER,
    notes TEXT
);

-- Optional index for queries by date
CREATE INDEX IF NOT EXISTS idx_platform_date ON platform_metrics (record_date);

