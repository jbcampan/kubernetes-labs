#!/usr/bin/env bash
# Launches a busybox pod that hammers hpa-demo-service in an infinite
# loop, generating enough CPU load on hpa-demo pods to trigger the HPA
# scale-up. Delete the pod (kubectl delete pod load-generator) to stop
# the load and observe the scale-down.
#
# MSYS_NO_PATHCONV=1 prevents Git Bash on Windows from rewriting the
# leading "/bin/sh" argument into a Windows path (e.g. "C:/Program
# Files/Git/usr/bin/sh") before it reaches kubectl. This has no effect
# on Linux/macOS, where the variable simply doesn't exist.
export MSYS_NO_PATHCONV=1

set -euo pipefail

echo "Starting load generator pod against hpa-demo-service..."

kubectl run load-generator \
  --image=busybox \
  --restart=Never \
  -- /bin/sh -c "while true; do wget -q -O- http://hpa-demo-service; done"

echo "Load generator pod 'load-generator' started."
echo "Watch scaling with: kubectl get hpa hpa-demo -w"
echo "Stop the load with:  kubectl delete pod load-generator"