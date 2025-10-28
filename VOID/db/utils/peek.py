# db/utils/peek.py
import os
from sqlalchemy import create_engine, text
from dotenv import load_dotenv
import pandas as pd

# --- Load environment variables ---
load_dotenv()

DB_CONFIG = {
    "dbname": os.environ.get("POSTGRES_DB"),
    "user": os.environ.get("POSTGRES_USER"),
    "password": os.environ.get("POSTGRES_PASSWORD"),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432)),
}

# --- Create SQLAlchemy engine ---
engine = create_engine(
    f"postgresql+psycopg2://{DB_CONFIG['user']}:{DB_CONFIG['password']}@"
    f"{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
)

def peek_metrics(limit=5):
    """
    Print the first N rows from the metrics table with all columns.
    """
    try:
        with engine.connect() as conn:
            # Fetch all columns for first N rows
            query = text(f"SELECT * FROM metrics ORDER BY id ASC LIMIT :limit")
            result = conn.execute(query, {"limit": limit})

            rows = result.fetchall()
            if not rows:
                print("No rows found in metrics table.")
                return

            # Convert to pandas DataFrame for pretty printing
            df = pd.DataFrame(rows, columns=result.keys())
            print(f"First {limit} rows in 'metrics' table:\n")
            print(df.to_string(index=False))
    except Exception as e:
        print(f"Error querying metrics table: {e}")

if __name__ == "__main__":
    peek_metrics()
