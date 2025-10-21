import sqlite3
from pathlib import Path
from datetime import datetime
import random
import time

DB_PATH_FINANCIAL = Path(__file__).resolve().parent.parent / "db/financial.db"

def insert_random_entry():
    """Insert one random financial record and keep only the latest 365 entries."""
    conn = sqlite3.connect(DB_PATH_FINANCIAL)
    cursor = conn.cursor()

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    gross = round(random.uniform(1000, 5000), 2)
    costs = round(random.uniform(500, gross * 0.9), 2)
    notes = f"Auto update {now}"

    # Insert new row
    cursor.execute(
        """
        INSERT INTO financial (record_date, gross, costs, notes)
        VALUES (?, ?, ?, ?)
        """,
        (now, gross, costs, notes)
    )

    # Delete oldest rows if over 365 total
    cursor.execute("""
        DELETE FROM financial
        WHERE id NOT IN (
            SELECT id FROM financial
            ORDER BY record_date DESC
            LIMIT 365
        );
    """)

    conn.commit()
    conn.close()
    print(f"Inserted new entry at {now} | gross={gross}, costs={costs}")


    
def run_live_update(interval: int = 5):
    """Continuously insert data every `interval` seconds."""
    print(f"Starting live updates every {interval} seconds. Press Ctrl+C to stop.\n")
    try:
        while True:
            insert_random_entry()
            time.sleep(interval)
    except KeyboardInterrupt:
        print("\nStopped live updates.")

if __name__ == "__main__":
    run_live_update(5)
