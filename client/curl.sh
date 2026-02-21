#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"

# Present client leaf + intermediate so nginx can build the chain to the trusted root.
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  --cert   <(cat "$CERTS_DIR/client/client.crt" "$CERTS_DIR/intermediate/intermediate.crt") \
  --key  "$CERTS_DIR/client/client.key" \
  https://localhost:8443/

