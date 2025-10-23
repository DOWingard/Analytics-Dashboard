# db/setupDB.py
import sqlite3
from pathlib import Path

DB_FOLDER = Path(__file__).parent

DATABASES = {
    "financial": "financial.sql",
    "platform": "platform.sql"
}

def create_database(sql_file_path: Path, db_file_path: Path):
    """Creates a SQLite database from a SQL file."""
    if not sql_file_path.exists():
        print(f"SQL file not found: {sql_file_path}")
        return

    conn = sqlite3.connect(db_file_path)
    with open(sql_file_path, "r") as f:
        sql_script = f.read()
    conn.executescript(sql_script)
    conn.commit()
    conn.close()
    print(f"Created database: {db_file_path}")

def main():
    for db_name, sql_filename in DATABASES.items():
        sql_file = DB_FOLDER / sql_filename
        db_file = DB_FOLDER / f"{db_name}.db"
        create_database(sql_file, db_file)

if __name__ == "__main__":
    main()
