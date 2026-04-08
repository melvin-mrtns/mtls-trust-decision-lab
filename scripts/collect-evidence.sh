#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   collect-evidence.sh <RUN_START_UTC> <OUT_DIR> <VERIFIER_CMD_FILE> <COMPOSE_DIR>
#
# - Collect enough evidence to classify the following failure cases with high confidence:
#   - MissingClientCertificateCase
#   - CertificateVerifySignatureMismatchCase
#   - MissingIntermediateCase
#   - WrongTrustAnchorCase / UntrustedSelfSignedLeafCase
#   - ExpiredCertificateCase / NotYetValidCertificateCase
#   - ExtendedKeyUsageConstraintCase / BasicConstraintsViolationCase
#   - DnsSanMismatchCase
#

if [[ $# -ne 4 ]]; then
  echo "Usage: $0 <RUN_START_UTC> <OUT_DIR> <VERIFIER_CMD_FILE> <COMPOSE_DIR>" >&2
  exit 1
fi

RUN_START_UTC="$1"
OUT="$2"
CMD_FILE="$3"
COMPOSE_DIR="$4"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "$COMPOSE_DIR" == "$ROOT_DIR" ]]; then
  COMPOSE_FILE="docker-compose.yml"
else
  COMPOSE_FILE="case-docker-compose.yml"
fi

COMPOSE_CMD="cd '$COMPOSE_DIR' && docker compose -f '$COMPOSE_FILE'"

mkdir -p "$OUT"/{environment,system,server,inputs,certs,metadata}

run() {
  local rel="$1"; shift
  local file="$OUT/$rel"
  mkdir -p "$(dirname "$file")"
  {
    echo "\$ $*"
    "$@"
  } >"$file" 2>&1 || true
}

run_sh() {
  local rel="$1"; shift
  local file="$OUT/$rel"
  mkdir -p "$(dirname "$file")"
  {
    echo "\$ $*"
    bash -lc "$*"
  } >"$file" 2>&1 || true
}

VERIFIER_CMD_RAW="$(cat "$CMD_FILE")"
printf "%s\n" "$VERIFIER_CMD_RAW" > "$OUT/metadata/verifier_cmd.raw.txt"

# Parse verifier command
CACERT=""
CERT=""
KEY=""
URL=""

# Turn newlines/backslashes into spaces for token parsing
CMD_ONELINE="$(printf "%s" "$VERIFIER_CMD_RAW" | tr '\n' ' ' | tr -d '\\')"

# Turns command into a bash array by splitting on whitespace
# shellcheck disable=SC2206
TOKENS=( $CMD_ONELINE )

# Extract decision inputs from the command
for ((i=0; i<${#TOKENS[@]}; i++)); do
  t="${TOKENS[$i]}"
  case "$t" in
    --cacert) CACERT="${TOKENS[$((i+1))]:-}" ;;
    --cert)   CERT="${TOKENS[$((i+1))]:-}" ;;
    --key)    KEY="${TOKENS[$((i+1))]:-}" ;;
    http://*|https://*) URL="$t" ;;
  esac
done

# Remove quotes from parsed variable to facilitate parsing
strip_quotes() {
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  s="${s#\'}"; s="${s%\'}"
  printf "%s" "$s"
}

CACERT="$(strip_quotes "$CACERT")"
CERT="$(strip_quotes "$CERT")"
KEY="$(strip_quotes "$KEY")"
URL="$(strip_quotes "$URL")"

# Extract host from URL if present
HOST=""
if [[ -n "$URL" ]]; then
  HOST="$URL"
  HOST="${HOST#http://}"
  HOST="${HOST#https://}"
  HOST="${HOST%%/*}"
  HOST="${HOST%%:*}"
fi

cat > "$OUT/metadata/verifier_inputs.parsed.txt" <<EOF
cacert=$CACERT
cert=$CERT
key=$KEY
url=$URL
host=$HOST
EOF

# Environment snapshots
run "environment/host_time_utc.txt" date -u
run "environment/uname.txt" uname -a
run "environment/openssl_version.txt" openssl version -a

