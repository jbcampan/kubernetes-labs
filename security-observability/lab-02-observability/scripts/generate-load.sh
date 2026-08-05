#!/usr/bin/env bash
# Applies the load-demo Deployment, watches kubectl top before/after a scale-up,
# then scales back down. Meant to be run while you also have the Dashboard
# open in a browser tab (Workloads > load-demo) to compare CLI vs UI.
set -euo pipefail

NAMESPACE="default"
DEPLOYMENT="load-demo"

echo "==> Applying load-demo Deployment (2 replicas)"
kubectl apply -f "$(dirname "$0")/../manifests/load-demo.yaml"

echo "==> Waiting for pods to be ready"
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=60s

echo "==> Baseline usage (2 replicas)"
kubectl top pods -n ${NAMESPACE} -l app=${DEPLOYMENT} || echo "metrics-server not ready yet, retry in a few seconds"

echo "==> Scaling up to 6 replicas to see the aggregate CPU usage increase"
kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=6
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=60s
sleep 5
kubectl top pods -n ${NAMESPACE} -l app=${DEPLOYMENT}
kubectl top nodes

echo "==> Scaling back down to 2 replicas"
kubectl scale deployment/${DEPLOYMENT} -n ${NAMESPACE} --replicas=2
kubectl rollout status deployment/${DEPLOYMENT} -n ${NAMESPACE} --timeout=60s

echo "==> Done. Compare these numbers with the Dashboard's Workloads view."