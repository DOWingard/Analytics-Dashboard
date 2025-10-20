from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse
import asyncio
from datetime import datetime
import random  # demo only, replace with real API calls

app = FastAPI()

html = """
<!DOCTYPE html>
<html>
<head>
  <title>Top 100 Stocks Live</title>
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
</head>
<body>
  <h1>Top 100 Stocks Live</h1>
  <canvas id="chart" width="1200" height="600"></canvas>
  <script>
    const ctx = document.getElementById('chart').getContext('2d');
    const datasets = [];

    const tickers = Array.from({length: 100}, (_, i) => "STOCK" + (i+1));
    tickers.forEach((t, i) => {
      datasets.push({
        label: t,
        borderColor: `hsl(${i*3.6}, 70%, 50%)`,
        backgroundColor: 'transparent',
        data: []
      });
    });

    const chart = new Chart(ctx, {
      type: 'line',
      data: { datasets: datasets },
      options: {
        animation: false,
        responsive: true,
        scales: {
          x: { type: 'linear', title: { display: true, text: 'Time (s)' } },
          y: { title: { display: true, text: 'Price' } }
        }
      }
    });

    const ws = new WebSocket(`${window.location.protocol.replace("http","ws")}//${window.location.host}/ws/stocks`);
    let startTime = Date.now();

    ws.onmessage = (event) => {
      const msg = JSON.parse(event.data);
      const t = (Date.now() - startTime) / 1000; // seconds since page load

      tickers.forEach((ticker, idx) => {
        chart.data.datasets[idx].data.push({ x: t, y: msg[ticker] });
        // keep last 50 points per stock
        if (chart.data.datasets[idx].data.length > 50) {
          chart.data.datasets[idx].data.shift();
        }
      });

      // Only update after pushing all data
      chart.update('none');
    };
  </script>
</body>
</html>

"""

@app.get("/")
async def get_root():
    return HTMLResponse(html)

# Demo function: replace with async API call to Polygon/IEX/Alpaca
async def fetch_latest_prices():
    # Simulate 100 stocks with random prices
    return {f"STOCK{i+1}": round(100 + random.random()*50, 2) for i in range(100)}

@app.websocket("/ws/stocks")
async def websocket_stocks(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            prices = await fetch_latest_prices()
            await ws.send_json(prices)
            await asyncio.sleep(1)  # 1 second updates
    except Exception:
        await ws.close()
