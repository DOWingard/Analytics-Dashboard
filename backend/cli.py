# backend/cli.py
import typer
from analytics import get_live_data

app = typer.Typer()

@app.command()
def show():
    print(get_live_data())

if __name__ == "__main__":
    app()
