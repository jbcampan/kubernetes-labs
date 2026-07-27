# Lab 01 — First Pod

## Objective

Launch your very first Kubernetes Pod, first imperatively (`kubectl run`),
then declaratively (`pod.yaml`), and explore its lifecycle with `kubectl`
— before understanding why a bare Pod is almost never used directly in
production.

## Structure

```
lab-01-first-pod/
├── README.md                # this file
├── kind-config.yaml          # local kind cluster config (1 node)
└── manifests/
    └── pod.yaml               # declarative definition of the nginx Pod
```

## What you create

- A local single-node kind cluster (`kind-config.yaml`)
- An nginx Pod launched imperatively with `kubectl run` (throwaway, for comparison)
- An nginx Pod defined declaratively (`manifests/pod.yaml`)

## What you learn

| Concept | Explanation |
|---|---|
| kind cluster | Kubernetes-in-Docker: runs a full Kubernetes cluster inside one or more Docker containers, no VM or cloud needed |
| `kubectl cluster-info` / `get nodes` | Verify the cluster is up and the control plane is responding |
| Imperative mode | `kubectl run` creates a resource directly with a single command, no file — handy for quick tests, poorly suited for versioning |
| Declarative mode | `kubectl apply -f pod.yaml` describes the desired state in a file; a versionable source of truth |
| Pod lifecycle | `Pending` (scheduling) → `ContainerCreating` (image pull, container creation) → `Running` |
| `kubectl describe pod` | Shows events (scheduling, pull, errors) — first reflex when debugging |
| `kubectl logs` | Shows the container's stdout/stderr output |
| `kubectl exec -it` | Opens an interactive shell inside the Pod's container |
| Bare Pod = not resilient | If the Pod is deleted or crashes, **nothing recreates it** — no controller is watching it (see Lab 03: Deployments) |

## Estimated cost

**€0** — fully local kind cluster, no AWS resources involved.

## Prerequisites

- Docker installed and running (kind's underlying runtime)
- `kind` installed ([official docs](https://kind.sigs.k8s.io/docs/user/quick-start/#installation))
- `kubectl` installed and available in PATH

## Steps

### 1. Create the kind cluster

```bash
kind create cluster --config kind-config.yaml
```

### 2. Verify the cluster is operational

```bash
kubectl cluster-info --context kind-lab01-first-pod
kubectl get nodes
# → a single node, control-plane role, status Ready
```

### 3. Launch a Pod imperatively (for comparison)

```bash
kubectl run first-pod-imperative --image=nginx:1.27-alpine --port=80
kubectl get pods
# → watch it appear, then move from Pending to Running

# Cleanup: this Pod is just a demonstration, not versioned
kubectl delete pod first-pod-imperative
```

### 4. Apply the declarative manifest

```bash
kubectl apply -f manifests/pod.yaml
```

### 5. Observe the lifecycle

```bash
# Watch the state move through its phases in real time
kubectl get pods -w
# Ctrl+C to stop once it reaches "Running"
```

### 6. Inspect the Pod

```bash
# Full details: image, events, IP, node it runs on
kubectl describe pod first-pod

# Container logs (nginx writes its access/error logs to stdout/stderr)
kubectl logs first-pod

# Interactive shell inside the container
kubectl exec -it first-pod -- sh
# Inside the shell: e.g. `ls /usr/share/nginx/html` then `exit`
```

### 7. Observe the lack of resilience

```bash
# Delete the Pod...
kubectl delete pod first-pod

# ...and notice it is NOT recreated
kubectl get pods
# → no resource: nothing is watching this Pod, unlike a Deployment
```

### 8. Clean up the cluster

```bash
kind delete cluster --name lab01-first-pod
```

## Key takeaways

- A Pod is the smallest deployable unit in Kubernetes, but it is **never
  self-healing** on its own: without a controller on top of it (Deployment,
  ReplicaSet, StatefulSet...), its deletion or crash is final.
- Imperative mode (`kubectl run`) is useful for quick CLI testing, but it's
  neither reproducible nor versionable — declarative mode (YAML file +
  `kubectl apply`) is the standard practice, including in production
  environments.
- `kubectl describe` is the first debugging reflex: the `Events` section at
  the bottom of the output tells the Pod's story (scheduling, image pull,
  any failures).
- This lack of resilience directly motivates Lab 03
  (`lab-03-deployments`), which introduces the controller that
  automatically recreates Pods.

## Useful links

- [kind — Quick Start](https://kind.sigs.k8s.io/docs/user/quick-start/)
- [Kubernetes — Pods (official docs)](https://kubernetes.io/docs/concepts/workloads/pods/)
- [Kubernetes — Pod Lifecycle](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/)
- [kubectl — Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)