#!/bin/bash
set -e

# -----------------------------
# Start Postgres in background
# -----------------------------
docker-entrypoint.sh postgres &

# -----------------------------
# Wait for Postgres to be ready
# -----------------------------
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  sleep 1
done

echo "[INFO] Ensuring local user exists with full privileges..."

# -----------------------------
# Ensure primary user
# -----------------------------
if [ -n "$POSTGRES_USER" ] && [ -n "$POSTGRES_PASSWORD" ]; then
  EXISTS=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_roles WHERE rolname='$POSTGRES_USER'")
  if [ "$EXISTS" != "1" ]; then
    echo "[INFO] Creating local user $POSTGRES_USER..."
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE ROLE $POSTGRES_USER WITH LOGIN PASSWORD '$POSTGRES_PASSWORD' SUPERUSER CREATEROLE CREATEDB REPLICATION BYPASSRLS;"
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"
  else
    echo "[INFO] Local user $POSTGRES_USER already exists, ensuring full privileges..."
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER ROLE $POSTGRES_USER WITH SUPERUSER CREATEROLE CREATEDB REPLICATION BYPASSRLS;"
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $POSTGRES_USER;"
  fi
fi



# -----------------------------
# Wait for Postgres to finish (keeps container alive)
# -----------------------------
wait
