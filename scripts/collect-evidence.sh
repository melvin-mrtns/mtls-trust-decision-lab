#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/collect-evidence.sh (Collects evidence for the baseline success run)
#   ./scripts/collect-evidence.sh FailureCase (Collects evidence for a failure run)
#
# Output:
#   evidence/<RUN_ID>/...  (timestamped bundle)
#
# This script does not modify configuration or certificates.
# It triggers exactly one handshake (success or a named failure) and captures evidence around that run.

CASE_NAME="${1:-baseline-success}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAIL_DIR="$ROOT_DIR/failure-cases/$CASE_NAME"
EVIDENCE_DIR="$ROOT_DIR/evidence"
RUN_START_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
RUN_ID="${CASE_NAME}-$(date -u +"%Y%m%dT%H%M%SZ")"
OUT="$EVIDENCE_DIR/$RUN_ID"

mkdir -p "$OUT"
mkdir -p "$OUT/metadata"
mkdir -p "$OUT/environment"
mkdir -p "$OUT/system"
mkdir -p "$OUT/verifier"
mkdir -p "$OUT/client"
mkdir -p "$OUT/certs"
mkdir -p "$OUT/network"

# Helper: run a command, capture stdout+stderr, preserve exit code in a .rc file
run() {
  local name="$1"; shift
  local file="$OUT/$name"
  {
    echo "\$ $*"
    "$@"
  } >"$file" 2>&1 || echo "$?" >"$file.rc"
}

# Helper: run a shell pipeline (for cases where pipes/redirection are needed)
run_sh() {
  local name="$1"; shift
  local file="$OUT/$name"
  {
    echo "\$ $*"
    bash -lc "$*"
  } >"$file" 2>&1 || echo "$?" >"$file.rc"
}

echo "Collecting evidence into: $OUT"
echo "$RUN_ID" > "$OUT/metadata/run_id.txt"
echo "$CASE_NAME" > "$OUT/metadata/case_name.txt"
date -u > "$OUT/metadata/utc_time.txt"

# Basic environment context
run "environment/uname.txt" uname -a
run "environment/docker_version.txt" docker version
run "environment/compose_version.txt" docker compose version
run "environment/openssl_version.txt" openssl version -a

# Compose state
run_sh "system/compose_ps.txt" "cd '$ROOT_DIR' && docker compose ps"
run_sh "system/compose_config_resolved.yml" "cd '$ROOT_DIR' && docker compose config"

# Handshake capture from the client side
if [[ "$CASE_NAME" == "baseline-success" ]]; then
  run_sh "client/curl_verbose.txt" "cd '$ROOT_DIR' && ./client/success-run.sh"
else
  FAIL_RUNNER="$FAIL_DIR/run.sh"
  run_sh "client/curl_verbose.txt" "cd '$ROOT_DIR' && '$FAIL_RUNNER'"
fi

# Output Handshake result in the terminal
echo "Handshake result:"
if grep -q "OK - mTLS handshake succeeded" "$OUT/client/curl_verbose.txt"; then
  echo "OK - mTLS handshake succeeded"
elif grep -q "No required SSL certificate was sent" "$OUT/client/curl_verbose.txt"; then
  echo "No required SSL certificate was sent"
else
  # fallback: show HTTP status line if present, otherwise last 5 lines
  grep -E "^< HTTP/" "$OUT/client/curl_verbose.txt" | tail -n 1 || tail -n 5 "$OUT/client/curl_verbose.txt" || true
fi

# Nginx config as seen inside the verifier container
run_sh "verifier/nginx_T.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx nginx -T"

# Logs (Decision outputs from the verifier)
run_sh "verifier/nginx_logs.txt" "cd '$ROOT_DIR' && docker compose logs --no-color --since '$RUN_START_UTC' nginx"
run_sh "verifier/flask_logs.txt" "cd '$ROOT_DIR' && docker compose logs --no-color --since '$RUN_START_UTC' flask"

# Connectivity checks (proves upstream is reachable from the network)
run_sh "network/dns_from_nginx_getent_hosts_flask.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx sh -lc 'getent hosts flask || true'"
run_sh "network/tcp_from_nginx_to_flask_5000.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx sh -lc 'nc -zv flask 5000 || true'"

# Certificate inspection (inputs to the decision graph)
run_sh "certs/root_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/root/root.crt -noout -subject -issuer -dates"
run_sh "certs/intermediate_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/intermediate/intermediate.crt -noout -subject -issuer -dates"
run_sh "certs/server_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/server/server.crt -noout -subject -issuer -dates"
run_sh "certs/client_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/client/client.crt -noout -subject -issuer -dates"

# Extract SAN + EKU/KU in a consistent way
run_sh "certs/server_san_eku_ku.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/server/server.crt -noout -text | egrep -n 'Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints' -A2"
run_sh "certs/client_san_eku_ku.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/client/client.crt -noout -text | egrep -n 'Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints' -A2"

# Verifier-style checks (evidence collectors)
run_sh "certs/verify_server_as_sslserver.txt" "cd '$ROOT_DIR' && openssl verify -CAfile certs/ca/root.crt -untrusted certs/intermediate/intermediate.crt -purpose sslserver certs/server/server.crt || true"
run_sh "certs/verify_client_as_sslclient.txt" "cd '$ROOT_DIR' && openssl verify -CAfile certs/ca/root.crt -untrusted certs/intermediate/intermediate.crt -purpose sslclient certs/client/client.crt || true"

# openssl s_client transcript
if [[ "$CASE_NAME" == "baseline-success" ]]; then
  run_sh "openssl_s_client.txt" "cd '$ROOT_DIR' && openssl s_client -connect localhost:8443 -servername localhost -showcerts -CAfile certs/ca/root.crt -cert certs/client/client.crt -key certs/client/client.key </dev/null || true"
elif [[ "$CASE_NAME" == "MissingClientCertFailure" ]]; then
  run_sh "openssl_s_client.txt" "cd '$ROOT_DIR' && openssl s_client -connect localhost:8443 -servername localhost -showcerts -CAfile certs/ca/root.crt </dev/null || true"
fi

# Summary stub
cat > "$OUT/summary.txt" <<EOF
Case: $CASE_NAME
Run:  $RUN_ID
Time: $(cat "$OUT/metadata/utc_time.txt")

- Run metadata (what was collected, when):
  - run_id.txt
  - case_name.txt
  - utc_time.txt

- Environment context (so outputs are reproducible):
  - env_*.txt

- System state (what was running, from which compose):
  - compose_ps.txt
  - compose_config_resolved.yml

- Verifier config (policy + enforcement inputs actually in effect):
  - nginx_T.txt

- Verifier outputs (decision outputs observed from the verifier):
  - nginx_logs.txt
  - flask_logs.txt

- Reachability checks (proves nginx can resolve and connect to the Flask service):
  - dns_from_nginx_getent_hosts_flask.txt
  - tcp_from_nginx_to_flask_5000.txt

- Certificate inputs (what identities and issuers were used):
  - cert_*.txt

- Verifier-style cert validation checks (purpose/path checks as evidence):
  - verify_server_as_sslserver.txt
  - verify_client_as_sslclient.txt

- Client transcript (proves what was presented + handshake/HTTP outcome):
  - curl_verbose.txt
  - openssl_s_client.txt

- Exit code (if any command failed):
  - *.rc
EOF

echo "Done: $OUT"
