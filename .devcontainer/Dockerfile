# Minimal Python 3.11 dev container
FROM mcr.microsoft.com/devcontainers/python:0-3.11

# Set working directory to the container's workspace
WORKDIR /app

# Copy requirements.txt from the .devcontainer folder and install dependencies
COPY .devcontainer/requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

# Copy the rest of the project files
COPY . .

# Expose FastAPI port
EXPOSE 8000

# Default command to run FastAPI
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
