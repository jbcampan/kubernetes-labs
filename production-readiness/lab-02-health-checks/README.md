# Lab 02 — Health Checks (startup / liveness / readiness probes)

## Objective

Make an application resilient by configuring the three Kubernetes probe
types — `startupProbe`, `livenessProbe`, `readinessProbe` — and understand
precisely what each one is responsible for: recovering from a stuck
process, temporarily removing a pod from traffic, and protecting a slow
startup phase.

## Structure

```
lab-02-health-checks/
├── README.md
├── app/
│   ├── app.py              # Flask app with controllable /healthz and /ready
│   ├── requirements.txt
│   └── Dockerfile
├── manifests/
│   ├── deployment.yaml     # 2 replicas, all three probes configured
│   └── service.yaml
└── scripts/
    ├── build-and-load.sh          # build the local image and load it into kind
    ├── demo-liveness-failure.sh   # trigger a simulated deadlock
    └── demo-readiness-failure.sh  # trigger a simulated temporary overload
```

## What you create

- A small Flask application exposing:
  - `/healthz` — used by `startupProbe` and `livenessProbe`
  - `/ready` — used by `readinessProbe`
  - `/simulate/blocked` — makes `/healthz` fail forever (deadlock simulation)
  - `/simulate/unready` — makes `/ready` fail for 30s then recover on its own
  - `/reset` — clears any simulated failure
- A custom Docker image built locally and loaded into `kind` (no registry)
- A `Deployment` (2 replicas) configuring all three probe types together
- A `ClusterIP` `Service` in front of it
- Two demo scripts, one per failure scenario

## What you learn

| Concept | Explanation |
|---|---|
| `startupProbe` | Protects a slow-starting app: while it hasn't succeeded, `livenessProbe` and `readinessProbe` are not evaluated at all. Prevents a slow app from being killed before it even had a chance to start. |
| `livenessProbe` | If it fails `failureThreshold` times in a row, the **container is restarted**. Meant for "the process is stuck and will never recover on its own" situations. |
| `readinessProbe` | If it fails, the Pod is **removed from the Service Endpoints** — no traffic sent to it — but the container keeps running untouched. Meant for temporary, self-recovering unavailability. |
| `initialDelaySeconds` / `periodSeconds` / `failureThreshold` / `timeoutSeconds` | Control when a probe starts checking, how often, how many consecutive failures trigger an action, and how long to wait for a response. |
| Badly tuned `livenessProbe` | Too aggressive settings (short `periodSeconds`, low `failureThreshold`) on an app that's just briefly slow (GC pause, cold cache) causes it to be killed mid-recovery — repeatedly — producing a `CrashLoopBackOff` that has nothing to do with an actual bug. |
| Probe types | `httpGet` (HTTP status code), `tcpSocket` (port open/closed), `exec` (command exit code) — this lab uses `httpGet` for full control over the response. |
| `kubectl get endpoints` | Shows in real time which Pods are currently considered "ready" and receiving traffic from the Service — this is exactly what `readinessProbe` controls. |

## Estimated cost

0€ — 100% local via `kind`, no AWS resource involved.

## Prerequisites

```bash
# Always start a lab with a fresh, isolated cluster
kind create cluster --name k8s-labs

# Docker must be running locally to build the demo image
docker version
```

## Steps

```bash
# 1. Build the demo image and load it into the kind cluster
#    (no registry involved, the image only exists inside the cluster nodes)
chmod +x scripts/*.sh
./scripts/build-and-load.sh

# 2. Deploy the app and its Service
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml

# 3. Watch the startupProbe do its job: pods should stay "0/1 Running"
#    for ~20s (STARTUP_DELAY_SECONDS) before turning "1/1 Ready"
kubectl get pods -l app=health-checks-demo -w
# Ctrl+C once both pods show 1/1 READY

# 4. Confirm both pods are registered as Service endpoints
kubectl get endpoints health-checks-demo

# 5. Demo scenario A — liveness failure (simulated deadlock -> restart)
./scripts/demo-liveness-failure.sh
# In another terminal, follow along:
kubectl get pods -l app=health-checks-demo -w
# Wait until RESTARTS goes from 0 to 1 on the targeted pod (~30-40s: 3 failed
# checks * periodSeconds=10s), then inspect the probe failure events:
kubectl describe pod <pod-name>

# 6. Demo scenario B — readiness failure (simulated overload -> no restart)
./scripts/demo-readiness-failure.sh
# In another terminal, follow along:
kubectl get endpoints health-checks-demo -w
# The targeted pod's IP disappears from the endpoint list for ~30s, then
# reappears on its own. Confirm RESTARTS did NOT change:
kubectl get pods -l app=health-checks-demo

# 7. Clean up state if you want to re-run a demo without redeploying
#    (port-forward to the targeted pod, then):
curl -s -X POST http://localhost:8080/reset

# 8. Always end a lab by deleting its dedicated cluster
kind delete cluster --name k8s-labs
```

## Key takeaways

- Why does a `livenessProbe` alone (without `startupProbe`) risk killing a
  slow-starting app before it ever gets the chance to become healthy?
- Why is a failing `readinessProbe` a "softer" failure than a failing
  `livenessProbe` — what real production incident does each one protect
  against?
- With 2 replicas, what happens to traffic sent to the Service while one
  pod is temporarily "not ready"? What would happen with only 1 replica?
- Why does `startupProbe` share the same endpoint (`/healthz`) as
  `livenessProbe` here instead of having its own? Is that always a good
  idea?
- What's the risk of setting `failureThreshold: 1` on a `livenessProbe`
  in a real production app subject to occasional network blips?

## Useful links

- Kubernetes docs — [Configure Liveness, Readiness and Startup Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- Kubernetes docs — [Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- `kind` docs — [Loading an Image Into Your Cluster](https://kind.sigs.k8s.io/docs/user/quick-start/#loading-an-image-into-your-cluster)