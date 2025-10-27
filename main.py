from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from contextlib import asynccontextmanager
import asyncio
from pathlib import Path
import json
from datetime import datetime, timedelta
import random
import io
import base64
from backend.analytics import Analytics

# --- Paths ---
FRONTEND_HTML = Path("frontend/interface.html")

# --- Config ---
MAX_POINTS = 50
UPDATE_INTERVAL = 0.5

# --- Background updater ---
def start_background_updater():
    # dummy placeholder for your liveSIM updater
    pass

@asynccontextmanager
async def lifespan(app: FastAPI):
    start_background_updater()
    yield

app = FastAPI(lifespan=lifespan)

# --- WebSocket ---
@app.websocket("/ws/multi")
async def websocket_multi(ws: WebSocket):
    await ws.accept()

    # Create a PERSISTENT Analytics instance for this WebSocket connection
    analytics_instance = Analytics()

    # --- Safe command execution in terminal with plot capture ---
    async def safe_exec(command: str):
        import io, contextlib
        import matplotlib
        matplotlib.use('Agg')  # Use non-interactive backend
        from matplotlib import pyplot as plt
        
        # Use the persistent analytics instance
        env = {"void": analytics_instance, "_": None, "__builtins__": __builtins__}
        buf = io.StringIO()
        plot_data = None
        
        with contextlib.redirect_stdout(buf):
            try:
                try:
                    result = eval(command, env)
                    if result is not None:
                        env["_"] = result
                except SyntaxError:
                    exec(command, env)
                
                # Check if any matplotlib figures were created
                if plt.get_fignums():
                    # Capture the current figure
                    img_buf = io.BytesIO()
                    plt.savefig(img_buf, format='png', bbox_inches='tight', dpi=100)
                    img_buf.seek(0)
                    plot_data = base64.b64encode(img_buf.read()).decode('utf-8')
                    plt.close('all')  # Close all figures
                    
            except Exception as e:
                print(f"Error: {e}")
        
        return buf.getvalue().strip(), plot_data

    # --- Series definitions ---
    all_series = [
        "gross", "costs", "revenue",
        "active_users", "new_users", "churned_users", "total"
    ]
    selected_series = set(all_series)

    # Latest data keyed by date
    latest_data = {}

    # Current funds for runway calculation
    current_funds = 50000  # starting funds

    # --- Generate and stream fake data ---
    async def stream_data():
        nonlocal latest_data, selected_series, current_funds
        base_time = datetime.now()
        counter = 0
        while True:
            # generate a new timestamp
            now = (base_time + timedelta(seconds=counter * UPDATE_INTERVAL)).strftime("%Y-%m-%d %H:%M:%S")
            counter += 1

            # financial metrics
            gross = round(random.uniform(1000, 5000), 2)
            costs = round(random.uniform(500, 3000), 2)
            revenue = gross - costs

            # platform metrics
            active_users = random.randint(100, 1000)
            new_users = random.randint(10, 100)
            churned_users = random.randint(0, 20)

            # total field
            total = gross + revenue + costs

            # update current funds
            current_funds += revenue - costs

            # calculate runway
            runway = current_funds / max(costs - revenue, 1)  # avoid division by zero

            # merge into single timestamp
            latest_data[now] = {
                "date": now,
                "gross": gross,
                "costs": costs,
                "revenue": revenue,
                "active_users": active_users,
                "new_users": new_users,
                "churned_users": churned_users,
                "total": total
            }

            # send the whole data for this timestamp + runway
            await ws.send_json({
                "data": latest_data[now],
                "runway": round(runway, 1)
            })

            # keep only last MAX_POINTS
            if len(latest_data) > MAX_POINTS:
                oldest = sorted(latest_data.keys())[0]
                del latest_data[oldest]

            await asyncio.sleep(UPDATE_INTERVAL)

    stream_task = asyncio.create_task(stream_data())

    # --- WebSocket receive loop ---
    try:
        while True:
            data = await ws.receive_text()
            try:
                msg = json.loads(data)
                if "plot" in msg and isinstance(msg["plot"], list):
                    selected_series = set(msg["plot"]) & set(all_series)
                    await ws.send_json({"output": f"Plotting series: {', '.join(selected_series)}"})
                elif "command" in msg:
                    cmd = msg.get("command", "").strip()
                    if cmd:
                        out, plot_data = await safe_exec(cmd)
                        response = {}
                        if out:
                            response["output"] = str(out)
                        if plot_data:
                            response["plot"] = plot_data
                        if response:
                            await ws.send_json(response)
            except json.JSONDecodeError:
                await ws.send_json({"output": "Invalid JSON"})
            except Exception as e:
                await ws.send_json({"output": f"Error: {e}"})
    except WebSocketDisconnect:
        stream_task.cancel()
    except Exception:
        stream_task.cancel()
        try:
            await ws.close()
        except:
            pass

# --- Serve frontend ---
@app.get("/")
async def get_root():
    return FileResponse(FRONTEND_HTML)