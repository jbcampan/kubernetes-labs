#!/usr/bin/env bash
# Generates a self-signed TLS certificate covering app.local and api.local,
# then creates the corresponding Kubernetes Secret (kubernetes.io/tls).
# For learning purposes only — never use self-signed certs in production.
set -euo pipefail

CERT_DIR="$(dirname "$0")/../.certs"
mkdir -p "$CERT_DIR"

openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout "$CERT_DIR/tls.key" \
  -out "$CERT_DIR/tls.crt" \
  -days 365 \
  -subj "/CN=app.local/O=k8s-labs" \
  -addext "subjectAltName=DNS:app.local,DNS:api.local"

kubectl create secret tls app-tls-secret \
  --cert="$CERT_DIR/tls.crt" \
  --key="$CERT_DIR/tls.key" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret app-tls-secret created/updated from self-signed cert."