# kubernetes-labs

A progressive, hands-on collection of Kubernetes labs built for learning and employability. Each lab isolates a single concept, implemented locally with realistic (but non-production-data) manifests.

## Goal

Learn Kubernetes from scratch, one notion at a time, entirely in local clusters (`kind`) — no cloud account, no billing risk. This repository is a sandbox, deliberately decoupled from any business application: every lab illustrates nginx, redis, a generic PostgreSQL, or a toy app.

Progression is incremental: each lab isolates a single important notion, with heavy `kubectl` practice in the CLI before Helm is introduced at all (deliberately pushed to Phase 4 — raw manifests need to be understood before they're templated).

## Tools used

| Tool | Usage |
|------|-------|
| **kind** | Local Kubernetes clusters — every lab runs entirely offline, no cloud billing |
| **kubectl** | Primary interface for the first 3 phases — raw manifests before any templating |
| **Helm** | Introduced only from Phase 4 onward, once raw YAML is well understood |
| **Bash** | One-off scripts (stress tests, seed data) when a lab needs them |

## Cost

**$0 for the entire curriculum.** Everything runs locally via `kind` — no AWS resources are ever billed. If a lab ever deviated from this (it doesn't, currently), it would be flagged explicitly and prominently in that lab's README.

Each lab is self-contained at the cluster level: it starts with `kind create cluster --name k8s-labs` and ends with `kind delete cluster --name k8s-labs`.

---

## Curriculum

### 1 — `fundamentals/` — Using Kubernetes without Helm
> The foundation. Represents roughly half of the overall understanding of the whole curriculum.

| Lab | Description |
|-----|-------------|
| lab-01-first-pod | Launch a first Pod "by hand", explore it with kubectl |
| lab-02-declarative-manifests | Move from imperative to declarative (`kubectl apply`) |
| lab-03-deployments | Understand why a bare Pod is almost never used directly |
| lab-04-services | Internal networking: ClusterIP, NodePort, DNS discovery |
| lab-05-configmaps-secrets | Separate application configuration from code |
| lab-06-namespaces | Organize and isolate cluster resources |

---

### 2 — `workloads-storage/` — Non-permanent workloads & storage
> Notions encountered early in the field, even before talking about networking.

| Lab | Description |
|-----|-------------|
| lab-01-jobs-cronjobs | Non-permanent workloads: batch jobs, scheduled tasks |
| lab-02-persistent-volumes | Pods are ephemeral — PV, PVC, StorageClass |
| lab-03-statefulsets | Deploy a database properly: stable identity, persistent storage |

---

### 3 — `networking/` — Exposing what's deployed
> Now that deploying is understood, learn to expose it.

| Lab | Description |
|-----|-------------|
| lab-01-ingress-nginx | Install an Ingress Controller, understand the reverse proxy |
| lab-02-ingress-rules | Multiple HTTP routes (`/`, `/api`, `/admin`), host/path/TLS |
| lab-03-network-policies | Control Pod-to-Pod traffic — Zero Trust |

---

### 4 — `packaging/` — Helm
> Deliberately placed after the fundamentals: Helm hides a lot of YAML, so raw manifests need to be understood first.

| Lab | Description |
|-----|-------------|
| lab-01-install-chart | Install an existing chart (nginx, prometheus, redis) |
| lab-02-create-chart | Create a first chart (`Chart.yaml`, `templates/`, `values.yaml`) |
| lab-03-custom-values | Parameterize a chart (replicas, image, resources) — templating |

---

### 5 — `production-readiness/` — Production concerns
> Only now do we talk about production.

| Lab | Description |
|-----|-------------|
| lab-01-resource-management | CPU/RAM — requests, limits, QoS |
| lab-02-health-checks | Resilient applications — startup/liveness/readiness probes |
| lab-03-horizontal-pod-autoscaler | Autoscale Pods with Metrics Server + HPA |
| lab-04-rolling-update-canary | Deployment strategies — RollingUpdate, Recreate, Canary |

---

### 6 — `security-observability/` — Security & observability
> Closing the loop on production-readiness: who can do what, and how to see and diagnose what's happening.

| Lab | Description |
|-----|-------------|
| lab-01-rbac | Kubernetes permissions — ServiceAccount, Role, RoleBinding |
| lab-02-observability | Observe a cluster — Metrics Server, dashboard, `kubectl top` |
| lab-03-debugging | Diagnose common incidents: `ImagePullBackOff`, `CrashLoopBackOff`, `Pending`, config errors |

---

**Total: 22 labs.**

## Repository structure

```
kubernetes-labs/
├── fundamentals/              # Phase 1 — 6 labs
├── workloads-storage/         # Phase 2 — 3 labs
├── networking/                # Phase 3 — 3 labs
├── packaging/                 # Phase 4 — 3 labs (Helm)
├── production-readiness/      # Phase 5 — 4 labs
└── security-observability/    # Phase 6 — 3 labs
```

Each lab follows the same structure:

```
lab-XX-name/
├── README.md
├── manifests/        # Raw YAML (pod.yaml, deployment.yaml, service.yaml...)
├── helm/              # Helm chart — only from Phase 4 onward
├── scripts/           # Bash scripts when needed (stress test, seed, etc.)
└── .gitignore          # If needed (local kubeconfig, Helm values with secrets, etc.)
```

## How to use

Each lab is self-contained, independent, and disposable. The general workflow is:

```bash
cd <phase>/lab-XX-name

kind create cluster --name k8s-labs

# ... follow the lab's README ...

kind delete cluster --name k8s-labs
```

Refer to each lab's `README.md` for prerequisites, step-by-step instructions, and what to observe. If a lab depends on something installed by a previous lab in the same phase (e.g. an Ingress Controller), that dependency and its reinstall command are called out explicitly at the top of the lab's Steps section.

## Prerequisites

- Docker (required by `kind`)
- [`kind`](https://kind.sigs.k8s.io/) — local Kubernetes clusters
- `kubectl`
- `helm` (from Phase 4 onward)

## Going further

Once the 22 labs are done, here are natural directions to keep going — no imposed order, pick what's most relevant:

| Topic | Why |
|-------|-----|
| **GitOps** (ArgoCD, Flux) | Continuous deployment — a natural next step once Helm is comfortable |
| **Advanced observability** (Prometheus, Grafana) | Goes beyond the Metrics Server / `kubectl top` covered in Phase 6 |
| **Service Mesh** (Istio, Linkerd) | mTLS, traffic shaping, retries — builds on the NetworkPolicy concepts from Phase 3 |
| **Operators / CRDs** | Extending the Kubernetes API itself, rather than just consuming it |
| **Deeper security** (kube-bench, Trivy, Pod Security Standards) | Natural continuation of the RBAC lab in Phase 6 |
| **Managed clusters** (EKS, GKE, AKS) | Moving from local (`kind`) to cloud — node management, IAM/Workload Identity integration |