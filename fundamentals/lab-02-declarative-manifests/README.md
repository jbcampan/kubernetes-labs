# Lab 02 — Declarative Manifests

## Objective

Move from imperative `kubectl` commands to a declarative workflow with
`kubectl apply`, and understand how Kubernetes reconciles the desired
state (your YAML manifest) with the actual state of the cluster — even
when someone changes something by hand in between.

## Structure

```
lab-02-declarative-manifests/
├── README.md
└── manifests/
    ├── pod-v1.yaml   # initial declarative version (image: nginx:1.25)
    ├── pod-v2.yaml   # adds a label (env: lab) and an annotation
    └── pod-v3.yaml   # bumps the image tag to nginx:1.27
```

## What you create

- A single Pod (`declarative-demo`), defined and evolved through three
  successive manifest versions
- A deliberate configuration drift (manual edit vs. the manifest),
  followed by its reconciliation

## What you learn

| Notion | Explanation |
|---|---|
| `kubectl run` | Imperative, one-shot Pod creation. No YAML file, hard to version, hard to reproduce. |
| `kubectl create -f` | Declarative-looking but still imperative in behavior: it applies once and fails with `AlreadyExists` if you run it again on the same object. |
| `kubectl apply -f` | Truly declarative: idempotent, safe to re-run, computes a diff between the manifest, the last applied config, and the live object. |
| Declarative source of truth | The YAML file is what defines the desired state — not whatever currently happens to be running in the cluster. |
| `kubectl diff -f` | Shows what would change on the cluster *before* you commit to `apply`, similar in spirit to `terraform plan`. |
| Labels | Key/value metadata used for **selection** (Services, ReplicaSets, `kubectl get -l`...). |
| Annotations | Key/value metadata for **humans and tooling** (descriptions, build info, controller state) — never used as a selector. |
| `kubectl edit` | Opens the live object in an editor and applies the change immediately to the cluster. Convenient for a quick test, but dangerous in practice: it bypasses version control, is not reproducible, and creates drift against your manifests. |
| Reconciliation | Re-applying the manifest after a manual drift restores the fields that are tracked by the manifest to their declared value. |

## Estimated cost

**0€** — everything runs on a local `kind` cluster created and destroyed
within this lab. No AWS resource is used.

## Prerequisites

- `kind` and `kubectl` installed locally
- No cluster needs to be running beforehand — this lab creates and
  destroys its own cluster, independently of any other lab

## Steps

### 0. Create the cluster

This lab is self-contained: it creates its own `kind` cluster and destroys
it at the end, so you can run it in isolation, repeat it as many times as
you want, and never leave a cluster silently running in the background.

```bash
kind create cluster --name k8s-labs
kubectl cluster-info --context kind-k8s-labs
kubectl get nodes
```

### 1. Imperative vs. declarative — a quick contrast

