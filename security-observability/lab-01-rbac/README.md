# Lab 01 — RBAC

## Objective

Understand Kubernetes' permission model by creating a restricted access for
a dedicated ServiceAccount through a `Role` and a `RoleBinding`, as opposed
to the implicit admin access used via kubeconfig up to now. A `ClusterRole`
and `ClusterRoleBinding` are then added for direct comparison, showing how
the exact same subject can go from "read-only in one namespace" to
"read-only across the whole cluster" depending on which binding is used.

## Structure

```
lab-01-rbac/
├── README.md
├── manifests/
│   ├── 00-namespaces.yaml           # rbac-demo + rbac-demo-other
│   ├── 01-serviceaccount.yaml       # ci-deployer (technical identity)
│   ├── 02-role.yaml                 # namespace-scoped, read-only
│   ├── 03-rolebinding.yaml          # binds ci-deployer to the Role
│   ├── 04-clusterrole.yaml          # cluster-scoped, pods only
│   ├── 05-clusterrolebinding.yaml   # binds ci-deployer to the ClusterRole
│   └── 06-sample-workloads.yaml     # disposable Deployments used as test targets
└── scripts/
    └── test-permissions.sh          # kubectl auth can-i battery, run twice
```

## What you create

- A dedicated `ServiceAccount` (`ci-deployer`) representing a technical
  account (e.g. a CI/CD pipeline), distinct from the admin user used so far
- A `Role` scoped to the `rbac-demo` namespace, with `get`/`list`/`watch`
  permissions on `pods` and `deployments`
- A `RoleBinding` linking `ci-deployer` to that `Role`
- A `ClusterRole` (`cluster-pod-reader`), with `get`/`list`/`watch`
  permissions on `pods` only, at cluster scope
- A `ClusterRoleBinding` linking `ci-deployer` to that `ClusterRole`
- Two disposable Deployments (`sample-nginx` in `rbac-demo`,
  `sample-nginx-other` in `rbac-demo-other`) used as concrete targets for
  the permission tests
- A `test-permissions.sh` script running a battery of
  `kubectl auth can-i --as=` checks with the expected result commented

## What you learn

| Concept | Explanation |
|---|---|
| `Role` vs `ClusterRole` | A `Role` defines rules scoped to a single namespace; a `ClusterRole` defines the same kind of rules but has no intrinsic scope — its scope depends on the binding used |
| `RoleBinding` vs `ClusterRoleBinding` | A `RoleBinding` applies a `Role` (or even a `ClusterRole`) to a single namespace; a `ClusterRoleBinding` applies a `ClusterRole` to the whole cluster |
| RBAC verbs | `get`, `list`, `watch` (read) vs `create`, `update`, `patch`, `delete` (write) — each verb is granted independently |
| `kubectl auth can-i --as=` | Simulates another subject's permissions (here a ServiceAccount) without switching context or testing against real conditions |
| Principle of least privilege | A technical account (CI/CD) should only have the permissions strictly required for its task — here read-only, never mutation |
| Additive permissions | RBAC permissions are additive: `ci-deployer` ends up with the union of the rights granted by the `RoleBinding` and the `ClusterRoleBinding`, never a restriction of one by the other |

## Estimated cost

0€ — entirely local via kind, no AWS resources involved.

## Prerequisites

```bash
kind create cluster --name k8s-labs
kubectl cluster-info --context kind-k8s-labs
```

## Steps

```bash
# 1. Create both namespaces (rbac-demo for the ServiceAccount and its Role,
#    rbac-demo-other used only to prove the Role does NOT reach it)
kubectl apply -f manifests/00-namespaces.yaml

# 2. Create the technical identity
kubectl apply -f manifests/01-serviceaccount.yaml

# 3. Create the namespace-scoped Role (read-only on pods/deployments)
kubectl apply -f manifests/02-role.yaml

# 4. Bind the ServiceAccount to the Role, scoped to rbac-demo only
kubectl apply -f manifests/03-rolebinding.yaml

# 5. Deploy the sample workloads used as test targets
kubectl apply -f manifests/06-sample-workloads.yaml
kubectl get deployments -n rbac-demo
kubectl get deployments -n rbac-demo-other

# 6. Inspect what was created
kubectl describe role pod-deployment-reader -n rbac-demo
kubectl describe rolebinding ci-deployer-binding -n rbac-demo

# 7. First permission check — BEFORE the ClusterRole/ClusterRoleBinding.
#    Expected: full access in rbac-demo (read-only), zero access elsewhere.
chmod +x scripts/test-permissions.sh
./scripts/test-permissions.sh

# 8. Same checks, one command at a time, to see the raw kubectl output
kubectl auth can-i get pods \
  --as=system:serviceaccount:rbac-demo:ci-deployer -n rbac-demo
# -> yes

kubectl auth can-i create pods \
  --as=system:serviceaccount:rbac-demo:ci-deployer -n rbac-demo
# -> no (read-only Role: create was never granted)

kubectl auth can-i get pods \
  --as=system:serviceaccount:rbac-demo:ci-deployer -n rbac-demo-other
# -> no (RoleBinding only applies inside rbac-demo)

# 9. Now widen the scope: create the ClusterRole and bind it cluster-wide
kubectl apply -f manifests/04-clusterrole.yaml
kubectl apply -f manifests/05-clusterrolebinding.yaml

kubectl describe clusterrole cluster-pod-reader
kubectl describe clusterrolebinding ci-deployer-cluster-binding

# 10. Second permission check — AFTER the ClusterRole/ClusterRoleBinding.
#     Expected: pods now readable everywhere, deployments still only
#     readable inside rbac-demo (the ClusterRole never covered deployments).
./scripts/test-permissions.sh

kubectl auth can-i get pods \
  --as=system:serviceaccount:rbac-demo:ci-deployer -n rbac-demo-other
# -> yes now (granted by the ClusterRoleBinding)

kubectl auth can-i list deployments \
  --as=system:serviceaccount:rbac-demo:ci-deployer -n rbac-demo-other
# -> still no (only the namespace-scoped Role covers deployments)

# 11. Clean up the cluster
kind delete cluster --name k8s-labs
```

## Key takeaways

- A `Role`/`RoleBinding` and a `ClusterRole`/`ClusterRoleBinding` can
  coexist on the same subject: permissions are additive, they never
  override or replace one another.
- A `ClusterRole` is only "cluster-wide" if it is used inside a
  `ClusterRoleBinding`. The same `ClusterRole` used inside a `RoleBinding`
  (not shown here, but possible) would stay limited to the binding's
  namespace — it is the binding that determines the scope, not the rule
  object itself.
- `kubectl auth can-i --as=` does not change anything: it's a simulation
  tool on the API server side (SelfSubjectAccessReview /
  SubjectAccessReview), ideal for validating an RBAC policy before wiring
  it into a real pipeline.
- The `ci-deployer` account remains unable to create, update or delete
  anything, even after the `ClusterRole` is added — it only grants
  additional read access on pods, never any write permission.

## Useful links

- [Using RBAC Authorization — Kubernetes docs](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Configure Service Accounts for Pods](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/)
- [kubectl auth can-i reference](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i/)