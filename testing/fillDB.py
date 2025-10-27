import sqlite3
from pathlib import Path
from datetime import date, timedelta
import random

# Database path relative to project root
DB_PATH_FINANCIAL = Path(__file__).resolve().parent.parent / "fakeDB/financial.db"

conn = sqlite3.connect(DB_PATH_FINANCIAL)
cursor = conn.cursor()


# Generate a year of daily financial data
start_date = date(2025, 1, 1)
num_days = 365

for i in range(num_days):
    current_date = start_date + timedelta(days=i)
    gross = round(random.uniform(1000, 5000), 2)  # Random gross between $1k-$5k
    costs = round(random.uniform(500, gross * 0.9), 2)  # Random costs, less than gross
    notes = f"Test data for {current_date}"

    cursor.execute(
        """
        INSERT INTO financial (record_date, gross, costs, notes)
        VALUES (?, ?, ?, ?)
        """,
        (current_date, gross, costs, notes)
    )

# Commit and close
conn.commit()
conn.close()

print(f"Inserted {num_days} rows into the financial table.")