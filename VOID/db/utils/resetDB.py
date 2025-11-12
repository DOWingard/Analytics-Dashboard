# # db/utils/resetDB.py
# import psycopg2
# from psycopg2 import sql, errors
# import os
# from dotenv import load_dotenv

# # Load environment variables from .env
# load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), ".env"))

# DB_HOST = os.getenv("POSTGRES_HOST", "localhost")
# DB_PORT = os.getenv("POSTGRES_PORT", 5432)
# DB_NAME = os.getenv("POSTGRES_DB", "nullanddb")
# DB_USER = os.getenv("POSTGRES_USER", "nullandvoid")
# DB_PASSWORD = os.getenv("POSTGRES_PASSWORD", "")


# def reset_database(conn):
#     """
#     Completely empties the metrics table and resets any auto-increment sequences.
#     If the table does not exist, it will be created.
#     """
#     cursor = conn.cursor()
#     try:
#         cursor.execute("""
#             TRUNCATE TABLE metrics RESTART IDENTITY CASCADE;
#         """)
#         print("[>] Database has been reset: all rows removed and IDs reset.")
#     except errors.UndefinedTable:
#         print("[!] Table 'metrics' does not exist. Creating table...")
#         cursor.execute("""
#             CREATE TABLE metrics (
#                 record_date DATE PRIMARY KEY,
#                 active_users INT,
#                 new_users INT,
#                 churned_users INT
#             );
#         """)
#         print("[>] Table 'metrics' created.")
#     finally:
#         conn.commit()
#         cursor.close()
