# backend/sense.py
import io, contextlib, re
import numpy as np
import matplotlib
matplotlib.use("Agg")
from matplotlib import pyplot as plt
from datetime import datetime
import os, sqlite3
import base64
from .utils.chebyshev import Cheby as cheby
import subprocess
from  VOID.seeker.client.seeker import SEEKR as ckr
import psycopg2
from dotenv import load_dotenv

class SENSE:
    """
    Class of methods to control live data visualization safely for WebSocket.
    """

    def __init__(self):
        self.cheb = cheby(degree=99)
        self.last_poly = None  # store last polynomial for derivative
        self.ckr = ckr()


    def help(self):
        """
        Print available commands and usage.
        """
        print("Available commands:")

        commands = [
            ("void.help()", "Show this help message"),
            ("void.ping()", "ping the DB"),
            ("void.printDB()", "Print all available columns from all DBs"),
            ("void.model('<x_col>','<y_col>')", "Plot y_col vs x_col"),
            ("void.modelDeriv()", "Plot derivative of last model"),
            ("TODO: void.swapX(<var>)", "Swap X-variable of last model"),
        ]

        max_len = max(len(cmd[0]) for cmd in commands)
        for cmd, desc in commands:
            print(f"> {cmd.ljust(max_len)} : {desc}")

    def swapX(self, command: str, env=None):
        """
        Safe swapX placeholder; no WS crash.
        """
        print("swapX is a TODO placeholder. Command ignored.")
        return ""

    @staticmethod
    def _toNumeric(series):
        """
        Convert a list/array of values to numeric floats safely.
        Non-numeric or None values become np.nan.
        """
        numeric = []
        for v in series:
            if v is None:
                numeric.append(np.nan)
                continue
            try:
                numeric.append(float(v))
            except Exception:
                try:
                    dt = datetime.fromisoformat(str(v))
                    numeric.append(dt.timestamp())
                except Exception:
                    numeric.append(np.nan)
        return np.array(numeric, dtype=float)

    def model(self, x_col: str, y_col: str):
        """
        Generate Chebyshev polynomial from two PostgreSQL columns and return plot as base64.
        Uses SEEKR instance (self.ckr) to query the metrics table.
        """
        # Use SEEKR to fetch data as dict
        data = self.ckr.metrics_as_dict(x_col, y_col)
        if not data:
            print("[!] No data found in metrics table.")
            return None

        # Extract x and y series
        x_orig, y_orig = [], []
        for date_str, row in data.items():
            x_val = row.get(x_col)
            y_val = row.get(y_col)
            if x_val is not None and y_val is not None:
                x_orig.append(x_val)
                y_orig.append(y_val)

        if not x_orig or not y_orig:
            print(f"[!] Columns '{x_col}' or '{y_col}' have no valid data.")
            return None

        x_orig = np.array(x_orig, dtype=float)
        y_orig = np.array(y_orig, dtype=float)

        # Normalize x to [-1, 1]
        x_cheb = 2 * (x_orig - np.nanmin(x_orig)) / max(np.nanmax(x_orig) - np.nanmin(x_orig), 1e-8) - 1

        # Express y as Chebyshev polynomial
        if self.cheb:
            self.last_poly = self.cheb.express(lambda x: np.interp(x, x_cheb, y_orig))
            y_cheb = self.last_poly(x_cheb)
        else:
            y_cheb = np.interp(x_cheb, x_cheb, y_orig)

        # Plot to buffer
        buf = io.BytesIO()
        plt.figure(figsize=(8, 5))
        plt.plot(x_orig, y_cheb, color='cyan',
                label=f'{y_col} vs {x_col} (Chebyshev)')
        plt.title(f'{y_col} vs {x_col}')
        plt.xlabel(x_col)
        plt.ylabel(y_col)
        plt.grid(True, linestyle='--', alpha=0.5)
        plt.legend()
        plt.savefig(buf, format='png', bbox_inches='tight', dpi=100)
        plt.close('all')
        buf.seek(0)
        return base64.b64encode(buf.read()).decode('utf-8')

    def modelDeriv(self):
        """
        Plot derivative of last Chebyshev model. Returns base64 plot.
        """
        if self.last_poly is None:
            print("No model established. Call model() first.")
            return None

        points = 100
        x_orig = np.linspace(0, points-1, points)
        x_cheb = 2 * x_orig / (points-1) - 1
        deriv_poly = self.cheb.deriv()
        y_deriv_cheb = deriv_poly(x_cheb)
        y_deriv_scaled = y_deriv_cheb * (2 / (points-1))

        buf = io.BytesIO()
        plt.figure(figsize=(8,5))
        plt.plot(x_orig, y_deriv_scaled, color='magenta', label='Derivative')
        plt.title("Derivative Model")
        plt.xlabel("Original x indices")
        plt.ylabel("dy/dx")
        plt.grid(True, linestyle='--', alpha=0.5)
        plt.legend()
        plt.savefig(buf, format='png', bbox_inches='tight', dpi=100)
        plt.close('all')
        buf.seek(0)
        return base64.b64encode(buf.read()).decode('utf-8')

    def printDB(self):
        """
        Print all columns from all SQLite DBs in ../db/
        """
        script_dir = os.path.dirname(os.path.abspath(__file__))
        db_dir = os.path.abspath(os.path.join(script_dir, '..', 'db'))
        if not os.path.exists(db_dir):
            print(f"Database directory not found: {db_dir}")
            return

        db_files = [f for f in os.listdir(db_dir) if f.endswith('.db')]
        if not db_files:
            print(f"No .db files found in {db_dir}")
            return

        print("\nAvailable fields in databases:\n" + "-"*40)
        for db_file in db_files:
            db_path = os.path.join(db_dir, db_file)
            try:
                conn = sqlite3.connect(db_path)
                cursor = conn.cursor()
                cursor.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view')")
                tables = [t[0] for t in cursor.fetchall()]
                for table in tables:
                    cursor.execute(f"PRAGMA table_info({table})")
                    columns = [c[1] for c in cursor.fetchall() if c[1].lower() not in ('id','notes')]
                    if columns:
                        print(f"\nDatabase: {db_file}\nTable/View: {table}")
                        for col in columns:
                            print(f"  - {col}")
                conn.close()
            except Exception as e:
                print(f"Error reading {db_file}: {e}")
        print("\n" + "-"*40)


    def ping(self):
        """
        Run the pingDB.bat file with default flag --null.
        """
        script_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        ping_path = os.path.join(script_dir, 'scripts', 'pingDB.bat')

        if not os.path.exists(ping_path):
            print(f"[!] pingDB.bat not found at {ping_path}")
            return

        try:
            # Default to main user
            result = subprocess.run(
                [ping_path, "--null"],
                shell=True,
                capture_output=True,
                text=True
            )
            print(result.stdout)
            if result.stderr:
                print(result.stderr)
        except Exception as e:
            print(f"[!] Error running pingDB.bat: {e}")
