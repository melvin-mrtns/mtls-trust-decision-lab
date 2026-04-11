#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"
COMPOSE_DIR="$ROOT_DIR"

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$ROOT_DIR/evidence/BCV_$RUN_ID"
RUN_START_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$ROOT_DIR/runlogs/nginx" "$OUT/server"
: > "$ROOT_DIR/runlogs/nginx/access.log"
: > "$ROOT_DIR/runlogs/nginx/error.log"
(cd "$COMPOSE_DIR" && docker compose -f docker-compose.yml exec -T nginx nginx -s reopen) >/dev/null 2>&1 || true

mkdir -p "$OUT/metadata" "$OUT/client"
echo "$RUN_START_UTC" > "$OUT/metadata/run_start_utc.txt"
echo "UsageConstraintFailure/BasicConstraintsViolationCase" > "$OUT/metadata/run_case.txt"

# Generate client leaf cert with wrong basic constraints (CA:TRUE instead of CA:FALSE)
openssl genrsa -out "$CASE_DIR/wrong_basic_constraints_client.key" 2048

openssl req -new -sha256 \
  -key "$CASE_DIR/wrong_basic_constraints_client.key" \
  -subj "/C=US/O=Lab Client/CN=lab-client-wrong-basic-constraints" \
  -out "$CASE_DIR/wrong_basic_constraints_client.csr"

openssl x509 -req -sha256 \
  -in "$CASE_DIR/wrong_basic_constraints_client.csr" \
  -CA "$CERTS_DIR/intermediate/intermediate.crt" \
  -CAkey "$CERTS_DIR/intermediate/intermediate.key" \
  -CAcreateserial \
  -days 365 \
  -out "$CASE_DIR/wrong_basic_constraints_client.crt" \
  -extfile "$CASE_DIR/wrong_basic_constraints_client.ext" \
  -extensions v3_client_wrong_ca

cat "$CASE_DIR/wrong_basic_constraints_client.crt" "$CERTS_DIR/intermediate/intermediate.crt" > \
  "$CASE_DIR/wrong_basic_constraints_client.fullchain.crt"

# Present client leaf cert with basicConstraints=CA:TRUE (wrong for a leaf)
VERIFIER_CMD=$(cat <<EOF
curl -v \
  --cacert "$CERTS_DIR/ca/root.crt" \
  --cert   "$CASE_DIR/wrong_basic_constraints_client.fullchain.crt" \
  --key    "$CASE_DIR/wrong_basic_constraints_client.key" \
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