# printColumns.py
import os
from sqlalchemy import create_engine, inspect
from dotenv import load_dotenv

# --- Load .env ---
load_dotenv()

# --- DB config ---
DB_CONFIG = {
    "dbname": os.environ.get("POSTGRES_DB", "nullanddb"),
    "user": os.environ.get("POSTGRES_USER", "nullandvoid"),
    "password": os.environ.get("POSTGRES_PASSWORD", ""),
    "host": os.environ.get("POSTGRES_HOST", "localhost"),
    "port": int(os.environ.get("POSTGRES_PORT", 5432)),
}

# --- SQLAlchemy engine ---
engine = create_engine(
    f"postgresql+psycopg2://{DB_CONFIG['user']}:{DB_CONFIG['password']}@"
    f"{DB_CONFIG['host']}:{DB_CONFIG['port']}/{DB_CONFIG['dbname']}"
)

def print_columns(table_name="metrics"):
    try:
        inspector = inspect(engine)
        columns = inspector.get_columns(table_name)
        if not columns:
            print(f"[!] Table '{table_name}' does not exist or has no columns.")
            return
        print(f"Columns in '{table_name}':")
        for col in columns:
            print(f"- {col['name']} ({col['type']})")
    except Exception as e:
        print(f"[!] Error inspecting table '{table_name}': {e}")

if __name__ == "__main__":
    print_columns()
