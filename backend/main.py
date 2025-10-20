from fastapi import FastAPI, WebSocket
from fastapi.responses import HTMLResponse
import math, asyncio, time

app = FastAPI()

html = """
<!DOCTYPE html>
<html>
    <head><title>Live Sine Demo</title></head>
    <body>
        <h1>Live Sine Wave Data</h1>
        <div id="output"></div>
        <script>
            const ws = new WebSocket("ws://" + location.host + "/ws");
            ws.onmessage = (event) => {
                const data = JSON.parse(event.data);
                document.getElementById("output").innerText = 
                    `t=${data.t.toFixed(2)} | sin(t)=${data.y.toFixed(3)}`;
            };
        </script>
    </body>
</html>
"""

@app.get("/")
async def get():
    return HTMLResponse(html)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await websocket.accept()
    t = 0.0
    while True:
        y = math.sin(t)
        await websocket.send_json({"t": t, "y": y})
        t += 0.1
        await asyncio.sleep(0.1)
