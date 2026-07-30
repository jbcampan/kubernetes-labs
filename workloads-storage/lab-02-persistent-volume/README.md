# Lab 02 — Persistent Volumes

## Objective

Understand that Pods are ephemeral: anything written to their filesystem
disappears when the Pod is deleted. This lab introduces PersistentVolume
(PV) and PersistentVolumeClaim (PVC) to decouple storage from the Pod's
lifecycle, using static provisioning (hostPath) suited to kind.

## Structure

    lab-02-persistent-volumes/
    ├── README.md
    └── manifests/
        ├── pod-ephemeral.yaml     # Pod with emptyDir — data lost on deletion
        ├── pv.yaml                # Static PersistentVolume (hostPath)
        ├── pvc.yaml                # PersistentVolumeClaim bound to the PV
        └── pod-persistent.yaml    # Pod mounting the PVC — data survives Pod deletion

## What you create

- A data-loss demonstration using a Pod with `emptyDir`
- A static `PersistentVolume` based on `hostPath`, suited to kind
- A `PersistentVolumeClaim` that automatically binds to that PV
- A Pod mounting the PVC, with persistent writes verified after deleting
  and recreating the Pod

## What you learn

| Concept | Explanation |
|---|---|
| PV / PVC lifecycle | The PV is a cluster-scoped resource (not namespaced), the PVC is a storage request made from a namespace; Kubernetes binds them when `storageClassName`, `accessModes`, and capacity match |
| Static vs dynamic provisioning | Here the PV is created by hand (static). In production, a `StorageClass` with a provisioner (e.g. the EBS CSI driver on EKS) creates the volume on demand (dynamic) |
| kind's default `StorageClass` | kind ships a `standard` class with dynamic provisioning via `rancher.local-path-provisioner` — not used here so the static binding stays explicit |
| `accessModes` | `ReadWriteOnce` (single node, read/write), `ReadOnlyMany` (multiple nodes, read-only), `ReadWriteMany` (multiple nodes, read/write, rare and backend-dependent) |
| `reclaimPolicy` | `Retain`: the PV and its data survive PVC deletion (requires manual action to reuse the volume); `Delete`: the volume is automatically deleted with the PVC |
| `emptyDir` vs persistent volume | `emptyDir` is created and destroyed with the Pod; a persistent volume (PV/PVC) exists independently of the Pod that mounts it |

## Estimated cost

€0 — local kind cluster, `hostPath` on the kind node's filesystem (a local
Docker container), no cloud resources involved.

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

## Steps

### 1. Demonstrate data loss (emptyDir)

```bash
# Create the Pod with an emptyDir volume
kubectl apply -f manifests/pod-ephemeral.yaml

# Wait until it's ready
kubectl wait --for=condition=Ready pod/ephemeral-writer --timeout=60s

# Verify the file exists
kubectl exec ephemeral-writer -- cat /data/message.txt

# Delete the Pod — the emptyDir is destroyed with it
kubectl delete pod ephemeral-writer

# Recreate an identical Pod
kubectl apply -f manifests/pod-ephemeral.yaml
kubectl wait --for=condition=Ready pod/ephemeral-writer --timeout=60s

# The file is rewritten "from scratch" — the previous write left no trace
# on the node (note: the command uses '>' not '>>', which already shows
# this, but the point is to confirm nothing survived at the node level)
kubectl exec ephemeral-writer -- cat /data/message.txt

# Clean up this part of the demo
kubectl delete pod ephemeral-writer
```

### 2. Create the PersistentVolume

```bash
# Static provisioning: the PV exists independently of any PVC
kubectl apply -f manifests/pv.yaml

# The PV should show up as "Available"
kubectl get pv pv-lab02-manual
```

### 3. Create the PersistentVolumeClaim

```bash
# The PVC requests 500Mi ReadWriteOnce on the "manual" class —
# Kubernetes binds it automatically to pv-lab02-manual
kubectl apply -f manifests/pvc.yaml

# The PVC should turn "Bound"
kubectl get pvc pvc-lab02

# The PV also turns "Bound", referencing the PVC
kubectl get pv pv-lab02-manual
```

### 4. Write data through the PVC

```bash
kubectl apply -f manifests/pod-persistent.yaml
kubectl wait --for=condition=Ready pod/persistent-writer --timeout=60s

# Check the written content
kubectl exec persistent-writer -- cat /data/message.txt
```

### 5. Verify persistence after deleting the Pod

```bash
# Delete only the Pod — the PV and its content are untouched
kubectl delete pod persistent-writer

# Recreate the Pod
kubectl apply -f manifests/pod-persistent.yaml
kubectl wait --for=condition=Ready pod/persistent-writer --timeout=60s

# The write command uses '>>': you should see TWO lines,
# proof that the data survived the Pod's deletion
kubectl exec persistent-writer -- cat /data/message.txt
```

### 6. Observe `reclaimPolicy: Retain` in action

```bash
# Delete the Pod, then the PVC
kubectl delete -f manifests/pod-persistent.yaml
kubectl delete -f manifests/pvc.yaml

# With reclaimPolicy: Retain, the PV is NOT deleted or automatically
# reusable — it moves to "Released", not "Available"
kubectl get pv pv-lab02-manual

# Explicit manual cleanup (that's the whole point of Retain:
# preventing accidental data loss)
kubectl delete pv pv-lab02-manual
```

### 7. Clean up the cluster

```bash
kind delete cluster --name k8s-labs
```

## Key takeaways

| Question | Answer |
|---|---|
| Why does the file disappear with `emptyDir` after the Pod is deleted? | `emptyDir` is a volume whose lifecycle is strictly tied to the Pod: Kubernetes creates it when the Pod is created and destroys it when the Pod is deleted, regardless of the node |
| Why use `hostPath` only here and not in production? | `hostPath` ties the volume to a specific node's filesystem; on a multi-node cluster, a Pod recreated on a different node wouldn't see the data. On EKS, you'd use a dynamic PV backed by EBS/EFS |
| What happens if the PVC requests more than the PV's capacity? | The PVC stays `Pending`, no matching PV is found |
| Why `Retain` rather than `Delete` in this lab? | To make it visible, for teaching purposes, that deleting a PVC doesn't necessarily delete the data — it's an explicit choice of `reclaimPolicy`, not a universal default behavior |
| Would a PV recreated with the same `hostPath` see the old data? | Yes, as long as the `/mnt/data/lab02` directory still exists on the kind node (a Docker container) — which is also a limitation: `kind delete cluster` removes that node container, so data never survives the cluster itself being deleted |

## Useful links

- [Kubernetes docs — Persistent Volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Kubernetes docs — Volumes (emptyDir, hostPath...)](https://kubernetes.io/docs/concepts/storage/volumes/)
- [kind — Local Path Provisioner](https://kind.sigs.k8s.io/docs/user/local-path-provisioning/)