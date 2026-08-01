#!/usr/bin/env bash
# Quick connectivity matrix for the netpol-demo namespace.
# Run BEFORE applying network policies to see the "everything is allowed"
# baseline, then again AFTER applying them to see Zero Trust in effect.
set -euo pipefail

NAMESPACE="netpol-demo"

get_pod() {
  kubectl get pod -n "$NAMESPACE" -l "app=$1" -o jsonpath='{.items[0].metadata.name}'
}

test_call() {
  local from_pod="$1"
  local from_label="$2"
  local target="$3"

  echo -n "[$from_label -> $target] "
  if kubectl exec -n "$NAMESPACE" "$from_pod" -- \
      wget -q -T 3 -O- "http://${target}.${NAMESPACE}.svc.cluster.local" > /dev/null 2>&1; then
    echo "ALLOWED"
  else
    echo "BLOCKED"
  fi
}

FRONTEND_POD=$(get_pod frontend)
BACKEND_POD=$(get_pod backend)
DATABASE_POD=$(get_pod database)

echo "=== Connectivity matrix ==="
test_call "$FRONTEND_POD" frontend backend
test_call "$FRONTEND_POD" frontend database
test_call "$BACKEND_POD" backend database
test_call "$BACKEND_POD" backend frontend
test_call "$DATABASE_POD" database backend
test_call "$DATABASE_POD" database frontend