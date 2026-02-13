#!/usr/bin/env bash
set -e

DIR="$(dirname "$0")"

# Present client leaf + intermediate so nginx can build the chain to the trusted root.
curl -vk \
  --cacert "$DIR/../certs/ca/intermediate.crt" \
  --cert   <(cat "$DIR/../certs/client/client.crt" "$DIR/../certs/intermediate/intermediate.crt") \
  --key  "$DIR/../certs/client/client.key" \
  https://localhost:8443/

