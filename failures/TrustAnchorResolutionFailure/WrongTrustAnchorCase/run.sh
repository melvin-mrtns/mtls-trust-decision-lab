#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"
COMPOSE_DIR="$ROOT_DIR"
CASE_DIR="$(cd "$(dirname "$0")" && pwd)"

RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$ROOT_DIR/evidence/WTA_$RUN_ID"
RUN_START_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

mkdir -p "$ROOT_DIR/runlogs/nginx" "$OUT/server"
: > "$ROOT_DIR/runlogs/nginx/access.log"
: > "$ROOT_DIR/runlogs/nginx/error.log"
(cd "$COMPOSE_DIR" && docker compose -f docker-compose.yml exec -T nginx nginx -s reopen) >/dev/null 2>&1 || true

mkdir -p "$OUT/metadata" "$OUT/client"
echo "$RUN_START_UTC" > "$OUT/metadata/run_start_utc.txt"
echo "TrustAnchorResolutionFailure/WrongTrustAnchorCase" > "$OUT/metadata/run_case.txt"

# Create a new client CA that is not trusted by the server
openssl genrsa -out "$CASE_DIR/wrong_ca.key" 4096
	openssl req -new -sha256 \
      -key "$CASE_DIR/wrong_ca.key" \
      -subj "/C=US/O=Lab Root CA/CN=lab-wrong-ca" \
      -out "$CASE_DIR/wrong_ca.csr"
	openssl x509 -req -sha256 \
		-in "$CASE_DIR/wrong_ca.csr" \
		-signkey "$CASE_DIR/wrong_ca.key" \
		-days 3650 \
		-out "$CASE_DIR/wrong_ca.crt" \
		-extfile certs/root/root.ext \
		-extensions v3_root_ca

# Client using a trust anchor that is not trusted by the server
VERIFIER_CMD=$(cat <<EOF
curl -v \
  --cacert "$CASE_DIR/wrong_ca.crt" \
  --cert   "$CERTS_DIR/client/client.fullchain.crt" \
  --key    "$CERTS_DIR/client/client.key" \
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