First, see what an imperative command actually produces under the hood.
This does **not** create anything sensitive to clean up (`--dry-run=client`
only prints the YAML, it doesn't touch the cluster):

```bash
kubectl run declarative-demo --image=nginx:1.25 --dry-run=client -o yaml
```

Now create a real, throwaway Pod imperatively, then remove it — this is
exactly the kind of one-off object that's hard to reproduce or version:

```bash
kubectl run temp-imperative --image=nginx:1.25
kubectl get pod temp-imperative
kubectl delete pod temp-imperative
```

Next, compare `kubectl create -f` with `kubectl apply -f`. `create` is not
idempotent — running it twice on the same manifest fails:

```bash
kubectl create -f manifests/pod-v1.yaml
kubectl create -f manifests/pod-v1.yaml
# Error from server (AlreadyExists): pods "declarative-demo" already exists
```

Clean up before moving to the declarative workflow:

```bash
kubectl delete -f manifests/pod-v1.yaml
```

### 2. First declarative apply

```bash
kubectl apply -f manifests/pod-v1.yaml
kubectl get pod declarative-demo --show-labels
```

Run the exact same command again — no error, because `apply` is
idempotent:

```bash
kubectl apply -f manifests/pod-v1.yaml
# pod/declarative-demo unchanged
```

Inspect the annotation `kubectl apply` adds automatically to track what it
last applied — this is how `apply` knows what it manages:

```bash
kubectl get pod declarative-demo -o jsonpath='{.metadata.annotations.kubectl\.kubernetes\.io/last-applied-configuration}'
```

### 3. Preview a change with `kubectl diff`

Before applying `pod-v2.yaml` (new label `env: lab` and a description
annotation), preview exactly what will change on the cluster:

```bash
kubectl diff -f manifests/pod-v2.yaml
```

You should see the added label and annotation shown as a diff, with
nothing yet applied. Now apply it for real:

```bash
kubectl apply -f manifests/pod-v2.yaml
kubectl get pod declarative-demo --show-labels
kubectl describe pod declarative-demo | grep -A2 Annotations
```

### 4. Create a manual drift

Open the live Pod directly in the cluster and change the image tag by
hand, simulating what happens when someone "just fixes it quickly" on a
running cluster instead of going through the manifest:

```bash
kubectl edit pod declarative-demo
```

In the editor, change:

```yaml
image: nginx:1.25
```

to:

```yaml
image: nginx:1.24
```

Save and exit. The live cluster state now diverges from
`manifests/pod-v2.yaml`, and nothing in Git or in your files reflects this
change — this is exactly the kind of silent drift `kubectl edit` makes
easy to introduce, and why it should be avoided outside of quick,
throwaway debugging.

### 5. Detect the drift with `kubectl diff`

```bash
kubectl diff -f manifests/pod-v2.yaml
```

The diff reveals the image field has drifted from `nginx:1.24` (live,
manually edited) back to `nginx:1.25` (declared in the manifest) —
exactly the mismatch you just introduced.

### 6. Reconcile — the manifest wins

```bash
kubectl apply -f manifests/pod-v2.yaml
kubectl get pod declarative-demo -o jsonpath='{.spec.containers[0].image}{"\n"}'
```

The image is back to `nginx:1.25`. The manual change is gone: `apply`
restored the field to what the manifest declares, because that field was
already tracked in the last-applied configuration. This is the core
lesson: **the manifest is the source of truth, not whatever is currently
running.**

### 7. A real, intentional change — `pod-v3.yaml`

This time the change is legitimate and versioned: bump the image tag to
`1.27`. Preview it first, then apply:

```bash
kubectl diff -f manifests/pod-v3.yaml
kubectl apply -f manifests/pod-v3.yaml
kubectl get pod declarative-demo -o jsonpath='{.spec.containers[0].image}{"\n"}'
```

Check that the container actually restarted with the new image:

```bash
kubectl get pod declarative-demo
# look at the RESTARTS column, it should have incremented
```

### 8. Cleanup the Pod

```bash
kubectl delete -f manifests/pod-v3.yaml
```

### 9. Delete the cluster

Since this lab created its own cluster, it also tears it down — nothing
persists to the next lab, on purpose:

```bash
kind delete cluster --name k8s-labs
```

## Understanding checkpoints

- Can you explain, in one sentence, why `kubectl create -f` is not truly
  declarative even though it takes a YAML file?
- What's the practical difference between a label and an annotation — and
  which one would you use to let a Service find this Pod?
- Why did the manual `kubectl edit` change to the image get silently
  overwritten by `kubectl apply`, while a field you'd never declared in
  any manifest would have been left alone?
- In a real team workflow, what should replace `kubectl edit` entirely?

## Useful links

- [Kubernetes docs — Managing Resources (declarative vs imperative)](https://kubernetes.io/docs/concepts/overview/working-with-objects/object-management/)
- [Kubernetes docs — kubectl apply / three-way merge](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/)
- [Kubernetes docs — Labels and Selectors](https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/)
- [Kubernetes docs — Annotations](https://kubernetes.io/docs/concepts/overview/working-with-objects/annotations/)