#!/bin/bash
set -e

# Start SSH in background
/usr/sbin/sshd -D &

# Start Postgres in background
docker-entrypoint.sh postgres &

# Wait for Postgres to be ready
until pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"; do
  sleep 1
done

echo "[INFO] Ensuring both users exist with full privileges..."

# Define users and passwords explicitly
users=(
  "$POSTGRES_USER:$POSTGRES_PASSWORD"
  "$POSTGRES_USER_SECOND:$POSTGRES_PASSWORD_SECOND"
)

for entry in "${users[@]}"; do
  user="${entry%%:*}"
  password="${entry##*:}"

  if [ -n "$user" ] && [ -n "$password" ]; then
    EXISTS=$(psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_roles WHERE rolname='$user'")
    if [ "$EXISTS" != "1" ]; then
      echo "[INFO] Creating user $user..."
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE ROLE $user WITH LOGIN PASSWORD '$password' SUPERUSER CREATEROLE CREATEDB REPLICATION BYPASSRLS;"
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $user;"
    else
      echo "[INFO] User $user already exists, ensuring full privileges..."
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "ALTER ROLE $user WITH SUPERUSER CREATEROLE CREATEDB REPLICATION BYPASSRLS;"
      psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "GRANT ALL PRIVILEGES ON DATABASE $POSTGRES_DB TO $user;"
    fi
  fi
done

wait
