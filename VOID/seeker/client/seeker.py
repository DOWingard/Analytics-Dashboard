# seekr/seekr.py
import os
import pandas as pd
from sqlalchemy import create_engine, text
from dotenv import load_dotenv

class SEEKR:
    """
    SEEKR: queries VOID-ABYSS.
    """

    DEFAULT_COLUMNS = [
        "funds", "costs", "gross", "revenue",
        "users", "new_users", "churned_users", "revenue_per_user"
    ]

    def __init__(self):
        load_dotenv()
        self.db_config = {
            "dbname": os.environ["POSTGRES_DB"],
            "user": os.environ["POSTGRES_USER"],
            "password": os.environ["POSTGRES_PASSWORD"],
            "host": os.environ.get("POSTGRES_HOST", "localhost"),
            "port": int(os.environ.get("POSTGRES_PORT", 5432)),
        }

        self.engine = create_engine(
            f"postgresql+psycopg2://{self.db_config['user']}:{self.db_config['password']}@"
            f"{self.db_config['host']}:{self.db_config['port']}/{self.db_config['dbname']}"
        )

        # Validate database connection
        self._check_db()

    # --- Internal Methods ---
    def _check_db(self):
        """Ensure database is reachable and table exists."""
        try:
            with self.engine.connect() as conn:
                conn.execute(text("SELECT 1"))
                exists = conn.execute(text("""
                    SELECT EXISTS (
                        SELECT 1 FROM information_schema.tables WHERE table_name = 'metrics'
                    );
                """)).scalar()
                if not exists:
                    raise RuntimeError("Table 'metrics' does not exist in the database")
        except Exception as e:
            raise RuntimeError(f"[SEEKR] Database not reachable or misconfigured: {e}")

    # --- Public Methods ---
    def metrics_as_dict(self, *columns):
        """
        Return metrics as a dict keyed by date.
        Optionally, provide a subset of column names as *columns.
        If none are provided, returns all DEFAULT_COLUMNS.
        Example:
        metrics_as_dict('funds', 'costs') -> only returns these two per date
        """
        cols_to_fetch = list(columns) if columns else self.DEFAULT_COLUMNS
        sql_cols = ", ".join(["record_date"] + cols_to_fetch)
        query = f"""
            SELECT {sql_cols} FROM metrics
            ORDER BY record_date ASC
        """

        try:
            df = pd.read_sql(query, self.engine)
            df["record_date"] = pd.to_datetime(df["record_date"])
        except Exception as e:
            print(f"[SEEKR] Error fetching metrics: {e}")
            return {}

        data = {}
        for _, row in df.iterrows():
            date_str = row["record_date"].strftime("%Y-%m-%d")
            data[date_str] = {col: float(row[col] or 0) for col in cols_to_fetch}
        return data

    def compute_runway(self, data):
        """Compute runway in months based on last record."""
        if not data:
            return 0.0
        last = list(data.values())[-1]
        burn = (last.get("costs") or 0) - (last.get("revenue") or 0)
        if burn <= 0:
            return float("inf")
        return (last.get("funds") or 0) / burn
    
    def ping(self):
        """
        SEEKR ping the AVYSS
        """
        try:
            self._check_db()  # silently verify DB
        except Exception:
            print("[!] Database unreachable or misconfigured")
            return

        data = self.metrics_as_dict()
        if not data:
            print("[!] No metrics found")
            return

        first_date = list(data.keys())[0]
        first_row = data[first_date]

        print(f"First record ({first_date}): {first_row}")

