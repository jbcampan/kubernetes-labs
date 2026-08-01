# Lab 03 — Network Policies

## Objective

Control communication between Pods using `NetworkPolicy` resources, moving
from Kubernetes' default "everything is allowed" flat network model to a
Zero Trust approach where only explicitly declared traffic flows are
permitted: `frontend -> backend` and `backend -> database`.

## Structure

```
lab-03-network-policies/
├── README.md
├── manifests/
│   ├── 00-kind-cluster-config.yaml
│   ├── 01-namespace.yaml
│   ├── 02-frontend-deployment.yaml
│   ├── 03-backend-deployment.yaml
│   ├── 04-database-deployment.yaml
│   ├── 05-frontend-service.yaml
│   ├── 06-backend-service.yaml
│   ├── 07-database-service.yaml
│   ├── 08-default-deny-all.yaml
│   ├── 09-allow-dns-egress.yaml
│   ├── 10-frontend-network-policy.yaml
│   ├── 11-backend-network-policy.yaml
│   └── 12-database-network-policy.yaml
└── scripts/
    └── test-connectivity.sh
```

## What you create

- Three `Deployment` resources (`frontend`, `backend`, `database`) with
  their associated ClusterIP `Service` objects
- A `default-deny-all` policy blocking all ingress/egress traffic in the
  `netpol-demo` namespace
- An `allow-dns-egress` policy, required so DNS resolution keeps working
  after the default-deny is applied
- Three targeted policies: `frontend -> backend`, `backend -> database`
  (ingress + egress), and `database` ingress restricted to `backend` only
- A connectivity test script (`test-connectivity.sh`) to visualize behavior
  before and after the policies are applied

## What you learn

| Concept | Explanation |
|---|---|
| Flat network by default | Without any NetworkPolicy, every Pod can reach every other Pod in the cluster, regardless of namespace |
| CNI and NetworkPolicy | `NetworkPolicy` is a Kubernetes API object, but it's the **CNI** that actually enforces it — kind's default CNI (`kindnet`) does not, so a compatible CNI (Calico, Cilium...) is required |
| `podSelector` | Selects the Pods the policy **applies to** — an empty `{}` selector means "all Pods in the namespace" |
| `policyTypes` | Declares whether the policy governs `Ingress` (incoming traffic), `Egress` (outgoing traffic), or both |
| `ingress` / `egress` | Lists of `from`/`to` rules (podSelector, namespaceSelector, ipBlock) plus allowed `ports` |
| Additivity of NetworkPolicies | All policies matching a given Pod are combined as a **union** — there's no "winning" policy, only accumulating allowances |
| Zero Trust | `default-deny` first, then explicit allow rules, rather than "open by default, block what you don't want" |
| The DNS trap | A `default-deny` on egress also blocks DNS resolution (port 53) unless a dedicated rule is added — otherwise nothing can resolve Service names anymore |

## Estimated cost

**$0.** Fully local (kind + Calico), no cloud resources involved.

⚠️ **Deviation from the standard flow used in other labs**: this lab cannot
rely on `kind create cluster --name k8s-labs` alone, because kind's default
CNI (`kindnet`) does not implement `NetworkPolicy`. The cluster must be
created with `disableDefaultCNI: true`, then Calico must be installed
manually (see Steps below). The cost remains zero — only the bootstrap
procedure changes.

## Prerequisites

- kind and kubectl installed
- No existing `k8s-labs` cluster (`kind get clusters` to check)
- Internet access to download the official Calico manifest

## Steps

```bash
# 1. Create the cluster WITHOUT the default CNI (⚠️ command specific to this
#    lab — do not use "kind create cluster --name k8s-labs" alone here)
kind create cluster --config manifests/00-kind-cluster-config.yaml

# 2. Install Calico (a CNI compatible with NetworkPolicy)
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.28.0/manifests/calico.yaml

# 3. Wait until all Calico pods are Running (can take 1-2 minutes)
kubectl wait --for=condition=Ready pods --all -n calico-system --timeout=180s

# 4. Check that the nodes are Ready (they stay NotReady until a CNI is active)
kubectl get nodes

# 5. Create the namespace and the workloads
kubectl apply -f manifests/01-namespace.yaml
kubectl apply -f manifests/02-frontend-deployment.yaml
kubectl apply -f manifests/03-backend-deployment.yaml
kubectl apply -f manifests/04-database-deployment.yaml
kubectl apply -f manifests/05-frontend-service.yaml
kubectl apply -f manifests/06-backend-service.yaml
kubectl apply -f manifests/07-database-service.yaml

# 6. Wait until all 3 Deployments are ready
kubectl wait --for=condition=Available deployment --all -n netpol-demo --timeout=60s

# 7. BASELINE — test connectivity BEFORE any NetworkPolicy
#    (everything should be ALLOWED: default flat network behavior)
chmod +x scripts/test-connectivity.sh
./scripts/test-connectivity.sh

# 8. Apply the default-deny policy (⚠️ from here on, nothing works anymore,
#    including DNS resolution, until step 9 is done)
kubectl apply -f manifests/08-default-deny-all.yaml

# 9. Re-allow DNS (otherwise the next tests will fail for the wrong reason:
#    name resolution, not the policy itself)
kubectl apply -f manifests/09-allow-dns-egress.yaml

# 10. Apply the targeted Zero Trust policies
kubectl apply -f manifests/10-frontend-network-policy.yaml
kubectl apply -f manifests/11-backend-network-policy.yaml
kubectl apply -f manifests/12-database-network-policy.yaml

# 11. AFTER — re-test connectivity
#     Expected: frontend->backend ALLOWED, backend->database ALLOWED,
#     everything else BLOCKED (frontend->database, backend->frontend,
#     database->backend, database->frontend)
./scripts/test-connectivity.sh

# 12. Inspect the policies applied to a given Pod
kubectl describe networkpolicy -n netpol-demo

# 13. Cleanup — always finish by deleting the cluster
kind delete cluster --name k8s-labs
```

## Key takeaways

- A `NetworkPolicy` without a compatible CNI is created without error but
  has **no effect at all** — always check the CNI first before debugging a
  policy that "doesn't seem to work"
- `podSelector: {}` (empty) means "all Pods in the namespace", not "no
  Pods" — a classic reading trap
- `default-deny-all` also blocks DNS: this is intentional in this lab, to
  really feel the full Zero Trust effect before nuancing it with
  `allow-dns-egress`
- NetworkPolicies are **namespace-scoped** and **additive**: there's no
  policy that "cancels" another one, only allowances that accumulate for a
  given Pod
- `frontend -> backend` requires two separate matching rules: **egress** on
  the frontend side AND **ingress** on the backend side — either one alone
  is not enough

## Useful links

- Official NetworkPolicy documentation: https://kubernetes.io/docs/concepts/services-networking/network-policies/
- kind — NetworkPolicy limitation with kindnet: https://kind.sigs.k8s.io/docs/user/known-issues/#network-policies
- Installing Calico on kind: https://docs.tigera.io/calico/latest/getting-started/kubernetes/kind
- Visual NetworkPolicy editor (handy for visualizing ingress/egress): https://editor.networkpolicy.io/