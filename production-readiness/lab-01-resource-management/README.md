# Lab 01 — Resource Management

## Objective
Configure explicit CPU/RAM `requests` and `limits` for containers, and
understand how Kubernetes uses them for scheduling decisions and Quality
of Service (QoS) classification.

## Structure
```
lab-01-resource-management/
├── README.md
└── manifests/
    ├── namespace.yaml                    # dedicated namespace for this lab
    ├── limitrange.yaml                   # default resource bounds for the namespace
    ├── deployment-no-resources.yaml      # BestEffort QoS example
    ├── deployment-with-resources.yaml    # Burstable QoS example
    └── deployment-oomkill.yaml           # provoked OOMKill example
```

## What you create
- A dedicated namespace (`resource-management-lab`)
- A Deployment with no `resources` field at all (BestEffort QoS)
- A Deployment with explicit `requests`/`limits` (Burstable QoS)
- A Deployment that deliberately exceeds its memory limit to trigger an OOMKill
- A `LimitRange` enforcing default and bounded resource values namespace-wide

## What you learn

| Concept | Explanation |
|---|---|
| `requests` | The amount of CPU/memory the scheduler guarantees is reserved on a node before placing the Pod. Not a ceiling. |
| `limits` | The hard ceiling a container cannot exceed. CPU limits are throttled; memory limits that are exceeded trigger an OOMKill. |
| QoS `Guaranteed` | Every container has `requests == limits` for both CPU and memory. Highest eviction priority (evicted last). |
| QoS `Burstable` | At least one container has `requests` set, but `requests != limits` somewhere. Medium eviction priority. |
| QoS `BestEffort` | No `requests`/`limits` set at all. First to be evicted/OOM-killed under node pressure. |
| CPU throttling | Exceeding a CPU limit does not kill the container — the kernel just throttles its CPU time. |
| Memory OOMKill | Exceeding a memory limit is fatal: the kernel's OOM killer terminates the process immediately (exit code 137). |
| `LimitRange` | Namespace-scoped object that injects default `requests`/`limits` into containers that don't specify them, and enforces min/max bounds on ones that do. |

## Estimated cost
0€ — entirely local via kind, no AWS resources involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
kubectl cluster-info --context kind-k8s-labs
```

## Steps

```bash
# 1. Create the namespace
kubectl apply -f manifests/namespace.yaml

# 2. Apply the LimitRange BEFORE deploying anything without resources,
#    so you can observe it injecting defaults.
kubectl apply -f manifests/limitrange.yaml
kubectl describe limitrange default-resource-limits -n resource-management-lab

# 3. Deploy the Pod with no resources declared.
#    Because of the LimitRange, it will actually inherit defaultRequest/default
#    values — inspect it to see the injected resources.
kubectl apply -f manifests/deployment-no-resources.yaml
kubectl get pod -n resource-management-lab -l app=nginx-no-resources -o jsonpath='{.items[0].spec.containers[0].resources}'
echo

# 4. Check its QoS class (should be Burstable, because the LimitRange
#    injected requests != limits — NOT BestEffort as you might expect,
#    since the namespace now enforces defaults)
kubectl get pod -n resource-management-lab -l app=nginx-no-resources -o jsonpath='{.items[0].status.qosClass}'
echo

# 5. Deploy the Pod with explicit requests/limits (requests < limits)
kubectl apply -f manifests/deployment-with-resources.yaml
kubectl get pod -n resource-management-lab -l app=nginx-with-resources -o jsonpath='{.items[0].status.qosClass}'
echo
# Expected: Burstable

# 6. Deploy the OOMKill demo and watch it get killed and restarted
kubectl apply -f manifests/deployment-oomkill.yaml
kubectl get pods -n resource-management-lab -l app=stress-oomkill -w
# Ctrl+C once you see RESTARTS increment

# 7. Inspect the termination reason — look for "OOMKilled" and exit code 137
kubectl describe pod -n resource-management-lab -l app=stress-oomkill | grep -A 5 "Last State"

# 8. Compare all three Pods' QoS classes side by side
kubectl get pods -n resource-management-lab -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass

# 9. Clean up the cluster
kind delete cluster --name k8s-labs
```

## Key takeaways
- `requests` drives **scheduling** (does the node have room?); `limits`
  drives **runtime enforcement** (what happens once running?). They answer
  two different questions.
- A container with no `resources` field isn't automatically BestEffort if
  the namespace has a `LimitRange` with defaults — the LimitRange mutates
  the Pod spec at admission time, before scheduling.
- CPU is a *compressible* resource (can be throttled); memory is
  *incompressible* (can't be throttled, so it's killed instead). This is
  why CPU limits are "soft" in practice and memory limits are "hard".
- `Guaranteed` QoS (not demonstrated here — try setting `requests == limits`
  on the with-resources Deployment yourself) gets the strongest protection
  against eviction under node pressure.

## Useful links
- [Kubernetes docs — Managing Resources for Containers](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [Kubernetes docs — Pod Quality of Service Classes](https://kubernetes.io/docs/concepts/workloads/pods/pod-qos/)
- [Kubernetes docs — LimitRange](https://kubernetes.io/docs/concepts/policy/limit-range/)
- [polinux/stress image (Docker Hub)](https://hub.docker.com/r/polinux/stress)