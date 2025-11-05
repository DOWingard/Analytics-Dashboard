import os
from sqlalchemy import create_engine, inspect
from dotenv import load_dotenv

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

def print_header(title):
    print("\n" + "=" * 70)
    print(title)
    print("=" * 70)

def print_schema():
    try:
        inspector = inspect(engine)
        tables = inspector.get_table_names()
        if not tables:
            print("[!] No tables found in database.")
            return

        print_header(f"Database: {DB_CONFIG['dbname']}")
        print("Tables:")
        for t in tables:
            print(f"  - {t}")

        for table in tables:
            print_header(f"TABLE: {table}")

            # --- Columns ---
            print("[COLUMNS]")
            columns = inspector.get_columns(table)
            for col in columns:
                line = f"  {col['name']:20} {col['type']} {'NOT NULL' if not col['nullable'] == False else 'NULL'}"
                if col.get("default"):
                    line += f" Default={col['default']}"
                print(line)

            # --- Primary Keys ---
            pk = inspector.get_pk_constraint(table)
            print("\n[PRIMARY KEYS]")
            pk_cols = pk.get("constrained_columns", []) if pk else []
            print("  " + ", ".join(pk_cols) if pk_cols else "  (none)")

            # --- Foreign Keys ---
            fkeys = inspector.get_foreign_keys(table)
            print("\n[FOREIGN KEYS]")
            if not fkeys:
                print("  (none)")
            else:
                for fk in fkeys:
                    print(f"  {fk['constrained_columns']} → {fk['referred_table']}({fk['referred_columns']})")

            # --- Indexes ---
            indexes = inspector.get_indexes(table)
            print("\n[INDEXES]")
            if not indexes:
                print("  (none)")
            else:
                for idx in indexes:
                    print(f"  {idx['name']} (unique={idx['unique']})")

        print("\n" + "-" * 70)
        print("Database schema inspection complete.")
        print("-" * 70)

    except Exception as e:
        print(f"[!] Error inspecting database: {e}")

if __name__ == "__main__":
    print_schema()
