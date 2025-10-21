from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse
from contextlib import asynccontextmanager
import asyncio
import sqlite3
from pathlib import Path
import json
from testing.liveSIM import run_live_update
import threading

# --- Paths ---
DB_PATH = Path("db/financial.db")

# --- Background thread management ---
def start_background_updater():
    """Start live financial updater in background."""
    thread = threading.Thread(target=run_live_update, args=(5,), daemon=True)
    thread.start()
    print("🚀 Live updater thread started.")


# --- Modern lifespan handler ---
@asynccontextmanager
async def lifespan(app: FastAPI):
    start_background_updater()
    yield
    print("🛑 FastAPI shutting down.")


app = FastAPI(lifespan=lifespan)


# --- Helper: fetch revenue data from DB ---
def fetch_revenue_data():
    """Return (dates, revenues) for last 365 records."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT record_date, revenue
        FROM financial
        ORDER BY record_date ASC
        LIMIT 365
    """)
    rows = cursor.fetchall()
    conn.close()
    return [{"date": r[0], "revenue": r[1]} for r in rows]


# --- Frontend HTML ---
html = """
<!DOCTYPE html>
<html>
<head>
  <title>Company Revenue Live</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h1>Company Revenue (Last 365 Days)</h1>
  <canvas id="chart" width="1200" height="600"></canvas>
  <script>
    const ctx = document.getElementById('chart').getContext('2d');
    const chart = new Chart(ctx, {
      type: 'line',
      data: { datasets: [{
        label: "Revenue",
        borderColor: "hsl(200, 70%, 50%)",
        backgroundColor: "transparent",
        data: []
      }] },
      options: {
        animation: false,
        responsive: true,
        scales: {
          x: { type: 'category', title: { display: true, text: 'Date' } },
          y: { title: { display: true, text: 'Revenue ($)' } }
        }
      }
    });

    const ws = new WebSocket(`${window.location.protocol.replace("http","ws")}//${window.location.host}/ws/revenue`);

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      chart.data.datasets[0].data = msg.map(d => ({ x: d.date, y: d.revenue }));
      chart.update('none');
    };
  </script>
</body>
</html>
"""


@app.get("/")
async def get_root():
    return HTMLResponse(html)


# --- WebSocket stream for revenue updates ---
@app.websocket("/ws/revenue")
async def websocket_revenue(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            data = fetch_revenue_data()
            await ws.send_text(json.dumps(data))
            await asyncio.sleep(5)  # match DB update rate
    except Exception:
        await ws.close()
