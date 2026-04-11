#!/usr/bin/env bash
set -e

echo "Stopping existing containers..."
docker compose down -v

echo "Starting containers..."
docker compose up -d

echo "Waiting for Flask to be ready..."
for i in $(seq 1 60); do
  if docker compose exec -T flask python -c "import socket; s=socket.socket(); s.settimeout(1); s.connect(('127.0.0.1', 5000)); s.close()" >/dev/null 2>&1; then
    echo "Flask is ready."
    exit 0
  fi
  sleep 1
done

echo "ERROR: Not able to bring up Flask in time..." >&2
exit 1