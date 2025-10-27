import psycopg2
import os
from dotenv import load_dotenv

# ==========================================================
# Load environment variables from .env in the same folder
# ==========================================================
dotenv_path = os.path.join(os.path.dirname(__file__), ".env")
load_dotenv(dotenv_path)

# ==========================================================
# Build database connection string from .env
# ==========================================================
POSTGRES_USER = os.getenv("POSTGRES_USER")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD")
POSTGRES_DB = os.getenv("POSTGRES_DB")
POSTGRES_HOST = os.getenv("POSTGRES_HOST", "localhost")
POSTGRES_PORT = os.getenv("POSTGRES_PORT", "6969")

DATABASE_URL = f"postgresql://{POSTGRES_USER}:{POSTGRES_PASSWORD}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

# Path to metrics.sql (assumed in same folder)
SQL_FILE = os.path.join(os.path.dirname(__file__), "metrics.sql")

# ==========================================================
# Script Execution
# ==========================================================
def main():
    if not os.path.exists(SQL_FILE):
        print(f"[!] File not found: {SQL_FILE}")
        return

    # Read the schema file
    with open(SQL_FILE, "r", encoding="utf-8") as f:
        schema_sql = f.read()

    try:
        # Connect to PostgreSQL
        conn = psycopg2.connect(DATABASE_URL)
        conn.autocommit = True
        cur = conn.cursor()

        # Execute the SQL commands
        cur.execute(schema_sql)
        cur.close()
        conn.close()

        print("[>] metrics.sql executed successfully. Database initialized.")
    except Exception as e:
        print("[!] Error executing metrics.sql:", e)

# ==========================================================
# Entry point
# ==========================================================
if __name__ == "__main__":
    main()
