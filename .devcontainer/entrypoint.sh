#!/bin/bash
set -e

# Start SSH in the background
/usr/sbin/sshd -D &

# Start Postgres as the main process
exec docker-entrypoint.sh postgres
