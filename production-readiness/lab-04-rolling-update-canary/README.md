# Lab 4 — Rolling Update, Recreate & Canary Release

## Objective

Compare the two native Kubernetes deployment strategies (`RollingUpdate`
and `Recreate`) by observing their real impact on service availability,
then build a hand-rolled Canary release demo using shared labels and a
replica ratio — no service mesh involved.

## Structure

```
lab-04-rolling-update-canary/
├── README.md
├── manifests/
│   ├── 01-rolling-update-deployment.yaml   # Deployment, strategy: RollingUpdate
│   ├── 01-rolling-update-service.yaml      # Service for the RollingUpdate demo
│   ├── 02-recreate-deployment.yaml         # Deployment, strategy: Recreate
│   ├── 02-recreate-service.yaml            # Service for the Recreate demo
│   ├── 03-canary-stable-deployment.yaml    # "stable" Deployment (9 replicas)
│   ├── 03-canary-canary-deployment.yaml    # "canary" Deployment (1 replica)
│   └── 03-canary-service.yaml              # Shared Service (selector app only)
└── scripts/
    └── canary-traffic-test.sh              # Tally STABLE vs CANARY over N requests
```

## What you create

- A `rolling-demo` Deployment (4 replicas) using the `RollingUpdate`
  strategy with `maxSurge: 1` / `maxUnavailable: 0`, updated live
- A `recreate-demo` Deployment (4 replicas) using the `Recreate` strategy,
  otherwise identical, to compare the resulting service outage
- Two Deployments sharing the label `app: canary-demo`:
  `canary-demo-stable` (9 replicas, `track: stable`) and
  `canary-demo-canary` (1 replica, `track: canary`)
- A single `canary-demo-svc` Service whose selector only targets
  `app: canary-demo`, so it routes to both tracks at once
- A bash load-test script that tallies STABLE vs CANARY responses to
  empirically verify the ~90/10 split

## What you learn

| Concept | Explanation |
|---|---|
| `strategy.type: RollingUpdate` | Replaces pods progressively; the service stays available during the update if `maxUnavailable` is tuned correctly |
| `strategy.type: Recreate` | Kills all existing pods before creating new ones; guaranteed downtime, but avoids any cohabitation of two versions (useful when the data schema changes in an incompatible way) |
| `maxSurge` / `maxUnavailable` | `maxSurge` allows extra pods temporarily, `maxUnavailable` allows fewer pods temporarily — their combination defines the speed/availability trade-off of the rollout |
| `readinessProbe` during a rollout | Without a reliable readiness probe, `maxUnavailable: 0` protects nothing: a pod that is "Running" but not yet ready can still receive traffic |
| Limits of native rollouts | No fine-grained traffic percentage control, no automatic rollback based on metrics, no progressive analysis — that's the role of a service mesh (Istio, Linkerd) or a dedicated controller (Argo Rollouts, Flagger) |
| "Poor man's" Canary via labels + replica ratio | By making a single Service match two separate Deployments, kube-proxy distributes traffic proportionally to each track's pod count — a rough but free approximation of a real canary |
| `kubectl rollout pause` / `resume` | Lets you freeze an ongoing rollout (for example after deploying just 1 canary pod) to observe behavior before deciding whether to continue or cancel |
| `kubectl rollout undo` | Reverts a Deployment to its previous revision if a problem is detected after a rollout |

## Estimated cost

€0 — local kind cluster, `hashicorp/http-echo` image (lightweight, public,
no paid external dependency).

## Prerequisites

```bash
kind create cluster --name k8s-labs
kubectl cluster-info --context kind-k8s-labs
```

This lab is self-contained: no prerequisite from a previous lab is
required (no Ingress Controller, no Metrics Server).

## Steps

### Part 1 — RollingUpdate

```bash
# 1. Deploy the app in version 1
kubectl apply -f manifests/01-rolling-update-deployment.yaml
kubectl apply -f manifests/01-rolling-update-service.yaml
kubectl rollout status deployment/rolling-demo

# 2. In a first terminal: watch the pods live
kubectl get pods -l app=rolling-demo -w

# 3. In a second terminal: expose the service and hit it continuously
kubectl port-forward svc/rolling-demo-svc 8080:80 &
while true; do curl -s http://localhost:8080; echo " - $(date +%T)"; sleep 0.3; done

# 4. In a third terminal: trigger the update to version-2
kubectl patch deployment rolling-demo -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"http-echo","args":["-text=version-2","-listen=:5678"]}]}}}}'

kubectl rollout status deployment/rolling-demo
kubectl rollout history deployment/rolling-demo

# 5. Expected outcome: the curl loop in terminal 3 sees no errors, the
# response gradually shifts from "version-1" to "version-2" pod by pod,
# never more than 5 pods nor fewer than 4 running at the same time
# (maxSurge=1, maxUnavailable=0)

# 6. (optional) Roll back to the previous revision
kubectl rollout undo deployment/rolling-demo

# Stop the curl loop and the port-forward before continuing
kill %1 2>/dev/null || true
```

