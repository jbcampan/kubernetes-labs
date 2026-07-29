# Lab 05 — ConfigMaps & Secrets

## Objective

Separate application configuration from the container image, distinguishing
between non-sensitive data (`ConfigMap`) and sensitive data (`Secret`), and
understand the two main ways to inject this data into a Pod: environment
variables and mounted volumes.

## Structure

```
lab-05-configmaps-secrets/
├── README.md
└── manifests/
    ├── configmap.yaml     # Non-sensitive config: APP_NAME, APP_ENV, LOG_LEVEL
    ├── secret.yaml         # Fake base64-encoded values: DB_PASSWORD, API_KEY
    └── deployment.yaml     # busybox Pod consuming both, via env vars + volumes
```

## What you create

* A `ConfigMap` (`app-config`) with 3 non-sensitive variables
* A `Secret` (`app-secret`) with 2 fake values (`DB_PASSWORD`, `API_KEY`)
* A `Deployment` (`config-secret-demo`, `busybox` image) that:
  * injects the whole ConfigMap as environment variables (`envFrom`)
  * explicitly injects one Secret key as an environment variable (`secretKeyRef`)
  * mounts the ConfigMap as a volume at `/etc/config` (one key = one file)
  * mounts the Secret as a volume at `/etc/secrets` (one key = one file)

## What you learn

| Concept | Explanation |
|---|---|
| ConfigMap vs Secret | Same injection mechanism, but a Secret is meant for sensitive data. A native Kubernetes Secret is **not encrypted**: its values are only base64-encoded, trivially reversible (`base64 -d`). Encryption at rest depends on the cluster configuration (etcd encryption), not on the object type. |
| Env vars (`envFrom` / `secretKeyRef`) | Simple, but frozen at container startup: a value change is only visible after the Pod is restarted. |
| Mounted volume | Each key becomes a file in the mount path. The kubelet can automatically update these files when the ConfigMap/Secret changes (unlike env vars), with a sync delay (up to ~1 minute depending on kubelet configuration). |
| `kubectl create configmap --from-literal` / `--from-file` | Two imperative ways to create a ConfigMap: `--from-literal=KEY=value` for direct key/value pairs, `--from-file=path` to inject the content of an entire file (the file name becomes the key). |
| Propagating an update | Editing a ConfigMap with `kubectl edit` or `kubectl apply` does not automatically restart Pods that are already running. Files mounted as volumes eventually get updated; environment variables never change without recreating the Pod. |
| Why you never commit a real Secret in plain text | A `Secret` YAML committed to Git exposes its values to anyone with access to the repo (Git history doesn't disappear). In real usage, these files get encrypted before being committed (e.g. Sealed Secrets, SOPS) or the values are fetched at runtime from an external vault (e.g. External Secrets Operator + AWS Secrets Manager / Vault) — out of scope for this lab, to be explored later on the EKS side. |

## Estimated cost

€0 — 100% local via kind, no AWS resources.

## Prerequisites

```bash
kind create cluster --name k8s-labs
```

## Steps

```bash
# 1. Apply the ConfigMap and the Secret
kubectl apply -f manifests/configmap.yaml
kubectl apply -f manifests/secret.yaml

# 2. Inspect the created objects
kubectl get configmap app-config -o yaml
kubectl get secret app-secret -o yaml
# Secret values appear base64-encoded, not in plain text:
echo 'UzNjcjN0LUY0a2UtUDRzc3cwcmQh' | base64 -d
# -> prints the fake value in plain text: proof this is just an encoding

# 3. Deploy the Pod consuming both objects
kubectl apply -f manifests/deployment.yaml
kubectl get pods -l app=config-secret-demo

# 4. Verify the environment variable injection
POD_NAME=$(kubectl get pods -l app=config-secret-demo -o jsonpath='{.items[0].metadata.name}')
kubectl exec "$POD_NAME" -- env | grep -E 'APP_NAME|APP_ENV|LOG_LEVEL|DB_PASSWORD'
# APP_NAME, APP_ENV, LOG_LEVEL come from the ConfigMap (envFrom)
# DB_PASSWORD comes from the Secret (secretKeyRef) — API_KEY does NOT
# appear here, on purpose: it's only injected via the volume, not env

# 5. Verify the mounted volume injection
kubectl exec "$POD_NAME" -- ls /etc/config
kubectl exec "$POD_NAME" -- cat /etc/config/APP_ENV
kubectl exec "$POD_NAME" -- ls /etc/secrets
kubectl exec "$POD_NAME" -- cat /etc/secrets/API_KEY
# Each key from the ConfigMap/Secret has indeed become a separate file

# 6. Observe that already-loaded environment variables don't get updated
kubectl create configmap app-config \
  --from-literal=APP_NAME="kubernetes-labs-demo" \
  --from-literal=APP_ENV="staging" \
  --from-literal=LOG_LEVEL="debug" \
  --dry-run=client -o yaml | kubectl apply -f -
sleep 5
kubectl exec "$POD_NAME" -- env | grep APP_ENV
# -> still "development": the env var doesn't change without recreating the Pod
kubectl exec "$POD_NAME" -- cat /etc/config/APP_ENV
# -> eventually shows "staging" once the volume sync happens
# (may take up to ~1 minute; re-run the command if needed)

# 7. Cleanup
kind delete cluster --name k8s-labs
```

## Key takeaways

* A native Kubernetes Secret is not a vault: it's an encoding, not
  encryption. Real security comes from RBAC (who can read the object) and,
  optionally, from etcd encryption at the cluster level.
* The choice between env var and volume isn't just a matter of taste: env
  vars are frozen at startup, volumes can be updated live — relevant for
  configs that change often (feature flags, log levels) without wanting to
  restart the Pod.
* In real usage, a real Secret should never be written in plain text in a
  committed file — this lab intentionally uses fake values to illustrate
  the mechanism without that risk.

## Useful links

* [ConfigMaps — official documentation](https://kubernetes.io/docs/concepts/configuration/configmap/)
* [Secrets — official documentation](https://kubernetes.io/docs/concepts/configuration/secret/)
* [Injecting data via volumes vs environment variables](https://kubernetes.io/docs/tasks/inject-data-application/distribute-credentials-secure/)