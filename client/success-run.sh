#!/usr/bin/env bash
set -e

echo "Stopping existing containers..."
docker compose down -v

echo "Starting containers..."
docker compose up -d

echo "Waiting for services to be ready..."
sleep 5

echo "Running curl test..."
"$(dirname "$0")/curl.sh"