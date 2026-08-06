# Lab 03 — Debugging

## Objective
Methodically diagnose the most common Kubernetes failures — `ImagePullBackOff`,
`CrashLoopBackOff`, `Pending`, and configuration errors — by triggering them
intentionally, in order to build reusable troubleshooting reflexes (useful
again during the Task Manager's migration to EKS).

## Structure
```
lab-03-debugging/
├── README.md
└── manifests/
    ├── 01-image-pull-backoff.yaml
    ├── 02-crash-loop-backoff.yaml
    ├── 03-pending-resources.yaml
    └── 04-missing-configmap.yaml
```

## What you create
- A `broken-image` Pod that fails to pull its image (nonexistent tag)
- A `crashing-app` Pod whose container exits immediately with a non-zero exit code
- An `oversized-app` Pod whose resource requests exceed the cluster's capacity
- A `misconfigured-app` Pod referencing a ConfigMap that does not exist

## What you learn

| Concept | Explanation |
|---|---|
| Diagnostic methodology | `kubectl get pods` (spot the status) → `kubectl describe pod` (read the `Events`) → `kubectl logs` (if the container ever started) → `kubectl get events --sort-by='.lastTimestamp'` (global timeline view) |
| `ImagePullBackOff` / `ErrImagePull` | A **kubelet**-level error: the image cannot be pulled (invalid tag/name, private registry without credentials, rate limiting) |
| `CrashLoopBackOff` | An **application**-level error: the container starts then exits with a non-zero code, and Kubernetes restarts it with exponential backoff |
| `Pending` | A **scheduler**-level error: no node can host the Pod (insufficient resources, unsatisfied `nodeSelector`/affinity, taints) |
| Missing dependency | A referenced ConfigMap/Secret that doesn't exist: the Pod stays in `CreateContainerConfigError`, with an explicit message in the `Events` |
| Reading `Events` | Always the fastest source of truth — check it before application logs |

## Estimated cost
€0 — everything runs locally with kind, no AWS resources involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
```

## Steps

### 1. ImagePullBackOff scenario

```bash
# Apply the Pod with a nonexistent image tag
kubectl apply -f manifests/01-image-pull-backoff.yaml

# Watch the status evolve: ContainerCreating -> ErrImagePull -> ImagePullBackOff
kubectl get pod broken-image --watch
# (Ctrl+C once ImagePullBackOff is reached)

# Diagnosis: the Events give the exact error message from the registry
kubectl describe pod broken-image
# Look at the "Events" section at the bottom: "Failed to pull image ... manifest unknown"

# kubectl logs gives nothing here: the container never started
kubectl logs broken-image
# Error from server (BadRequest): container "app" in pod "broken-image" is waiting to start

# Fix: correct the tag in the manifest (e.g. nginx:1.27), then reapply
kubectl delete -f manifests/01-image-pull-backoff.yaml
```

### 2. CrashLoopBackOff scenario

```bash
kubectl apply -f manifests/02-crash-loop-backoff.yaml

# The RESTARTS counter increases with each attempt, with exponential backoff
kubectl get pod crashing-app --watch
# (Ctrl+C once CrashLoopBackOff is reached)

# Diagnosis: container logs, including the previous attempt
kubectl logs crashing-app
kubectl logs crashing-app --previous
# "Simulating a fatal startup error"

# Additional diagnosis: Events + exact exit code
kubectl describe pod crashing-app
# Look for "Last State: Terminated / Exit Code: 1"

# Fix: in a real app, fix the bug or the startup command
kubectl delete -f manifests/02-crash-loop-backoff.yaml
```

### 3. Pending scenario (insufficient resources)

```bash
kubectl apply -f manifests/03-pending-resources.yaml

# The Pod stays stuck in Pending, never assigned to a node
kubectl get pod oversized-app

# Diagnosis: the scheduler's Events explain why
kubectl describe pod oversized-app
# "0/1 nodes are available: 1 Insufficient cpu, 1 Insufficient memory"

# Additional diagnosis: compare the request to the node's actual capacity
kubectl describe node k8s-labs-control-plane | grep -A 5 "Allocatable"

# Fix: lower requests/limits to realistic values
kubectl delete -f manifests/03-pending-resources.yaml
```

### 4. Configuration error scenario (missing ConfigMap)

```bash
kubectl apply -f manifests/04-missing-configmap.yaml

# Status stuck in CreateContainerConfigError
kubectl get pod misconfigured-app

# Diagnosis: the Events name the missing resource precisely
kubectl describe pod misconfigured-app
# "configmap \"app-config-that-does-not-exist\" not found"

kubectl delete -f manifests/04-missing-configmap.yaml
```

### 5. Global view: sort all namespace events

```bash
# Useful when several Pods are failing at the same time
kubectl get events --sort-by='.lastTimestamp'
```

### 6. Cluster cleanup

```bash
kind delete cluster --name k8s-labs
```

## Understanding checkpoints
- Why is `kubectl logs` useless for diagnosing an `ImagePullBackOff`, but
  essential for a `CrashLoopBackOff`?
- Why does a `Pending` Pod **never** have container-level Events (Events come
  from the scheduler, not the kubelet, since the Pod was never assigned to a
  node)?
- What's the difference between `ErrImagePull` and `ImagePullBackOff` (the
  latter is the backoff state reached after several failures of the former)?
- Why is `--previous` on `kubectl logs` essential in a CrashLoopBackOff (the
  container has already been restarted, so its current logs may be empty)?

## Useful links
- [Debug Pods — official Kubernetes documentation](https://kubernetes.io/docs/tasks/debug/debug-application/debug-pods/)
- [Debug Running Pods](https://kubernetes.io/docs/tasks/debug/debug-application/debug-running-pod/)
- [Determine the Reason for Pod Failure](https://kubernetes.io/docs/tasks/debug/debug-application/determine-reason-pod-failure/)