# Lab 03 — Custom values

## Objective
Fine-tune a Helm chart (replicas, image, resources) and install it with
different value sets depending on the environment (dev/staging/prod), to
illustrate how the same chart can produce different deployments without
ever touching its templates.

## Structure

    packaging/lab-03-custom-values/
    ├── README.md
    ├── helm/
    │   └── webapp/
    │       ├── Chart.yaml
    │       ├── values.yaml            # chart defaults
    │       ├── .helmignore
    │       └── templates/
    │           ├── _helpers.tpl
    │           ├── deployment.yaml    # parameterized replicas/image/resources + if/else
    │           ├── service.yaml
    │           └── NOTES.txt
    ├── values-dev.yaml                # override: 1 replica, no resources
    ├── values-staging.yaml            # override: 2 replicas, resources set
    ├── values-prod.yaml               # override: 3 replicas, stricter resources
    └── .gitignore

## What you create
- A `webapp` chart with fully parameterizable `replicaCount`,
  `image.repository`/`image.tag`, `service.type`/`service.port`, and
  `resources.requests`/`resources.limits`.
- Three values files (`values-dev.yaml`, `values-staging.yaml`,
  `values-prod.yaml`) that only redefine what actually changes.
- Two Namespaces (`dev`, `staging`) each running a release of the same
  chart, installed with different values.
- An example of `helm upgrade --dry-run` to preview the effect of
  switching to prod values before actually applying it.

## What you learn

| Concept | Explanation |
|---|---|
| Values precedence | `values.yaml` (chart default) < file passed with `-f` < `--set` flag. The last one applied wins; multiple `-f` flags apply in command-line order. |
| Structuring `values.yaml` | Group by domain (`image:`, `service:`, `resources:`) rather than flat, to stay readable and consistent with Helm conventions (`helm create`). |
| Conditional templating (`if`) | `{{- if .Values.resources.requests }}` only generates a YAML block when the value is actually set — avoids an empty or invalid `resources: {}`. |
| `helm upgrade --dry-run` | Simulates rendering and applying a values change without touching the cluster — essential before a real `helm upgrade` on staging/prod. |
| Link to Phase 5 | The `resources.requests`/`resources.limits` defined here will be revisited and deepened (QoS, fine tuning) in `production-readiness/lab-01-resource-management`. |

## Estimated cost
0€ — local kind cluster, no AWS resources involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
kubectl create namespace dev
kubectl create namespace staging
```

## Steps

```bash
# 1. Install the release in dev, with dev values (1 replica, no resources)
helm install webapp-dev ./helm/webapp \
  -f values-dev.yaml \
  --namespace dev

# 2. Install the same release in staging, with staging values (2 replicas, resources)
helm install webapp-staging ./helm/webapp \
  -f values-staging.yaml \
  --namespace staging

# 3. Compare the two deployments: different replica count and resources
kubectl get deployment -n dev
kubectl get deployment -n staging
kubectl get deployment webapp-dev -n dev -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'
kubectl get deployment webapp-staging -n staging -o jsonpath='{.spec.template.spec.containers[0].resources}{"\n"}'

# 4. Preview (without applying anything) what switching to prod values
#    would do to the existing staging release
helm upgrade webapp-staging ./helm/webapp \
  -f values-prod.yaml \
  --namespace staging \
  --dry-run

# 5. Verify values precedence: --set always wins over -f
helm upgrade webapp-dev ./helm/webapp \
  -f values-dev.yaml \
  --set replicaCount=2 \
  --namespace dev \
  --dry-run
# → the rendered output should show replicas: 2, even though values-dev.yaml says replicaCount: 1

# 6. Cleanup: uninstall the releases
helm uninstall webapp-dev -n dev
helm uninstall webapp-staging -n staging
kubectl delete namespace dev staging

# 7. Destroy the cluster
kind delete cluster --name k8s-labs
```

## Key takeaways
- Why you should never hardcode an environment-specific value inside a
  template: the template stays identical, only the source of the values
  changes.
- Why `values-dev.yaml` can legitimately leave `resources` empty locally
  (kind has no real capacity constraint to respect) while
  `values-staging.yaml`/`values-prod.yaml` enforce them — anticipating the
  behavior of a real cluster (EKS) where missing limits can starve other
  Pods.
- Why `--dry-run` is the first command to run before any `helm upgrade`
  touching a shared environment (staging, prod): it reveals templating
  errors and the scope of the diff before any real impact.
- Difference between file-based overrides (`-f`, versionable, reviewable)
  and `--set` overrides (one-off, handy on the CLI but not tracked in git)
  — good practice: `--set` for quick debugging, `-f` for anything that
  needs to be reproducible.

## Useful links
- Helm — Values Files: https://helm.sh/docs/chart_template_guide/values_files/
- Helm — Template Function List (if/with/range): https://helm.sh/docs/chart_template_guide/function_list/
- Helm — helm upgrade: https://helm.sh/docs/helm/helm_upgrade/