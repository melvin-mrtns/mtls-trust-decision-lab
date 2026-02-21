#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"

# NOT presenting client certificate.
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  https://localhost:8443/