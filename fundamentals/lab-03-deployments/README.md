# Lab 03 — Deployments

## Objective

Understand why a bare Pod is almost never used in practice, by introducing
the Deployment as a management layer on top of Pods: replication,
self-healing, and controlled rollouts.

## Structure

```
lab-03-deployments/
├── README.md              # this file
└── manifests/
    └── deployment.yaml     # nginx Deployment, 3 replicas
```

## What you create

* A `deployment.yaml` manifest defining an nginx Deployment with 3 replicas
* A self-healing demonstration: manually deleting a Pod managed by the
  Deployment, then observing it being recreated automatically
* An image update (`nginx:1.25` → `nginx:1.26`) triggering a tracked and
  historized rollout

## What you learn

| Concept | Explanation |
|---|---|
| Deployment → ReplicaSet → Pods | The Deployment doesn't manage Pods directly: it creates and drives a ReplicaSet, which in turn guarantees the desired number of Pods. Each image update creates a new ReplicaSet. |
| Self-healing | The ReplicaSet continuously compares the actual state (number of live Pods) to the desired state (`replicas: 3`). A Pod that is deleted, crashes, or is evicted from its node is immediately replaced. |
| `kubectl scale` | Changes the number of replicas on the fly, without touching the manifest or redeploying the existing Pods. |
| `selector.matchLabels` | The exact — and only — link between a Deployment and "its" Pods. If the template labels don't match the selector, the Deployment refuses the creation (validation error). |
| `kubectl rollout status/history/undo` | `status` tracks the progress of an ongoing rollout, `history` lists past revisions (one ReplicaSet per revision), `undo` reverts to a previous revision by recreating the old ReplicaSet at the desired scale. |

## Estimated cost

€0 — local kind cluster, public `nginx` image pulled from Docker Hub, no
cloud resources involved.

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

## Steps

```bash
# 1. Apply the Deployment
kubectl apply -f manifests/deployment.yaml

# 2. Check that the 3 Pods are Running
kubectl get pods -l app=nginx-demo

# 3. Observe the Deployment -> ReplicaSet -> Pods chain
kubectl get deployment nginx-demo
kubectl get replicaset -l app=nginx-demo
kubectl describe deployment nginx-demo | grep -A2 "Selector\|Labels"

# 4. Demonstrate self-healing: manually delete a Pod
POD_NAME=$(kubectl get pods -l app=nginx-demo -o jsonpath='{.items[0].metadata.name}')
kubectl delete pod "$POD_NAME"

# A new Pod appears immediately to replace the deleted one
kubectl get pods -l app=nginx-demo -w
# Ctrl+C once a new Pod is visible as Running

# 5. Manually scale the Deployment
kubectl scale deployment nginx-demo --replicas=5
kubectl get pods -l app=nginx-demo

# Back to 3 replicas (as defined in the manifest)
kubectl scale deployment nginx-demo --replicas=3

# 6. Trigger a rollout via an image update
kubectl set image deployment/nginx-demo nginx=nginx:1.26

# 7. Follow the rollout in real time
kubectl rollout status deployment/nginx-demo

# 8. Check the revision history
kubectl rollout history deployment/nginx-demo

# 9. Roll back to the previous revision (nginx:1.25)
kubectl rollout undo deployment/nginx-demo

# Verify the image is back to nginx:1.25
kubectl rollout status deployment/nginx-demo
kubectl get deployment nginx-demo -o jsonpath='{.spec.template.spec.containers[0].image}'
echo

# 10. Cleanup
kubectl delete -f manifests/deployment.yaml
kind delete cluster --name k8s-labs
```

## Key takeaways

* A deleted bare Pod never comes back: nothing watches over it. This is
  exactly what the Deployment fixes through the ReplicaSet.
* The ReplicaSet, not the Deployment, is responsible for day-to-day
  self-healing. The Deployment only steps in during updates (creating a
  new ReplicaSet, progressive rollover).
* `kubectl scale` changes the cluster's desired state, not the local
  `deployment.yaml` file — a later `kubectl apply` on that file would
  bring the replica count back down to 3.
* Every `kubectl set image` (or any change to the Pod `template`) creates
  a new ReplicaSet starting at 0 and progressively scales it up, while the
  old one scales down to 0 — this is the RollingUpdate mechanism, covered
  in more detail later in Phase 5.
* `kubectl rollout undo` doesn't "repair" a revision: it recreates the
  old ReplicaSet, provided it hasn't been purged from history (limited by
  default via `revisionHistoryLimit`).

## Useful links

* [Deployments — Kubernetes docs](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
* [ReplicaSet — Kubernetes docs](https://kubernetes.io/docs/concepts/workloads/controllers/replicaset/)
* [kubectl rollout — reference](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)