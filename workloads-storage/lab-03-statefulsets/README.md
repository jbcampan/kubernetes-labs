# Lab 03 — StatefulSets

## Objective

Deploy a database-like workload using a StatefulSet instead of a Deployment,
to get a stable network identity and a dedicated, persistent volume per
replica. This lab uses generic PostgreSQL instances (independent, not real
replication) purely to demonstrate StatefulSet mechanics: ordered Pod
naming, per-Pod DNS, and per-Pod storage.

## Structure

```
lab-03-statefulsets/
├── README.md
└── manifests/
    ├── secret.yaml              # fictitious DB credentials
    ├── headless-service.yaml    # clusterIP: None, required for per-Pod DNS
    └── statefulset.yaml         # 3 replicas + volumeClaimTemplates
```

## What you create

- A `Secret` holding fictitious PostgreSQL credentials
- A headless `Service` (`clusterIP: None`) named `postgres-headless`
- A `StatefulSet` named `postgres` with 3 replicas, each backed by its own
  PersistentVolumeClaim generated from `volumeClaimTemplates`
- A live demonstration of stable Pod identity (`postgres-0`, `postgres-1`,
  `postgres-2`) and per-Pod DNS resolution

## What you learn

| Concept | Explanation |
|---|---|
| StatefulSet vs Deployment | Pods get a stable, predictable name (`postgres-0`, `postgres-1`...) instead of a random suffix. They are created and terminated in order (0, then 1, then 2), and terminated in reverse order. |
| Headless Service | With `clusterIP: None`, the Service does not load-balance. Instead, it lets Kubernetes DNS resolve one A record per Pod: `postgres-0.postgres-headless.default.svc.cluster.local`. |
| `volumeClaimTemplates` | Each replica gets its own PVC, automatically named `<template-name>-<pod-name>` (e.g. `postgres-storage-postgres-0`). Unlike a Deployment's shared or ephemeral volume, data is not lost when a specific Pod restarts. |
| Scaling and storage | Scaling a StatefulSet down does **not** delete the PVCs of the removed replicas — they remain, ready to be reattached if you scale back up. Scaling to 0 and deleting the StatefulSet still leaves the PVCs behind; they must be deleted manually. |
| Real-world use case | Databases (PostgreSQL, MySQL, MongoDB), distributed systems (Kafka, Elasticsearch, ZooKeeper) — anything that needs a stable identity and/or persistent per-instance storage. |

## Estimated cost

0€ — 100% local via kind. The `standard` StorageClass used here is
provisioned by kind's built-in `local-path-provisioner`, no cloud storage
involved.

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

This lab is fully self-contained: no dependency on any previous lab.

## Steps

```bash
# 1. Create the fictitious credentials Secret
kubectl apply -f manifests/secret.yaml

# 2. Create the headless Service (must exist before/with the StatefulSet
#    for DNS records to resolve correctly)
kubectl apply -f manifests/headless-service.yaml

# 3. Create the StatefulSet
kubectl apply -f manifests/statefulset.yaml

# 4. Watch Pods being created IN ORDER: postgres-0 must be Running before
#    postgres-1 starts, etc. Ctrl+C once all 3 are Running.
kubectl get pods -l app=postgres-statefulset -w

# 5. Confirm the stable names (not random suffixes like a Deployment)
kubectl get pods -l app=postgres-statefulset -o wide

# 6. Confirm one PVC per Pod was created automatically
kubectl get pvc

# 7. Confirm per-Pod DNS resolution via the headless Service
kubectl run dns-test --image=busybox:1.36 --rm -it --restart=Never -- \
  nslookup postgres-0.postgres-headless.default.svc.cluster.local

# 8. Delete one Pod and observe it comes back with the SAME name and
#    reattaches the SAME PVC (unlike a Deployment, which would create a
#    Pod with a new random name and no shared storage)
kubectl delete pod postgres-1
kubectl get pods -l app=postgres-statefulset -w

# 9. Scale down: postgres-2 is terminated, but its PVC is kept
kubectl scale statefulset postgres --replicas=2
kubectl get pvc

# 10. Scale back up: postgres-2 is recreated and reattaches its ORIGINAL
#     PVC (same data directory, not a fresh volume)
kubectl scale statefulset postgres --replicas=3
kubectl get pvc

# 11. Clean up the StatefulSet and Service
kubectl delete -f manifests/statefulset.yaml
kubectl delete -f manifests/headless-service.yaml
kubectl delete -f manifests/secret.yaml

# 12. Confirm the PVCs are STILL there — StatefulSet deletion never
#     cascades to PersistentVolumeClaims, by design (data safety)
kubectl get pvc

# 13. Manual cleanup of the PVCs (and their underlying PVs)
kubectl delete pvc -l app=postgres-statefulset

# 14. Tear down the cluster
kind delete cluster --name k8s-labs
```

## Key takeaways

- Why does `postgres-1` come back with the exact same name after being
  deleted, while a Deployment Pod would come back with a different one?
- What would happen to the data if this had been a plain Deployment with
  a single shared volume instead of `volumeClaimTemplates`?
- Why does Kubernetes deliberately **not** delete PVCs when a StatefulSet
  is deleted or scaled down?
- In this lab the 3 PostgreSQL instances are fully independent (no real
  replication between them) — what would be needed to turn this into an
  actual replicated PostgreSQL cluster?

## Useful links

- https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- https://kubernetes.io/docs/tutorials/stateful-application/basic-stateful-set/
- https://kubernetes.io/docs/concepts/services-networking/service/#headless-services
- https://hub.docker.com/_/postgres