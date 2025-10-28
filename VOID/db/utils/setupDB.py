# db/db_connection.py
import psycopg2
import os
from dotenv import load_dotenv

# Load environment variables
dotenv_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path)

POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DB = os.getenv("POSTGRES_DB")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "5432")

# Construct database URL (for psycopg2)
DATABASE_URL = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

def get_connection():
    """
    Returns a psycopg2 connection object to the database.
    """
    return psycopg2.connect(
        host=POSTGRES_HOST,
        port=POSTGRES_PORT,
        database=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD
    )

# --- Test connection on import ---
if __name__ == "__main__":
    try:
        conn = get_connection()
        print(f"[SUCCESS] Connected to PostgreSQL database '{POSTGRES_DB}' as user '{POSTGRES_USER}' on host '{POSTGRES_HOST}:{POSTGRES_PORT}'")
        conn.close()
    except psycopg2.OperationalError as e:
        print(f"[ERROR] Failed to connect to PostgreSQL database '{POSTGRES_DB}' as user '{POSTGRES_USER}' on host '{POSTGRES_HOST}:{POSTGRES_PORT}'")
        print("Reason:", e)
    except Exception as e:
        print(f"[ERROR] Unexpected error while connecting to database: {e}")
