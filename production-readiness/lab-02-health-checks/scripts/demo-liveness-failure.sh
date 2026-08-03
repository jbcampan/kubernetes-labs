#!/usr/bin/env bash
set -euo pipefail

POD=$(kubectl get pods -l app=health-checks-demo -o jsonpath='{.items[0].metadata.name}')
echo "Targeting pod: ${POD}"

echo "Port-forwarding 8080 -> 8080 in the background..."
kubectl port-forward "pod/${POD}" 8080:8080 >/tmp/port-forward.log 2>&1 &
PF_PID=$!
sleep 2

echo "Triggering a simulated deadlock on ${POD} (POST /simulate/blocked)..."
curl -s -X POST http://localhost:8080/simulate/blocked
echo

kill "${PF_PID}" 2>/dev/null || true

cat <<EOF

Now watch the liveness probe fail and the container restart:
  kubectl get pods -l app=health-checks-demo -w

Once RESTARTS increments, inspect the probe failure events:
  kubectl describe pod ${POD}
EOF