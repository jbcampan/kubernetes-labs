#!/usr/bin/env bash
set -euo pipefail

# Demonstrates RBAC permission checks with `kubectl auth can-i --as=`.
# Run this script twice during the lab:
#   1. After applying manifests 00-03 (namespaces, SA, Role, RoleBinding)
#   2. After applying manifests 04-05 (ClusterRole, ClusterRoleBinding)
# Compare the two outputs to see the scope widen from one namespace to
# the whole cluster.
#
# Usage: ./scripts/test-permissions.sh

SA="system:serviceaccount:rbac-demo:ci-deployer"

check() {
  local description="$1"
  local verb="$2"
  local resource="$3"
  local namespace="$4"

  local ns_flag=()
  if [[ -n "$namespace" ]]; then
    ns_flag=(-n "$namespace")
  else
    ns_flag=(-A)
  fi

  local result
  result=$(kubectl auth can-i "$verb" "$resource" --as="$SA" "${ns_flag[@]}" 2>/dev/null || true)

  printf "%-65s -> %s\n" "$description" "$result"
}

echo "=== Permissions of ${SA} ==="
echo

echo "--- Inside its own namespace (rbac-demo) ---"
check "get pods in rbac-demo"                 get    pods         rbac-demo
check "list deployments in rbac-demo"         list   deployments  rbac-demo
check "create pods in rbac-demo"              create pods         rbac-demo
check "delete deployments in rbac-demo"       delete deployments  rbac-demo
echo

echo "--- Outside its namespace (rbac-demo-other) ---"
check "get pods in rbac-demo-other"           get    pods         rbac-demo-other
check "list deployments in rbac-demo-other"   list   deployments  rbac-demo-other
echo

echo "--- Cluster-wide (all namespaces, -A) ---"
check "get pods across all namespaces"        get    pods         ""
check "list deployments across all namespaces" list  deployments  ""
echo

echo "Expected BEFORE the ClusterRole/ClusterRoleBinding are applied:"
echo "  - rbac-demo: get pods=yes, list deployments=yes, create pods=no, delete deployments=no"
echo "  - rbac-demo-other: everything=no"
echo "  - cluster-wide: everything=no"
echo
echo "Expected AFTER the ClusterRole/ClusterRoleBinding are applied:"
echo "  - rbac-demo: unchanged"
echo "  - rbac-demo-other: get pods=yes (from ClusterRole), list deployments=no (not covered)"
echo "  - cluster-wide: get pods=yes, list deployments=no"