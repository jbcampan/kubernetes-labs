# Lab 01 — Install an existing Helm chart

## Objective

Install a Helm chart published by a third party to understand what Helm
actually brings on top of raw YAML manifests applied with `kubectl apply`:
packaging, versioning, templating, and lifecycle management of a "release"
(install / upgrade / rollback / uninstall).

> **Note on the chart choice**: the original lab statement mentioned
> `bitnami/nginx`. Since Broadcom ended the free Bitnami image program
> (2025-2026), versioned images for Bitnami charts have been moved to an
> unmaintained "legacy" repository, which regularly breaks deployments
> with `ImagePullBackOff` errors. This lab uses **podinfo**
> (`stefanprodan/podinfo`) instead: a small, actively maintained Go demo
> app used by CNCF projects (Flux, Flagger) for this exact kind of
> exercise. The Helm vocabulary learned here is strictly identical.

## Structure

```
lab-01-install-chart/
├── README.md
└── helm/
    └── values-override.yaml   # minimal override of the chart's default values
```

No `manifests/` folder in this lab: we don't hand-write any Kubernetes
resource YAML, we install an already-published chart. No `.gitignore`:
nothing sensitive or local is generated.

## What you create

* A Helm repo added locally (`stefanprodan`)
* A release named `podinfo` installed in the `default` namespace with a
  custom values file (`values-override.yaml`)
* An update of that release (changing `replicaCount` via CLI)
* A browsable release history (`helm history`)
* A clean uninstall at the end of the lab

## What you learn

| Notion | Explanation |
|---|---|
| Helm repo | An index of published charts, added locally with `helm repo add` and refreshed with `helm repo update`. Equivalent of an APT/Docker Hub repository, but for Kubernetes packages. |
| Chart | The Helm "package": parameterized YAML templates + metadata (`Chart.yaml`) + default values (`values.yaml`). |
| Release | An installed instance of a chart in a cluster, identified by a name (here `podinfo`). The same chart can be installed multiple times under different release names. |
| Values | The parameters that fill in the chart's templates. A merge between the chart's `values.yaml` (defaults) and our overrides (`-f values-override.yaml`, `--set`). |
| `helm install` / `helm upgrade --install` | Create or update a release. The `upgrade --install` form (alias `-i`) is idempotent: it installs if the release doesn't exist, otherwise it updates — handy in CI/CD. |
| `helm uninstall` | Removes all Kubernetes resources created by the release, along with its history (unless `--keep-history` is used). |
| `helm list` / `helm status` / `helm history` | Tracking installed releases, their detailed status, and their successive revisions (the basis for `helm rollback`, used later in production-readiness). |
| `helm template` | Renders the chart's templates as raw YAML **without** contacting the cluster or installing anything — useful for reviewing "what Helm will actually apply" before committing. |
| `helm show values` | Displays the chart's default values, essential to check before writing an override (a key that doesn't exist in `values.yaml` is silently ignored by the templates). |
| Release state storage | By default, Helm stores each release revision as a Kubernetes **Secret** in the release's namespace (`kubectl get secrets -l owner=helm`) — no external database involved. |

## Estimated cost

0€ — local kind cluster, lightweight chart (a single Go image a few MB in
size), no cloud resources involved.

## Prerequisites

```bash
# Create the local cluster dedicated to this lab
kind create cluster --name k8s-labs

# Confirm kubectl is pointing at it
kubectl cluster-info --context kind-k8s-labs

# Confirm Helm is installed
helm version
```

## Steps

```bash
# ─── 1. Add the Helm repo and refresh it ───────────────────────────────

helm repo add stefanprodan https://stefanprodan.github.io/podinfo
helm repo update

# Search the chart in the repo we just added — confirms it's available
# and shows its latest version
helm search repo stefanprodan/podinfo


# ─── 2. Inspect the chart before installing it ─────────────────────────

# Show the chart's default values — used as a reference when writing our
# values-override.yaml (already done in helm/values-override.yaml)
helm show values stefanprodan/podinfo

# Preview the YAML Helm will actually generate, WITH our overrides,
# WITHOUT touching the cluster — the safety step before any real
# install/upgrade
helm template podinfo stefanprodan/podinfo \
  -f helm/values-override.yaml


# ─── 3. Install the chart with our custom values ───────────────────────

helm upgrade --install podinfo stefanprodan/podinfo \
  -f helm/values-override.yaml \
  --namespace default \
  --wait

# Check the release
helm list
helm status podinfo

# Check the Kubernetes resources created by the chart
kubectl get all -l app.kubernetes.io/name=podinfo

# Test the app: port-forward then HTTP request
kubectl port-forward svc/podinfo 9898:9898 &
curl -s http://localhost:9898 | grep message
# → should show "hello from lab-01-install-chart", confirming that our
#   values-override.yaml was applied and not the chart defaults
kill %1


# ─── 4. Update the release (values change) ──────────────────────────────

# Bump from 2 to 3 replicas, directly via --set (without touching the
# values file, to illustrate both ways of overriding)
helm upgrade podinfo stefanprodan/podinfo \
  -f helm/values-override.yaml \
  --set replicaCount=3 \
  --namespace default \
  --wait

kubectl get pods -l app.kubernetes.io/name=podinfo
# → should show 3 Pods Running


# ─── 5. Check the release history ───────────────────────────────────────

helm history podinfo
# → should show 2 revisions: REVISION 1 (install) and REVISION 2 (upgrade)

# Bonus: where Helm stores this history — one Secret per revision
kubectl get secrets -l owner=helm,name=podinfo


# ─── 6. Clean uninstall ──────────────────────────────────────────────────

helm uninstall podinfo --namespace default

# Confirm nothing is left
helm list
kubectl get all -l app.kubernetes.io/name=podinfo
# → no resource should be returned

helm repo remove stefanprodan


# ─── 7. Cluster cleanup ───────────────────────────────────────────────────

kind delete cluster --name k8s-labs
```

## Key takeaways

* **Why `--wait`?** Without this flag, `helm install`/`upgrade` returns as
  soon as the resources are created on the API side, not when the Pods
  are actually `Ready`. `--wait` blocks the command until the Deployment
  has reached the expected number of replicas — useful in CI/CD to avoid
  chaining a next step onto a deployment that's still in progress.
* **`helm upgrade --install` vs `helm install`**: in an automated
  pipeline, you don't always know whether the release already exists
  (first deployment vs subsequent ones). `upgrade --install` handles both
  cases with a single idempotent command — the form we'll use
  consistently from now on.
* **Values: merge, not replace.** `values-override.yaml` only redefines 4
  keys (`replicaCount`, `ui`, `resources`, `service`) — every other chart
  key (image, probes, service account...) keeps its default value. Helm
  merges the two, it doesn't replace the whole file.
* **No rollback in this lab** — deliberately left out here to stay
  focused on the basic vocabulary. `helm rollback` will be used hands-on
  in `production-readiness/lab-04-rolling-update-canary`, where the
  notion of deployment strategy makes more sense.

## Useful links

* [Official Helm documentation — Quickstart](https://helm.sh/docs/intro/quickstart/)
* [Official Helm documentation — Using Helm](https://helm.sh/docs/intro/using_helm/)
* [podinfo GitHub repo](https://github.com/stefanprodan/podinfo)
* [podinfo chart on Artifact Hub](https://artifacthub.io/packages/helm/podinfo/podinfo)