# db/fillYear.py
import psycopg2
from datetime import date, timedelta
import random
import os
from dotenv import load_dotenv

# Load environment variables from .env
load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "../.env"))

DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
DB_PORT = int(os.getenv("POSTGRES_PORT", 5432))
DB_NAME = os.getenv("POSTGRES_DB", "nullanddb")
DB_USER = os.getenv("POSTGRES_USER", "nullandvoid")
DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")

# Path to the metrics SQL schema
SQL_FILE = os.path.join(os.path.dirname(__file__), "../metrics.sql")

def setup_db(conn):
    """Create metrics table and triggers if they don't exist."""
    if not os.path.exists(SQL_FILE):
        raise FileNotFoundError(f"metrics.sql not found at {SQL_FILE}")

    with open(SQL_FILE, "r", encoding="utf-8") as f:
        schema_sql = f.read()

    cursor = conn.cursor()
    cursor.execute(schema_sql)
    conn.commit()
    cursor.close()
    print("[>] Database schema ensured from metrics.sql")

def populate_metrics(conn, days=365):
    """
    Populate the `metrics` table with synthetic data.
    Works with generated columns (revenue, revenue_per_user).
    """
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("""
        SELECT EXISTS (
            SELECT FROM information_schema.tables 
            WHERE table_name = 'metrics'
        );
    """)
    exists = cursor.fetchone()[0]
    if not exists:
        setup_db(conn)

    # Start values
    funds = 100_000
    users = 50
    churn_rate = 0.02
    
    for i in range(days):
        record_date = date.today() - timedelta(days=days - i)
        
        # Simulate user growth
        new_users = max(1, int(users * 0.05 + random.randint(-2, 3)))
        churned_users = int(users * churn_rate)
        users = users + new_users - churned_users
        
        # Costs and gross (revenue is generated automatically)
        costs = max(0, int(funds * 0.01 + users*2 + random.randint(-50, 50)))
        gross = users * 50 + random.randint(-20, 20)
        
        # Insert row
        cursor.execute("""
            INSERT INTO metrics
            (record_date, funds, costs, gross, users, new_users, churned_users, notes)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (record_date) DO NOTHING
        """, (
            record_date, funds, costs, gross, users, new_users, churned_users, None
        ))
        
        funds += (gross - costs)
    
    conn.commit()
    cursor.close()
    print(f"[>] Inserted {days} days of synthetic metrics (skipped existing dates).")

if __name__ == "__main__":
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )
    populate_metrics(conn)
    conn.close()
