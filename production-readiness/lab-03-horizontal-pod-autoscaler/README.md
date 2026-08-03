# Lab 03 — Horizontal Pod Autoscaler

## Objective

Automatically scale the number of replicas of a Deployment based on real CPU load, using Metrics Server and HPA — moving from manual scaling (Phase 1) to metrics-driven scaling.

## Structure

```
production-readiness/lab-03-horizontal-pod-autoscaler/
├── README.md
├── manifests/
│   ├── metrics-server-patch.json   # JSON patch to adapt Metrics Server to kind
│   ├── deployment.yaml             # Deployment with CPU requests/limits (HPA prerequisite)
│   ├── service.yaml                # ClusterIP Service exposing the Deployment
│   └── hpa.yaml                    # HorizontalPodAutoscaler targeting the Deployment
└── scripts/
    └── load-test.sh                # Busybox pod looping requests to trigger scale-up
```

## What you create

- Metrics Server installation (official manifest + `--kubelet-insecure-tls` patch to work on kind)
- An `hpa-demo` Deployment with CPU `requests`/`limits` defined
- A `Service` (ClusterIP) exposing this Deployment
- An `hpa.yaml` manifest targeting the Deployment (`targetCPUUtilizationPercentage`)
- A `scripts/load-test.sh` script that launches a load pod (HTTP request loop) to trigger the scale-up

## What you learn

| Concept | Explanation |
|---|---|
| Mandatory CPU requests | The HPA computes a CPU usage percentage relative to the `request` declared on the container. Without a `request`, it has no baseline to calculate against and refuses to scale. |
| Metrics Server on kind | kind does not expose kubelet certificates signed by a trusted CA by default. Metrics Server must be patched with `--kubelet-insecure-tls` to accept this connection locally. |
| `kubectl top` | Command that queries Metrics Server directly (not the standard API server) to display real CPU/RAM usage of nodes and pods. |
| HPA control loop | The HPA controller queries Metrics Server every 15s by default, computes `actual usage / target usage`, and adjusts replicas — with a stabilization window to avoid flapping. |
| Asymmetric scale-up / scale-down | Kubernetes scales up quickly (reactive to load) but scales down more slowly (default 5-minute stabilization window) to avoid oscillation. |
| Git Bash path conversion (Windows) | MSYS (used by Git Bash) rewrites any argument starting with `/` into a Windows path before it reaches `kubectl`, breaking `/bin/sh` inside containers. Setting `MSYS_NO_PATHCONV=1` disables this rewriting. |

## Estimated cost

€0 — entirely local on kind, no AWS resources.

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

This lab is independent: no component from a previous lab is required.

## Steps

### 1. Install Metrics Server

```bash
# Official manifest from the metrics-server project
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

```bash
# kind uses self-signed certificates on kubelets: Metrics Server refuses
# by default to trust them. We patch the Deployment to add
# --kubelet-insecure-tls (acceptable only in local/dev environments).
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p "$(cat manifests/metrics-server-patch.json)"
```

```bash
# Wait for Metrics Server to be ready before continuing
kubectl rollout status deployment/metrics-server -n kube-system --timeout=120s
```

```bash
# Verify that metrics are flowing (can take 30-60s after the rollout)
kubectl top nodes
```

### 2. Deploy the target application

```bash
kubectl apply -f manifests/deployment.yaml
kubectl apply -f manifests/service.yaml
```

```bash
kubectl rollout status deployment/hpa-demo --timeout=60s
```

```bash
# Check that pods are already consuming a bit of CPU at idle
kubectl top pods -l app=hpa-demo
```

### 3. Create the HPA

```bash
kubectl apply -f manifests/hpa.yaml
```

```bash
# Initial state: TARGETS should show a percentage (not <unknown>)
# once Metrics Server has had time to collect data
kubectl get hpa hpa-demo
```

### 4. Trigger the scale-up

```bash
# Launches a busybox pod that hammers the service in an infinite loop
chmod +x scripts/load-test.sh
./scripts/load-test.sh
```

```bash
# In a second terminal: watch the scale-up live
# (CPU% in TARGETS should rise, then REPLICAS increase after ~1-2 min)
kubectl get hpa hpa-demo -w
```

### 5. Observe the scale-down

```bash
# Stop the load: delete the load-generator pod
kubectl delete pod load-generator
```

```bash
# Keep watching: scale-down takes longer than scale-up
# (default stabilization window ~5 min) — this is expected and intentional
kubectl get hpa hpa-demo -w
```

### 6. Cleanup

```bash
kind delete cluster --name k8s-labs
```

## Key takeaways

| Concept | Explanation |
|---|---|
| Why the HPA shows `<unknown>` at first | Metrics Server hasn't collected data yet (first cycle after deployment). Waiting ~1 minute is usually enough. |
| Why `hpa-example` and not plain `nginx` | `nginx` at idle barely consumes CPU even under light requests: impossible to observe a realistic scale-up without a dedicated stress tool. The `hpa-example` image is specifically designed by the Kubernetes project for this kind of demo (it computes square roots in a loop on each request, generating controlled CPU load). |
| Why `--kubelet-insecure-tls` is only acceptable here | On production EKS, kubelet certificates are signed by the cluster's CA: this flag should never be used outside a lab environment. |
| Difference between `autoscaling/v1` and `autoscaling/v2` | `v1` only supports `targetCPUUtilizationPercentage`. `v2` (used here) allows multiple metrics (CPU, memory, custom metrics) via a `metrics` list. |
| Why `load-test.sh` sets `MSYS_NO_PATHCONV=1` | Prevents Git Bash on Windows from mangling the `/bin/sh` argument passed to `kubectl run`. Harmless no-op on Linux/macOS. |

## Useful links

- [Official HPA documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [HPA walkthrough with `php-apache`/`hpa-example`](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
- [Metrics Server — GitHub](https://github.com/kubernetes-sigs/metrics-server)
- [Metrics Server on kind — known certificate issue](https://github.com/kubernetes-sigs/metrics-server#readme)