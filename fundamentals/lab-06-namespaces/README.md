# Lab 06 — Namespaces

## Objective
Organize and isolate cluster resources using Namespaces, and prepare the
environment-separation pattern (dev/staging/prod) that will later be reused
on Amazon EKS.

## Structure
```
lab-06-namespaces/
├── README.md
└── manifests/
    ├── 01-namespaces.yaml           # dev + staging Namespace objects
    ├── 02-resourcequota-dev.yaml    # ResourceQuota for "dev"
    ├── 02-resourcequota-staging.yaml# ResourceQuota for "staging"
    ├── 03-deployment-dev.yaml       # "web" Deployment in "dev"
    ├── 03-service-dev.yaml          # "web" Service in "dev"
    ├── 04-deployment-staging.yaml   # "web" Deployment in "staging"
    └── 04-service-staging.yaml      # "web" Service in "staging"
```

## What you create
- Two Namespaces: `dev` and `staging`, each labeled `env: <name>`
- One `ResourceQuota` per Namespace (tighter for `dev`, looser for `staging`)
- The same `web` Deployment (nginx, 2 replicas) and `web` Service (ClusterIP)
  deployed independently in both Namespaces, with identical names but no
  collision

## What you learn

| Concept | Explanation |
|---|---|
| `kubectl create namespace` | Creates an isolated logical partition of the cluster (same nodes, same API server, separate object namespace) |
| `kubectl config set-context --current --namespace=` | Changes the *default* namespace for your current kubectl context, so you stop typing `-n <namespace>` on every command |
| Isolation by default | Resource names only need to be unique **within** a namespace — `web` can exist in both `dev` and `staging` at once |
| No network isolation by default | Pods in `dev` can reach Pods in `staging` over the network unless a `NetworkPolicy` says otherwise (Phase 3 teaser) |
| Inter-namespace DNS | Any Service is reachable from another namespace at `<service>.<namespace>.svc.cluster.local` (here: `web.dev.svc.cluster.local`, `web.staging.svc.cluster.local`) |
| `ResourceQuota` | Caps the total resources (pod count, CPU/memory requests and limits) that can be consumed inside one namespace — first taste of cluster governance |
| `LimitRange` (mentioned, not used here) | Would set *default* requests/limits per container so you don't have to declare them manually every time; skipped in this lab to keep the ResourceQuota enforcement visible |
| Naming convention | Namespace = environment name (`dev`, `staging`); `env` label duplicates it for label-selector-based tooling (RBAC, NetworkPolicy, dashboards) |

## Estimated cost
0€ — 100% local via kind, no AWS resource involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
kubectl cluster-info --context kind-k8s-labs
```

## Steps

```bash
# 1. Create both namespaces
kubectl apply -f manifests/01-namespaces.yaml

# 2. Confirm they exist and check the "env" label
kubectl get namespaces --show-labels

# 3. Apply the ResourceQuotas (one per namespace)
kubectl apply -f manifests/02-resourcequota-dev.yaml
kubectl apply -f manifests/02-resourcequota-staging.yaml

# 4. Inspect the quota: "Used" starts at 0, "Hard" shows the caps
kubectl describe resourcequota dev-quota -n dev
kubectl describe resourcequota staging-quota -n staging

# 5. Deploy the "web" app in dev
kubectl apply -f manifests/03-deployment-dev.yaml
kubectl apply -f manifests/03-service-dev.yaml

# 6. Deploy the exact same app (same names) in staging — no conflict
kubectl apply -f manifests/04-deployment-staging.yaml
kubectl apply -f manifests/04-service-staging.yaml

# 7. Compare both namespaces side by side
kubectl get pods -n dev -o wide
kubectl get pods -n staging -o wide

# 8. Quota now reflects real consumption (2 pods, 100m/128Mi requests each)
kubectl describe resourcequota dev-quota -n dev

# 9. Switch your default namespace to "dev" to stop typing -n dev
kubectl config set-context --current --namespace=dev
kubectl get pods
# ... reset back to default when done exploring
kubectl config set-context --current --namespace=default

# 10. Prove inter-namespace DNS resolution: call staging's Service from dev
kubectl run tmp-curl --image=curlimages/curl:8.10.1 -n dev \
  --restart=Never --rm -it -- curl -s web.staging.svc.cluster.local

# 11. Hit the ResourceQuota limit on purpose: scale dev past its pod cap
kubectl scale deployment web -n dev --replicas=10
kubectl get pods -n dev
# some Pods stay unscheduled/absent — inspect why:
kubectl describe resourcequota dev-quota -n dev
kubectl get events -n dev --sort-by=.lastTimestamp | tail -n 10

# 12. Scale back down before cleanup
kubectl scale deployment web -n dev --replicas=2

# 13. Cleanup
kind delete cluster --name k8s-labs
```

## Key takeaways
- **Why does `kubectl scale --replicas=10` not create 10 Pods in `dev`?**
  `dev-quota` caps `pods` at `5` and `requests.cpu` at `500m`. The
  ReplicaSet controller keeps trying, but the API server refuses to admit
  Pods beyond the quota — check `kubectl get events` for
  `forbidden: exceeded quota` messages.
- **Why do the Deployments explicitly set `resources.requests` and
  `resources.limits`, unlike earlier labs?** Because both namespaces have a
  `ResourceQuota` constraining `requests.cpu/memory` and
  `limits.cpu/memory`. Once a quota tracks those, every container in that
  namespace must declare them, or its Pod is rejected outright — this is a
  Kubernetes admission rule, not a convention.
- **Why can `web` exist in both `dev` and `staging` without conflict?**
  A Namespace is a partition of the object name space: the *cluster-wide*
  unique key for a Deployment is actually `(namespace, name)`, not `name`
  alone.
- **Is `dev` isolated from `staging` on the network?** No — by default all
  Pods can reach all other Pods across namespaces. `dev` can `curl`
  `staging`'s Service and vice versa. Restricting that requires a
  `NetworkPolicy`, covered in Phase 3.
- **What would `LimitRange` add on top of `ResourceQuota`?** `ResourceQuota`
  caps the *total* consumption of a namespace; `LimitRange` sets *default*
  and *min/max* values per individual container, so teams don't have to
  remember to set `resources` on every manifest. Not used here so the
  quota's enforcement stays visible for teaching purposes.

## Useful links
- Namespaces: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/
- Resource Quotas: https://kubernetes.io/docs/concepts/policy/resource-quotas/
- Limit Ranges: https://kubernetes.io/docs/concepts/policy/limit-range/
- DNS for Services and Pods: https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/