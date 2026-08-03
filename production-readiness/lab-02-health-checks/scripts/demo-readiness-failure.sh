#!/usr/bin/env bash
set -euo pipefail

POD=$(kubectl get pods -l app=health-checks-demo -o jsonpath='{.items[0].metadata.name}')
echo "Targeting pod: ${POD}"

echo "Port-forwarding 8080 -> 8080 in the background..."
kubectl port-forward "pod/${POD}" 8080:8080 >/tmp/port-forward.log 2>&1 &
PF_PID=$!
sleep 2

echo "Triggering a simulated overload on ${POD} (POST /simulate/unready, 30s)..."
curl -s -X POST "http://localhost:8080/simulate/unready?duration=30"
echo

kill "${PF_PID}" 2>/dev/null || true

cat <<EOF

Now watch the pod disappear from (and later rejoin) the Service endpoints:
  kubectl get endpoints health-checks-demo -w

Note: the pod is NOT restarted, RESTARTS should stay unchanged:
  kubectl get pods -l app=health-checks-demo
EOF