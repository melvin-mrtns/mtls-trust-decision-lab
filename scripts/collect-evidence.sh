#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/collect-evidence.sh (Collects evidence for the baseline success run)
#   ./scripts/collect-evidence.sh FailureCase (Collects evidence for a failure run)
#
# Output:
#   evidence/<RUN_ID>/...  (timestamped bundle)
#
# This script never changes the system. It only collects proof from the current state.

CASE_NAME="${1:-baseline-success}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/evidence"
RUN_ID="$(date -u +"%Y%m%dT%H%M%SZ")-${CASE_NAME}"
OUT="$EVIDENCE_DIR/$RUN_ID"

mkdir -p "$OUT"

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
echo "$RUN_ID" > "$OUT/run_id.txt"
echo "$CASE_NAME" > "$OUT/case_name.txt"
date -u > "$OUT/utc_time.txt"

# Basic environment context
run "env_uname.txt" uname -a
run "env_docker_version.txt" docker version
run "env_compose_version.txt" docker compose version
run "env_openssl_version.txt" openssl version -a

# Compose state
run_sh "compose_ps.txt" "cd '$ROOT_DIR' && docker compose ps"
run_sh "compose_config_resolved.yml" "cd '$ROOT_DIR' && docker compose config"

# Nginx config as seen inside the verifier container
run_sh "nginx_T.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx nginx -T"

# Logs (Decision outputs from the verifier)
run_sh "nginx_logs.txt" "cd '$ROOT_DIR' && docker compose logs --no-color --tail=300 nginx"
run_sh "flask_logs.txt" "cd '$ROOT_DIR' && docker compose logs --no-color --tail=300 flask"

# Connectivity checks (proves upstream is reachable from the network)
run_sh "dns_from_nginx_getent_hosts_flask.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx sh -lc 'getent hosts flask || true'"
run_sh "tcp_from_nginx_to_flask_5000.txt" "cd '$ROOT_DIR' && docker compose exec -T nginx sh -lc 'nc -zv flask 5000 || true'"

# Certificate inspection (inputs to the decision graph)
run_sh "cert_root_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/root/root.crt -noout -subject -issuer -dates"
run_sh "cert_intermediate_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/intermediate/intermediate.crt -noout -subject -issuer -dates"
run_sh "cert_server_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/server/server.crt -noout -subject -issuer -dates"
run_sh "cert_client_subject_issuer.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/client/client.crt -noout -subject -issuer -dates"

# Extract SAN + EKU/KU in a consistent way
run_sh "cert_server_san_eku_ku.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/server/server.crt -noout -text | egrep -n 'Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints' -A2"
run_sh "cert_client_san_eku_ku.txt" "cd '$ROOT_DIR' && openssl x509 -in certs/client/client.crt -noout -text | egrep -n 'Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints' -A2"

# Verifier-style checks (evidence collectors)
run_sh "verify_server_as_sslserver.txt" "cd '$ROOT_DIR' && openssl verify -CAfile certs/ca/root.crt -purpose sslserver certs/server/server.crt || true"
run_sh "verify_client_as_sslclient.txt" "cd '$ROOT_DIR' && openssl verify -CAfile certs/ca/root.crt -purpose sslclient certs/client/client.crt || true"

# Handshake capture from the client side
run_sh "curl_verbose.txt" "cd '$ROOT_DIR' && ./client/curl.sh || true"

# openssl s_client transcript
run_sh "openssl_s_client.txt" "cd '$ROOT_DIR' && openssl s_client -connect localhost:8443 -servername localhost -showcerts -CAfile certs/ca/root.crt -cert certs/client/client.crt -key certs/client/client.key </dev/null || true"

# Summary stub
cat > "$OUT/summary.txt" <<EOF
Case: $CASE_NAME
Run:  $RUN_ID
Time: $(cat "$OUT/utc_time.txt")

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
