# Lab 02 — Observability

## Objective
Observe the state of a kind cluster and its workloads using native
Kubernetes tools — Metrics Server (already installed in Phase 5) and the
Kubernetes Dashboard — to lay the groundwork before the future integration
with CloudWatch Container Insights on EKS.

## Structure
```
lab-02-observability/
├── README.md
├── manifests/
│   ├── dashboard-serviceaccount.yaml   # ServiceAccount dedicated to Dashboard access
│   ├── dashboard-rbac.yaml             # Read-only ClusterRole + ClusterRoleBinding
│   └── load-demo.yaml                  # Toy Deployment generating CPU load
├── scripts/
│   └── generate-load.sh                # Scale up/down + live kubectl top
└── .gitignore
```

## What you create
- An installation of the official Kubernetes Dashboard via Helm (the static
  `recommended.yaml` manifest is no longer distributed as of 2026)
- A dedicated `dashboard-viewer` ServiceAccount, bound to a read-only
  `ClusterRole` (no `cluster-admin`, no access to Secrets)
- A `load-demo` Deployment that continuously consumes CPU so there is
  something meaningful to observe
- A `kubectl top nodes` / `kubectl top pods` session before/after a
  scale-up, compared against the same numbers shown in the Dashboard

## What you learn

| Concept | Explanation |
|---|---|
| `metrics-server` | Aggregates CPU/RAM usage from Pods and Nodes; powers `kubectl top` and the Dashboard's graphs. Without it, both tools return an error. |
| Secure access to the Dashboard | `kubectl port-forward` or `kubectl proxy` only — never a `LoadBalancer` or an exposed `NodePort` without strong authentication in front of it. |
| ServiceAccount + Bearer Token | The Dashboard authenticates with a ServiceAccount token (`kubectl create token`), not a username/password login. |
| Read-only RBAC applied concretely | Reuses the previous lab: a ClusterRole that explicitly lists allowed resources and verbs, with no `*` and no `secrets`. |
| Kubernetes Events | The first place to look when diagnosing an issue (`kubectl get events --sort-by=.lastTimestamp` or the Dashboard's Events tab) — before even checking logs. |
| Limits of native tooling | `kubectl top` and the Dashboard only show a live snapshot — no history, no alerting. A full observability stack (Prometheus + Grafana) is out of scope here. |
| Link with EKS | On EKS, CloudWatch Container Insights will play the same role as Metrics Server + Dashboard here, but with built-in history and alerting. |

## Estimated cost
€0 — local kind cluster, no AWS resources involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
```

This lab depends on **Metrics Server**, installed in Phase 5 Lab 03
(`production-readiness/lab-03-horizontal-pod-autoscaler`). Since every lab
is independent at the cluster level, it is reinstalled here:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# kind uses self-signed kubelet certificates: without this patch,
# metrics-server stays in CrashLoopBackOff (TLS error).
kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

kubectl rollout status deployment/metrics-server -n kube-system --timeout=90s
```

`helm` must be installed on your machine (already used in Phase 4).

## Steps

```bash
# 1. Install the Kubernetes Dashboard via Helm
#    (the official repo moved to kubernetes-retired.github.io/dashboard
#    after the GitHub repo was archived in early 2026; recommended.yaml
#    no longer exists)
helm repo add kubernetes-dashboard https://kubernetes-retired.github.io/dashboard/
helm repo update

helm install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
  --create-namespace \
  --namespace kubernetes-dashboard

kubectl rollout status deployment/kubernetes-dashboard-web -n kubernetes-dashboard --timeout=90s

# 2. Create the dedicated ServiceAccount and read-only RBAC
kubectl apply -f manifests/dashboard-serviceaccount.yaml
kubectl apply -f manifests/dashboard-rbac.yaml

# 3. Generate an access token (valid for 1 hour by default)
kubectl -n kubernetes-dashboard create token dashboard-viewer > dashboard-token.txt
cat dashboard-token.txt

# 4. Expose the Dashboard locally (never expose it publicly)
#    Target the Kong gateway service, not "kubernetes-dashboard" directly
#    (change introduced in Dashboard v7).
kubectl -n kubernetes-dashboard port-forward svc/kubernetes-dashboard-kong-proxy 8443:443
# Open https://localhost:8443 in the browser, accept the self-signed
# certificate, paste the content of dashboard-token.txt

# 5. Generate load and compare CLI vs Dashboard
chmod +x scripts/generate-load.sh
./scripts/generate-load.sh
# While the script runs, open Workloads > load-demo in the Dashboard
# and watch the live CPU graphs

# 6. Explore cluster Events
kubectl get events --sort-by=.lastTimestamp --all-namespaces
# Compare with the "Events" tab of a Pod in the Dashboard

# 7. Cleanup
kubectl delete -f manifests/load-demo.yaml
helm uninstall kubernetes-dashboard -n kubernetes-dashboard
kubectl delete namespace kubernetes-dashboard
kind delete cluster --name k8s-labs
```

## Key takeaways
- **Why not `cluster-admin`?** The Dashboard's historical official tutorial
  used an `admin-user` bound to `cluster-admin` to simplify the demo. That
  is exactly the anti-pattern this lab avoids: a viewer account should never
  be able to delete a production Deployment.
- **`kubectl top` vs Dashboard**: both read from the same `metrics.k8s.io`
  API, backed by `metrics-server`. The Dashboard simply adds a graphical
  layer on top of the same numbers.
- **Instability of the Dashboard ecosystem**: this lab required adapting
  the historical documentation (archived repo, mandatory Helm install, Kong
  service instead of the direct Dashboard service). The Kubernetes SIG UI
  project is now pushing **Headlamp** as a successor — worth keeping in
  mind if this lab is redone months later and the commands above no longer
  work as-is.
- **On EKS**: CloudWatch Container Insights will do the same job (metrics
  collection + visualization), but relying on a CloudWatch agent instead of
  `metrics-server`, with added retention and alerting.

## Useful links
- Dashboard Helm repository: https://kubernetes-retired.github.io/dashboard/
- Official Metrics Server documentation:
  https://github.com/kubernetes-sigs/metrics-server
- Kubernetes RBAC guide:
  https://kubernetes.io/docs/reference/access-authn-authz/rbac/
- CloudWatch Container Insights (for the follow-up on EKS):
  https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights.html