from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.middleware.cors import CORSMiddleware
import asyncio
from pathlib import Path
from dotenv import load_dotenv
from VOID.seeker.client.seeker import SEEKR
from VOID.glimpse.sense import SENSE
import uvicorn
import io, sys, contextlib, base64
import matplotlib.pyplot as plt

# --- Paths ---
FRONTEND_HTML = Path("frontend/interface.html")

# --- Config ---
UPDATE_INTERVAL = 1.0  # seconds

# --- Load .env ---
load_dotenv()

# --- Initialize SEEKR ---
ckr = SEEKR()

# --- Initialize SEEKR ---
void = SENSE()


# --- FastAPI App ---
app = FastAPI(title="Live Metrics Dashboard")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Metrics WebSocket ---
@app.websocket("/ws/metrics")
async def websocket_metrics(ws: WebSocket):
    await ws.accept()
    try:
        while True:
            metrics_data = ckr.metrics_as_dict() or {}
            runway_months = ckr.compute_runway(metrics_data)

            data_list = []
            for date, values in metrics_data.items():
                row = {"record_date": date}
                for k, v in values.items():
                    try:
                        row[k] = float(v or 0)
                    except Exception:
                        row[k] = 0.0
                data_list.append(row)

            await ws.send_json({
                "data": data_list,
                "runway": runway_months
            })
            await asyncio.sleep(UPDATE_INTERVAL)
    except WebSocketDisconnect:
        pass
    except Exception as e:
        print(f"[!] Metrics WS error: {e}")
        try:
            await ws.close()
        except:
            pass

# --- REPL WebSocket ---
command_history = []

@app.websocket("/ws/repl")
async def websocket_repl(ws: WebSocket):
    await ws.accept()
    banner = "[hint: void.help()]\n>>> "
    await ws.send_json({"type": "text", "content": banner})

    repl_globals = {"void": void, "plt": plt}
    
    try:
        while True:
            msg = await ws.receive_text()
            command_history.append(msg)  # store command

            stdout = io.StringIO()
            plot_sent = False
            try:
                with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stdout):
                    # first try eval
                    try:
                        result = eval(msg, repl_globals)
                        if result is not None:
                            print(result)
                    except SyntaxError:
                        # fallback to exec
                        exec(msg, repl_globals)

                    # check for matplotlib figures
                    figs = [plt.figure(n) for n in plt.get_fignums()]
                    for fig in figs:
                        buf = io.BytesIO()
                        fig.savefig(buf, format="png")
                        plt.close(fig)
                        buf.seek(0)
                        img_b64 = base64.b64encode(buf.read()).decode()
                        await ws.send_json({"type":"plot","content":img_b64})
                        plot_sent = True
            except Exception as e:
                print(f"Error: {e}")

            output = stdout.getvalue()
            if output.strip():
                # send output to frontend
                await ws.send_json({"type": "text", "content": output})
            # send prompt
            await ws.send_json({"type": "text", "content": ">>> "})
            # also print to server console
            if output.strip():
                print(output, end="")
            if plot_sent:
                print("[Plot sent to frontend]")
    except WebSocketDisconnect:
        pass

# --- Serve Frontend ---
@app.get("/")
async def get_root():
    if not FRONTEND_HTML.exists():
        return {"error": "Frontend file not found"}
    return FileResponse(FRONTEND_HTML)

# --- Run server ---
if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000, reload=True)
