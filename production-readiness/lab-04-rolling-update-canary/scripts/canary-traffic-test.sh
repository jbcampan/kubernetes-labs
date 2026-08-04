#!/usr/bin/env bash
# Sends a batch of HTTP requests to the canary-demo Service (via an existing
# `kubectl port-forward`) and tallies how many responses came from the
# STABLE track vs the CANARY track. Useful to verify the ~90/10 split
# implied by the 9 stable / 1 canary replica ratio.
set -euo pipefail

URL="${1:-http://localhost:8082}"
REQUESTS="${2:-50}"

stable_count=0
canary_count=0

echo "Sending ${REQUESTS} requests to ${URL} ..."

for i in $(seq 1 "${REQUESTS}"); do
  response=$(curl -s "${URL}")
  if [[ "${response}" == *"STABLE"* ]]; then
    stable_count=$((stable_count + 1))
  elif [[ "${response}" == *"CANARY"* ]]; then
    canary_count=$((canary_count + 1))
  else
    echo "Unexpected response: ${response}"
  fi
done

echo ""
echo "Results over ${REQUESTS} requests:"
echo "  STABLE: ${stable_count} ($(( stable_count * 100 / REQUESTS ))%)"
echo "  CANARY: ${canary_count} ($(( canary_count * 100 / REQUESTS ))%)"