### Part 2 — Recreate

```bash
# 1. Deploy the app in version 1
kubectl apply -f manifests/02-recreate-deployment.yaml
kubectl apply -f manifests/02-recreate-service.yaml
kubectl rollout status deployment/recreate-demo

# 2. Expose the service and hit it continuously, logging failures
kubectl port-forward svc/recreate-demo-svc 8081:80 &
while true; do
  code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081)
  echo "$(date +%T) - HTTP ${code}"
  sleep 0.2
done &

# 3. Trigger the update to version-2
kubectl patch deployment recreate-demo -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"http-echo","args":["-text=version-2","-listen=:5678"]}]}}}}'

kubectl rollout status deployment/recreate-demo

# 4. Expected outcome: unlike Part 1, the curl stream shows error lines
# (code 000 / connection refused) during the window where all old pods
# have been terminated and the new ones aren't ready yet — this is the
# service outage characteristic of Recreate

# Stop the loops and the port-forward
kill %1 %2 2>/dev/null || true
```

### Part 3 — Manual Canary release

```bash
# 1. Deploy stable (9 replicas) and canary (1 replica) + the shared Service
kubectl apply -f manifests/03-canary-stable-deployment.yaml
kubectl apply -f manifests/03-canary-canary-deployment.yaml
kubectl apply -f manifests/03-canary-service.yaml

kubectl rollout status deployment/canary-demo-stable
kubectl rollout status deployment/canary-demo-canary

# 2. Verify the Service sees all 10 pods from both tracks
kubectl get pods -l app=canary-demo --show-labels
kubectl get endpoints canary-demo-svc

# 3. Expose the service and run the load-test script
kubectl port-forward svc/canary-demo-svc 8082:80 &
chmod +x scripts/canary-traffic-test.sh
./scripts/canary-traffic-test.sh http://localhost:8082 50

# Expected result: ~90% STABLE / ~10% CANARY, proportional to the
# 9 stable replicas / 1 canary replica ratio

# 4. Demonstrate rollout pause/resume on the stable track
kubectl rollout pause deployment/canary-demo-stable

kubectl patch deployment canary-demo-stable -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"http-echo","args":["-text=response from STABLE v2","-listen=:5678"]}]}}}}'

# The Deployment is modified but NO pod is recreated while it's paused
kubectl get pods -l app=canary-demo,track=stable
kubectl rollout status deployment/canary-demo-stable  # stays stuck

# Once satisfied with the canary version under real conditions, resume
# the stable track's rollout
kubectl rollout resume deployment/canary-demo-stable
kubectl rollout status deployment/canary-demo-stable

# Stop the port-forward
kill %1 2>/dev/null || true
```

### Cleanup

```bash
kind delete cluster --name k8s-labs
```

## Understanding checkpoints

- **Why isn't `maxUnavailable: 0` alone enough?** Without a correct
  `readinessProbe`, Kubernetes considers a pod "available" as soon as it's
  `Running`, even if it's not actually ready to serve traffic — the
  zero-downtime guarantee depends as much on the probe as on the strategy.
- **Why is the Canary here called "poor man's"?** The traffic ratio
  (~10%) comes purely from the replica ratio and kube-proxy's round-robin
  distribution — there is no strict percentage guarantee, no segmentation
  by user/cookie, and no automatic rollback based on error metrics. A real
  canary setup (Argo Rollouts, Flagger, Istio) drives traffic by an exact
  percentage and can automatically abort on degradation.
- **Why separate `track: stable` and `track: canary` in the Deployments'
  selectors but not in the Service's?** The Deployments need `track` in
  their `selector.matchLabels` so each only manages its own pods
  (otherwise two Deployments would fight over the same pods). The
  Service, on the other hand, must deliberately ignore `track` to cover
  both populations.
- **Recreate isn't inherently "bad"**: it's the right choice when two
  versions of the application cannot coexist (incompatible schema
  migration, exclusive lock on a shared resource) — the availability cost
  is then a conscious trade-off.

## Useful links

- [Kubernetes docs — Deployment strategies (RollingUpdate / Recreate)](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#strategy)
- [Kubernetes docs — Rolling back a Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#rolling-back-a-deployment)
- [Kubernetes docs — Pausing and Resuming a rollout](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#pausing-and-resuming-a-deployment)
- [Kubernetes blog — Canary deployments](https://kubernetes.io/blog/2018/04/30/zero-downtime-deployment-kubernetes-jenkins/)
- [hashicorp/http-echo — GitHub](https://github.com/hashicorp/http-echo)