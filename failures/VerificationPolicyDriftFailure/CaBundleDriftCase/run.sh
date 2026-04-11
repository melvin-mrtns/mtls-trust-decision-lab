#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$ROOT_DIR/evidence/CBD_$RUN_ID"
RUN_START_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$ROOT_DIR/runlogs/nginx" "$OUT/server"
: > "$ROOT_DIR/runlogs/nginx/access.log"
: > "$ROOT_DIR/runlogs/nginx/error.log"

mkdir -p "$OUT/metadata" "$OUT/client"
echo "$RUN_START_UTC" > "$OUT/metadata/run_start_utc.txt"
echo "VerificationPolicyDriftFailure/CaBundleDriftCase" > "$OUT/metadata/run_case.txt"

# Run 1: succeeds exactly like the baseline success
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  --cert   "$CERTS_DIR/client/client.fullchain.crt" \
  --key    "$CERTS_DIR/client/client.key" \
  https://localhost:8443/ 2>&1 | tee "$OUT/baseline/client/handshake.txt" || true

# Generate a new CA for the server
openssl genrsa -out "$CASE_DIR/wrong_root.key" 4096
openssl req -new -sha256 \
    -key "$CASE_DIR/wrong_root.key" \
    -subj "/C=US/O=Lab Root CA/CN=lab-ca-bundle-drift" \
    -out "$CASE_DIR/wrong_root.csr"
openssl x509 -req -sha256 \
		-in "$CASE_DIR/wrong_root.csr" \
		-signkey "$CASE_DIR/wrong_root.key" \
		-days 3650 \
		-out "$CASE_DIR/wrong_root.crt" \
		-extfile "$CERTS/root/root.ext" \
		-extensions v3_root_ca

# Bring down root nginx
(cd "$ROOT_DIR" && docker compose -f docker-compose.yml stop nginx) >/dev/null 2>&1 || true

# Bring up nginx for this case (case-specific compose)
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml up -d --force-recreate nginx)

# Reload nginx
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml exec -T nginx nginx -s reopen) >/dev/null 2>&1 || true

# Run 2: failures despite the same client request because the server's CA has changed
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  --cert   "$CERTS_DIR/client/client.fullchain.crt" \
  --key    "$CERTS_DIR/client/client.key" \
  https://localhost:8443/ 2>&1 | tee "$OUT/baseline/client/handshake.txt" || true

RUN_END_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "$RUN_END_UTC" > "$OUT/metadata/run_end_utc.txt"

cp "$ROOT_DIR/runlogs/nginx/access.log" "$OUT/drift/access.log" 2>/dev/null || true
cp "$ROOT_DIR/runlogs/nginx/error.log"  "$OUT/drift/error.log"  2>/dev/null || true

# Collect evidence
"$ROOT_DIR/scripts/collect-evidence.sh" "$RUN_START_UTC" "$OUT"

# Analyze
python3 "$ROOT_DIR/scripts/analyze_run.py" "$OUT"

# Stop case nginx, then restore root nginx
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml stop nginx) >/dev/null 2>&1 || true
(cd "$ROOT_DIR" && docker compose -f docker-compose.yml up -d --force-recreate nginx) >/dev/null 2>&1 || true