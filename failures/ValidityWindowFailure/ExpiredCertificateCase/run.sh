#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPOSE_DIR="$CASE_DIR"

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$ROOT_DIR/evidence/EC_$RUN_ID"
RUN_START_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Bring down root nginx
(cd "$ROOT_DIR" && docker compose -f docker-compose.yml stop nginx) >/dev/null 2>&1 || true

# Bring up nginx for this case that has a fake time of 2 days in the future (case-specific compose)
export DOCKER_UID="$(id -u)"
export DOCKER_GID="$(id -g)"
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml up -d --force-recreate --build nginx)

mkdir -p "$ROOT_DIR/runlogs/nginx" "$OUT/server"
: > "$ROOT_DIR/runlogs/nginx/access.log"
: > "$ROOT_DIR/runlogs/nginx/error.log"
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml exec -T nginx nginx -s reopen) >/dev/null 2>&1 || true


mkdir -p "$OUT/metadata" "$OUT/client"
echo "$RUN_START_UTC" > "$OUT/metadata/run_start_utc.txt"
echo "ValidityWindowFailure/ExpiredCertificateCase" > "$OUT/metadata/run_case.txt"

# Create client key + CSR
openssl genrsa -out "$CASE_DIR/client_expired.key" 2048

openssl req -new -sha256 \
  -key "$CASE_DIR/client_expired.key" \
  -subj "/C=US/O=Lab Client/CN=lab-client-expired" \
  -out "$CASE_DIR/client_expired.csr"

# Create trusted but expired client cert
# NotBefore = 2 days ago, validity length only 1 day (expired 1 day ago)
# Use faketime to create cert dated 2 days ago
FAKETIME="-2d" openssl x509 -req -sha256 \
  -in "$CASE_DIR/client_expired.csr" \
  -CA "$CERTS_DIR/intermediate/intermediate.crt" \
  -CAkey "$CERTS_DIR/intermediate/intermediate.key" \
  -CAcreateserial \
  -out "$CASE_DIR/client_expired.crt" \
  -extfile "$CERTS_DIR/client/client.ext" \
  -extensions v3_client \
  -days 1

cat "$CASE_DIR/client_expired.crt" "$CERTS_DIR/intermediate/intermediate.crt" > "$CASE_DIR/client_expired.fullchain.crt"

# Present expired but trusted client cert
VERIFIER_CMD=$(cat <<EOF
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  --cert   "$CASE_DIR/client_expired.fullchain.crt" \
  --key    "$CASE_DIR/client_expired.key" \
  https://localhost:8443/
EOF
)

printf "%s\n" "$VERIFIER_CMD" > "$OUT/metadata/verifier_cmd.sh"

bash -lc "$VERIFIER_CMD" 2>&1 | tee "$OUT/client/handshake.txt" || true

RUN_END_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "$RUN_END_UTC" > "$OUT/metadata/run_end_utc.txt"

cp "$ROOT_DIR/runlogs/nginx/access.log" "$OUT/server/access.log" 2>/dev/null || true
cp "$ROOT_DIR/runlogs/nginx/error.log"  "$OUT/server/error.log"  2>/dev/null || true

# Collect evidence
"$ROOT_DIR/scripts/collect-evidence.sh" \
  "$RUN_START_UTC" \
  "$OUT" \
  "$OUT/metadata/verifier_cmd.sh" \
  "$COMPOSE_DIR"

# Analyze
python3 "$ROOT_DIR/scripts/analyze_run.py" "$OUT"

# Stop case nginx, then restore root nginx
(cd "$COMPOSE_DIR" && docker compose -f case-docker-compose.yml down) >/dev/null 2>&1 || true
(cd "$ROOT_DIR" && docker compose -f docker-compose.yml up -d --force-recreate nginx) >/dev/null 2>&1 || true