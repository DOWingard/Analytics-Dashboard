# backend/analytics.py
import io, contextlib, re, math
from .utils.chebyshev import Cheby as cheby
from matplotlib import pyplot as plt
from datetime import datetime
import numpy as np
import sqlite3
import sys
import os

class Analytics:
    """
    Class of methods to control live data visualization.
    """

    def __init__(self):
        self.cheb = cheby(degree=99)

    def help(self):
        """
        Print available commands and usage.
        """
        print("Available commands:")

        commands = [
            ("void.help()", "Pretty obvious at this point"),
            ("void.swapX(<var>)", "Swap the X-variable of the plot to <var>"),
            ("void.model()", "Plot comparison using chebyshev basis"),
        ]

        # determine max width of command column
        max_len = max(len(cmd[0]) for cmd in commands)

        # print nicely aligned
        for cmd, desc in commands:
            print(f"> {cmd.ljust(max_len)} : {desc}")

    def swapX(self,command: str):
        """
        TODO: make this swam the X-variable of plot.
        """
        print("TODO: make this swam the X-variable of plot.")
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            try:
                # Convert barewords to strings for known functions
                # Example: swapX(Date) -> swapX("Date")
                command = re.sub(
                    r'(\bvoid\.swapX\s*\(\s*)([A-Za-z_][A-Za-z0-9_]*)\s*\)',
                    r'\1"\2")', command
                )

                try:
                    result = eval(command, env)
                    env["_"] = result if result is not None else env["_"]
                except SyntaxError:
                    exec(command, env)
            except Exception as e:
                print(f"Error: {e}")
        return buf.getvalue().strip()

    def model(self, x_col: str, y_col: str):
        """
        Generate a Chebyshev polynomial from any two columns in any database
        in ../db/, each sorted by its own record_date, and plot the result.
        """
        import os, sqlite3, numpy as np
        import matplotlib.pyplot as plt
        from datetime import datetime

        script_dir = os.path.dirname(os.path.abspath(__file__))
        db_dir = os.path.abspath(os.path.join(script_dir, '..', 'db'))
        if not os.path.exists(db_dir):
            print(f"Database directory not found: {db_dir}")
            return

        db_files = [f for f in os.listdir(db_dir) if f.endswith('.db')]
        if not db_files:
            print(f"No .db files found in {db_dir}")
            return

        def to_numeric(series):
            numeric = []
            for v in series:
                if v is None:
                    numeric.append(np.nan)
                    continue
                try:
                    numeric.append(float(v))
                except ValueError:
                    try:
                        dt = datetime.fromisoformat(str(v))
                        numeric.append(dt.timestamp())
                    except Exception:
                        raise ValueError(f"Cannot convert value to float: {v}")
            return np.array(numeric, dtype=float)

        def fetch_column(col_name):
            """
            Fetch a column from any table/view in any DB, ordered by its own record_date.
            Returns: (numpy array, 'db.table') or (None, None)
            """
            col_name_lower = col_name.lower()
            for db_file in db_files:
                db_path = os.path.join(db_dir, db_file)
                try:
                    conn = sqlite3.connect(db_path)
                    cursor = conn.cursor()

                    # Get all tables and views
                    cursor.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view')")
                    tables = [t[0] for t in cursor.fetchall()]

                    for table in tables:
                        try:
                            # Fetch table columns
                            cursor.execute(f"PRAGMA table_info('{table}')")
                            columns_info = cursor.fetchall()  # [(cid, name, type, ...)]
                            # Map lowercase -> actual column names
                            columns = {c[1].lower(): c[1] for c in columns_info}
                            if col_name_lower in columns:
                                actual_col = columns[col_name_lower]

                                # If record_date exists, order by it
                                if 'record_date' in columns:
                                    cursor.execute(f"SELECT \"{actual_col}\" FROM \"{table}\" ORDER BY \"record_date\"")
                                else:
                                    cursor.execute(f"SELECT \"{actual_col}\" FROM \"{table}\"")
                                data = cursor.fetchall()
                                if data:
                                    conn.close()
                                    return np.array([row[0] for row in data], dtype=float), f"{db_file}.{table}"
                        except sqlite3.Error:
                            continue
                    conn.close()
                except sqlite3.Error:
                    continue
            return None, None

        x_orig, x_source = fetch_column(x_col)
        y_orig, y_source = fetch_column(y_col)

        if x_orig is None:
            print(f"Column '{x_col}' not found in any database.")
            return
        if y_orig is None:
            print(f"Column '{y_col}' not found in any database.")
            return

        # Truncate to shorter series
        min_len = min(len(x_orig), len(y_orig))
        x_orig = x_orig[:min_len]
        y_orig = y_orig[:min_len]

        # Normalize x to [-1,1]
        x_cheb = 2 * (x_orig - np.nanmin(x_orig)) / (np.nanmax(x_orig) - np.nanmin(x_orig)) - 1

        # Express y as Chebyshev polynomial
        poly = self.cheb.express(lambda x: np.interp(x, x_cheb, y_orig))
        y_cheb = poly(x_cheb)

        # Plot
        plt.figure(figsize=(8,5))
        plt.plot(x_orig, y_cheb, color='cyan',
                label=f'{y_col} ({y_source}) vs {x_col} ({x_source}) (Chebyshev)')
        plt.title(f'{y_col} vs {x_col}')
        plt.xlabel(f'{x_col} ({x_source})')
        plt.ylabel(f'{y_col} ({y_source})')
        plt.grid(True, linestyle='--', alpha=0.5)
        plt.legend()
        plt.show()




    def modelDeriv(self):
        """
        Calculate and plot the derivative of the previously established model.
        Requires model() to be called first to establish the Chebyshev polynomial.
        """
        try:
            # Check if a polynomial has been established
            if self.cheb.poly is None:
                raise ValueError("No model established. Call model() first to create a Chebyshev polynomial.")
            
            # Number of points (same as model())
            points = 100
            
            # Original x indices mapped to [-1,1] for Chebyshev
            x_orig = np.linspace(0, points-1, points)
            x_cheb = 2 * x_orig / (points-1) - 1
            
            # Calculate derivative (this modifies self.cheb.poly in place)
            deriv_poly = self.cheb.deriv()
            
            # Evaluate derivative at x_cheb
            # Note: Need to scale by chain rule factor because we mapped coordinates
            # dy/dx_orig = dy/dx_cheb * dx_cheb/dx_orig = dy/dx_cheb * 2/(points-1)
            y_deriv_cheb = deriv_poly(x_cheb)
            y_deriv_scaled = y_deriv_cheb * (2 / (points-1))
            
            # Plot
            plt.figure(figsize=(8,5))
            plt.plot(x_orig, y_deriv_scaled, color='magenta', label='Derivative')
            plt.title("Derivative Model")
            plt.xlabel("Original x indices")
            plt.ylabel("dy/dx")
            plt.grid(True, linestyle='--', alpha=0.5)
            plt.legend()
            plt.show()
            
        except ValueError as ve:
            print(f"Error: {ve}")
        except Exception as e:
            print(f"Error in modelDeriv(): {e}")


    def printDB(self):
        """
        Prints all available columns from all tables and views in any database
        in ../db/, ignoring 'id' and 'notes'.
        """
        import sqlite3, os

        try:
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

                    # Get all tables and views
                    cursor.execute("SELECT name FROM sqlite_master WHERE type IN ('table','view')")
                    tables = [t[0] for t in cursor.fetchall()]

                    for table in tables:
                        cursor.execute(f"PRAGMA table_info({table})")
                        columns = [col[1] for col in cursor.fetchall() if col[1].lower() not in ('id','notes')]

                        if columns:
                            print(f"\nDatabase: {db_file}\nTable/View: {table}")
                            for col in columns:
                                print(f"  - {col}")

                    conn.close()

                except sqlite3.Error as e:
                    print(f"Error reading {db_file}: {e}")
                    continue

            print("\n" + "-"*40)

        except Exception as e:
            print(f"Error in printDB(): {e}")




    def toNumeric(series):
        """
        Convert a list/array of values to numeric floats.
        - If already numeric, returns as float array
        - If strings look like dates/timestamps, converts to seconds since epoch
        """
        numeric = []
        for v in series:
            try:
                numeric.append(float(v))  # already numeric
            except ValueError:
                # Try parsing as datetime
                try:
                    dt = datetime.fromisoformat(v)  # handles "YYYY-MM-DD HH:MM:SS"
                    numeric.append(dt.timestamp())   # float seconds since epoch
                except Exception:
                    raise ValueError(f"Cannot convert value to float: {v}")
        return np.array(numeric, dtype=float)