# System snapshots
run_sh "system/compose_ps.txt" "$COMPOSE_CMD ps"
run_sh "system/compose_config.yml" "$COMPOSE_CMD config"

# Verifier snapshots (nginx)
run_sh "server/nginx_T.txt" "$COMPOSE_CMD exec -T nginx nginx -T"
run_sh "server/nginx_V.txt" "$COMPOSE_CMD exec -T nginx nginx -V 2>&1"
run_sh "server/nginx_time_utc.txt" "$COMPOSE_CMD exec -T nginx sh -lc 'date -u'"

# Snapshot container logs since run start (decision outputs)
run_sh "server/nginx_container_logs_since_run.txt" "$COMPOSE_CMD logs --no-color --since '$RUN_START_UTC' nginx"
run_sh "server/flask_container_logs_since_run.txt" "$COMPOSE_CMD logs --no-color --since '$RUN_START_UTC' flask"
run_sh "server/error.log" "$COMPOSE_CMD exec -T nginx sh -lc 'cat /var/log/nginx/error.log 2>/dev/null || true'"

# Discover nginx TLS directive paths from nginx -T output
NGINX_T="$OUT/server/nginx_T.txt"

# Extract first-match helper
extract_first() {
  local directive="$1"
  awk -v d="$directive" '
    $1==d {gsub(/;/,"",$2); print $2; exit}
  ' "$NGINX_T"
}

# Extract all matches helper
extract_all() {
  local directive="$1"
  awk -v d="$directive" '
    $1==d {gsub(/;/,"",$2); print $2}
  ' "$NGINX_T"
}

SSL_CLIENT_CERTIFICATE="$(extract_first ssl_client_certificate)"
SSL_TRUSTED_CERTIFICATE="$(extract_first ssl_trusted_certificate)"

# Ensure all ssl certs are extracted
mapfile -t SSL_CERTS < <(extract_all ssl_certificate)
mapfile -t SSL_KEYS  < <(extract_all ssl_certificate_key)

cat > "$OUT/metadata/nginx_tls_paths.txt" <<EOF
ssl_client_certificate=$SSL_CLIENT_CERTIFICATE
ssl_trusted_certificate=$SSL_TRUSTED_CERTIFICATE
ssl_certificate=$(printf "%s\n" "${SSL_CERTS[@]}")
ssl_certificate_key=$(printf "%s\n" "${SSL_KEYS[@]}")
EOF

# Copy nginx-referenced cert/trust files from the container
mkdir -p "$OUT/inputs/nginx"

# Copy file out of container and records sha256 hash for that path
copy_from_container_if_set() {
  local path="$1"
  local dst="$2"
  [[ -z "$path" ]] && return 0
  bash -lc "$COMPOSE_CMD cp 'nginx:$path' '$dst'" >/dev/null 2>&1 || true
  run_sh "${dst#$OUT/}.sha256.txt" \
  "$COMPOSE_CMD exec -T nginx sh -lc \"sha256sum '$path' 2>/dev/null || true\""
}

copy_from_container_if_set "$SSL_CLIENT_CERTIFICATE" "$OUT/inputs/nginx/ssl_client_certificate.crt"
copy_from_container_if_set "$SSL_TRUSTED_CERTIFICATE" "$OUT/inputs/nginx/ssl_trusted_certificate.crt"

# Server Certificate FullChain (or leaf only based on nginx configuration)
mkdir -p "$OUT/inputs/server"
if [[ -n "${SSL_CERTS[0]}" ]]; then
  bash -lc "$COMPOSE_CMD cp 'nginx:${SSL_CERTS[0]}' '$OUT/inputs/server/fullchain.crt'" \
    >/dev/null 2>&1 || true
  run_sh "inputs/server/fullchain.crt.sha256.txt" \
    "$COMPOSE_CMD exec -T nginx sh -lc \"sha256sum '${SSL_CERTS[0]}' 2>/dev/null || true\""
fi

