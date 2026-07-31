# Lab 01 — Ingress Controller (ingress-nginx)

## Objective

Install an Ingress Controller (ingress-nginx) on a kind cluster and
understand its role as a single HTTP/HTTPS entry point, as opposed to one
`NodePort` Service per application (seen in Phase 1). Observe the full
lifecycle of a request: host → kind node → Ingress Controller → Service →
Pod.

## Structure

```
lab-01-ingress-nginx/
├── README.md
├── kind-config.yaml              # kind cluster with extraPortMappings 80/443
└── manifests/
    ├── nginx-deployment.yaml     # test backend (2 nginx replicas)
    ├── nginx-service.yaml        # ClusterIP Service in front of the Deployment
    └── ingress.yaml              # routing rule "/" -> nginx-demo:80
```

Note: the Ingress Controller itself (`ingress-nginx`) is not stored as a
file in this repo. It is installed directly from the project's official
manifest via `kubectl apply -f <URL>` (see Steps) — this is the recommended
usage by the project, which ships one manifest per provider (`kind`,
`cloud`, `aws`, `baremetal`...) rather than having each user copy-paste it.

## What you create

* A kind cluster configured to map host ports 80/443 to the node
  (`kind-config.yaml`)
* The ingress-nginx Ingress Controller, installed in the `ingress-nginx`
  namespace via the official manifest for the `kind` provider
* An `nginx-demo` Deployment (2 replicas) + its `ClusterIP` Service
* A minimal `Ingress` object routing all of `/` to `nginx-demo:80`

## What you learn

| Concept | Explanation |
|---|---|
| Ingress Controller vs Ingress object | The **controller** is a Pod running in the cluster (here NGINX) that does the actual reverse-proxy work. The **Ingress object** is just a declarative rule that this controller reads and applies — without an installed controller, a standalone `Ingress` does strictly nothing. |
| `extraPortMappings` in kind | A kind cluster runs inside Docker containers isolated from the host network. Without explicit port mapping, nothing inside (including the controller) is reachable from `localhost`. |
| Request lifecycle | `curl` on the host → port 80 mapped to the node → `ingress-nginx-controller` Service (internally a NodePort) → controller Pod → internal NGINX reads the `Ingress` object → forwards to the `nginx-demo` Service → application Pod. |
| `ingressClassName` | Specifies which controller should handle this `Ingress` (useful as soon as multiple controllers coexist in a cluster — not our case here, but a good habit from the first lab onward). |
| NodePort (Phase 1) vs Ingress | NodePort exposes a raw port per Service, with no notion of HTTP host/path. Ingress routes at the application layer (host, path, TLS) behind a single entry point — this is what we'll use in practice for any HTTP app. |
| Admission webhook | The first two Jobs that run when the controller starts generate a TLS certificate used to validate `Ingress` objects created afterward — hence a short delay before everything is fully operational. |

## Estimated cost

€0 — local kind cluster, no AWS resources involved.

## Prerequisites

```bash
kind create cluster --name k8s-labs --config kind-config.yaml
kubectl cluster-info --context kind-k8s-labs
```

## Steps

```bash
# 1. Install ingress-nginx via the official manifest for the "kind" provider
#    (nodeSelector/toleration rule + NodePort Service already configured in
#    this manifest to match the "ingress-ready=true" label set by kind-config.yaml)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/kind/deploy.yaml

# 2. Wait for the controller Pod to be ready (the admission webhook
#    certificate Jobs can take up to 1-2 min on first startup)
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# 3. Check that everything is running in the ingress-nginx namespace
kubectl get pods -n ingress-nginx

# 4. Read the controller logs (useful to understand what it does at
#    startup: loading the internal NGINX config, watching Ingress objects...)
kubectl logs -n ingress-nginx -l app.kubernetes.io/component=controller --tail=50

# 5. Deploy the test backend
kubectl apply -f manifests/nginx-deployment.yaml
kubectl apply -f manifests/nginx-service.yaml
kubectl get pods -l app=nginx-demo
kubectl get svc nginx-demo

# 6. Deploy the Ingress rule
kubectl apply -f manifests/ingress.yaml
kubectl get ingress nginx-demo
# Wait for the ADDRESS column to populate (can take a few seconds)

# 7. Test the full end-to-end HTTP request
#    thanks to the port 80 mapping configured in kind-config.yaml, the host's
#    port 80 goes directly to the node -> controller's NodePort Service
curl --resolve demo.localdev.me:80:127.0.0.1 http://demo.localdev.me/

# 8. (Learning comparison) test a route that doesn't exist in the Ingress
curl --resolve demo.localdev.me:80:127.0.0.1 http://demo.localdev.me/nope
# -> still an nginx response because pathType Prefix on "/" catches everything;
#    the real multi-path routing demo comes in lab-02

# 9. Full cleanup
kind delete cluster --name k8s-labs
```

## Troubleshooting notes

* If `curl` fails with `Connection refused`: check that `kind-config.yaml`
  was actually used when creating the cluster (`extraPortMappings` cannot be
  added after the fact, the cluster must be recreated).
* If the controller Pod stays `Pending`: check
  `kubectl get nodes --show-labels` — the `ingress-ready=true` label must be
  present on the control-plane node (set by `kubeadmConfigPatches` in
  `kind-config.yaml`). Without this label, the official kind manifest's
  `nodeSelector` finds no eligible node.
* `kubectl get ingress nginx-demo` may show an empty `ADDRESS` for a few
  seconds: normal, ingress-nginx updates the status once it has finished
  syncing its internal configuration.
* **Worth noting (no impact on this lab)**: the `kubernetes/ingress-nginx`
  repository was archived (read-only) on March 24, 2026, as the project
  entered end-of-maintenance mode. The `controller-v1.15.1` manifest used
  here remains fully functional for local learning purposes. For
  production, the project now recommends moving to a Gateway API
  implementation instead of ingress-nginx — out of scope for this
  curriculum, but worth keeping in mind if you reuse this pattern on a real
  EKS cluster later.

## Useful links

* [Official ingress-nginx installation docs](https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md)
* [Kubernetes — Ingress concept](https://kubernetes.io/docs/concepts/services-networking/ingress/)
* [kind — Ingress guide](https://kind.sigs.k8s.io/docs/user/ingress/)