# Copy client-side inputs
mkdir -p "$OUT/inputs/client"
if [[ -n "$CACERT" && -f "$CACERT" ]]; then
  cp -f "$CACERT" "$OUT/inputs/client/cacert.crt"
  run_sh "inputs/client/cacert.sha256.txt" "sha256sum '$CACERT' 2>/dev/null || true"
fi
if [[ -n "$CERT" && -f "$CERT" ]]; then
  cp -f "$CERT" "$OUT/inputs/client/cert.crt"
  run_sh "inputs/client/cert.sha256.txt" "sha256sum '$CERT' 2>/dev/null || true"
fi
if [[ -n "$KEY" && -f "$KEY" ]]; then
  # NOT a copy of private key; Just compute public key hash
  run_sh "inputs/client/key.pubkey_sha256.txt" "openssl pkey -in '$KEY' -pubout 2>/dev/null | sha256sum || true"
fi

# Certificate cert fields
mkdir -p "$OUT/certs/fields"

cert_fields() {
  local cert_path="$1"
  local out_rel="$2"
  [[ ! -f "$cert_path" ]] && return 0

  {
    echo "## file=$cert_path"
    openssl x509 -in "$cert_path" -noout -subject -issuer -serial -dates -fingerprint -sha256 2>/dev/null || true
    echo
    echo "## SAN / EKU / KU / BasicConstraints (best-effort)"
    openssl x509 -in "$cert_path" -noout -text 2>/dev/null | \
      awk '
        /X509v3 Subject Alternative Name/ {p=1}
        /X509v3 Extended Key Usage/ {p=1}
        /X509v3 Key Usage/ {p=1}
        /X509v3 Basic Constraints/ {p=1}
        p==1 {print}
        /^[[:space:]]*X509v3/ && $0 !~ /(Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints)/ {p=0}
      ' || true
  } > "$OUT/$out_rel" 2>&1 || true
}

# Client cert fields
if [[ -f "$OUT/inputs/client/cert.crt" ]]; then
  cert_fields "$OUT/inputs/client/cert.crt" "certs/fields/client_cert.txt"
fi

# CA cert fields
if [[ -f "$OUT/inputs/client/cacert.crt" ]]; then
  cert_fields "$OUT/inputs/client/cacert.crt" "certs/fields/client_cacert.txt"
fi

# Nginx trust store cert fields (server-side trust for client certs)
if [[ -n "$SSL_CLIENT_CERTIFICATE" ]]; then
  # Extract directly from container since copy may fail
  bash -lc "$COMPOSE_CMD exec -T nginx sh -lc \"openssl x509 -in '$SSL_CLIENT_CERTIFICATE' -noout -subject -issuer -serial -dates -fingerprint -sha256 2>/dev/null || true\"" > "$OUT/certs/fields/nginx_ssl_client_certificate.txt" 2>&1 || true
fi

# Nginx presented server cert fields (extract from first ssl_certificate path)
if [[ -n "${SSL_CERTS[0]}" ]]; then
  # Extract directly from container
  bash -lc "$COMPOSE_CMD exec -T nginx sh -lc \"openssl x509 -in '${SSL_CERTS[0]}' -noout -subject -issuer -serial -dates -fingerprint -sha256 2>/dev/null || true\"" > "$OUT/certs/fields/server_cert.txt" 2>&1 || true
  # Also get SAN/EKU/KU/BasicConstraints
  bash -lc "$COMPOSE_CMD exec -T nginx sh -lc \"openssl x509 -in '${SSL_CERTS[0]}' -noout -text 2>/dev/null | grep -A2 -E 'X509v3 (Subject Alternative Name|Extended Key Usage|Key Usage|Basic Constraints)' || true\"" >> "$OUT/certs/fields/server_cert.txt" 2>&1 || true
fi

# Wrong-key detection support (cert pubkey hash vs key pubkey hash)
if [[ -f "$OUT/inputs/client/cert.crt" ]]; then
  run_sh "inputs/client/cert.pubkey_sha256.txt" \
    "openssl x509 -in '$OUT/inputs/client/cert.crt' -pubkey -noout 2>/dev/null | openssl pkey -pubin -outform PEM 2>/dev/null | sha256sum || true"
fi

echo "Evidence collected into $OUT"