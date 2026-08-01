# Lab 02 — Ingress rules: path, host and TLS routing

## Objective
Create several distinct HTTP routes (`/`, `/api`, `/admin`) to different
Services, relying on the Ingress Controller installed in the previous lab
(`lab-01-ingress-nginx`). Introduces path-based routing, host-based
routing, and TLS termination at the Ingress level.

## Structure
```
lab-02-ingress-rules/
├── README.md
├── manifests/
│   ├── frontend-configmap.yaml    # dummy HTML served by the frontend
│   ├── frontend-deployment.yaml
│   ├── frontend-service.yaml
│   ├── api-configmap.yaml         # dummy HTML served by the api
│   ├── api-deployment.yaml
│   ├── api-service.yaml
│   ├── admin-configmap.yaml       # dummy HTML served by the admin
│   ├── admin-deployment.yaml
│   ├── admin-service.yaml
│   ├── ingress-path-based.yaml    # path routing: /, /api, /admin
│   ├── ingress-host-based.yaml    # host routing: app.local, api.local
│   └── ingress-tls.yaml           # TLS variant of the host-based rules
├── scripts/
│   └── generate-tls-cert.sh       # generates the self-signed cert + TLS Secret
└── .gitignore                     # ignores the locally generated cert/key
```

## What you create
- Three Deployment + Service pairs (`frontend`, `api`, `admin`), each an
  `nginx:1.27-alpine` image serving a differentiated HTML page via
  ConfigMap
- A `path-based-ingress` Ingress routing `/`, `/api`, `/admin` to the three
  Services
- A `host-based-ingress` Ingress routing `app.local` and `api.local` to
  `frontend-service` and `api-service`
- A self-signed certificate (SAN `app.local` + `api.local`) and the
  associated `app-tls-secret` TLS Secret
- A `tls-ingress` Ingress reusing the host-based routing with TLS
  termination

## What you learn

| Concept | Explanation |
|---|---|
| `pathType: Prefix` | Matches any path starting with the given prefix (`/` matches everything) |
| `pathType: ImplementationSpecific` | Lets the controller (here ingress-nginx) interpret the path as a regex — needed to capture and rewrite |
| `nginx.ingress.kubernetes.io/rewrite-target` | Rewrites the URL sent to the backend; here `/$2` reinjects the captured group after `/api` or `/admin`, so nginx correctly serves `index.html` |
| Host-based routing (`spec.rules[].host`) | The same Ingress Controller distinguishes requests based on the `Host` header, independently of the path |
| Path-based routing | A single host, multiple backends distinguished by URL prefix |
| `kubernetes.io/tls` Secret | Dedicated Secret type containing `tls.crt` and `tls.key`, referenced in `spec.tls[].secretName` |
| TLS termination at Ingress | HTTPS traffic is decrypted at the Ingress Controller level; backend Pods remain plain HTTP |
| Dependency | Requires the ingress-nginx Ingress Controller installed in the previous lab (reinstallation documented below) |

## Estimated cost
€0 — everything runs locally via kind, no AWS resources involved.

## Prerequisites
```bash
kind create cluster --name k8s-labs
```

## Steps

```bash
# --- Dependency: reinstalling the Ingress Controller from the previous lab ---
# This lab relies on ingress-nginx (lab-01-ingress-nginx). Since every lab
# is independent at the cluster level, we reinstall it here.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.2/deploy/static/provider/kind/deploy.yaml

# Wait for the controller to be ready before continuing
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s

# --- Deploying the three backends ---
kubectl apply -f manifests/frontend-configmap.yaml
kubectl apply -f manifests/frontend-deployment.yaml
kubectl apply -f manifests/frontend-service.yaml

kubectl apply -f manifests/api-configmap.yaml
kubectl apply -f manifests/api-deployment.yaml
kubectl apply -f manifests/api-service.yaml

kubectl apply -f manifests/admin-configmap.yaml
kubectl apply -f manifests/admin-deployment.yaml
kubectl apply -f manifests/admin-service.yaml

# Check that the three Pods are Running
kubectl get pods -o wide

# --- Part 1: path-based routing ---
kubectl apply -f manifests/ingress-path-based.yaml

# Port-forward the controller to test locally without editing /etc/hosts
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8080:80

# In another terminal:
curl http://localhost:8080/          # should show the "Frontend service" page
curl http://localhost:8080/api       # should show the "API service" page
curl http://localhost:8080/admin     # should show the "Admin panel" page

# Clean up before the next part
kubectl delete -f manifests/ingress-path-based.yaml

# --- Part 2: host-based routing ---
kubectl apply -f manifests/ingress-host-based.yaml

# Add the following entries to /etc/hosts (requires admin rights):
# 127.0.0.1 app.local
# 127.0.0.1 api.local

# Still with the port-forward active on 8080:
curl -H "Host: app.local" http://localhost:8080/    # -> Frontend service
curl -H "Host: api.local" http://localhost:8080/    # -> API service
# or, with the /etc/hosts entries in place:
curl http://app.local:8080/
curl http://api.local:8080/

kubectl delete -f manifests/ingress-host-based.yaml

# --- Part 3: TLS ---
chmod +x scripts/generate-tls-cert.sh
./scripts/generate-tls-cert.sh

kubectl apply -f manifests/ingress-tls.yaml

# HTTPS test (443 exposed by the controller, via a dedicated port-forward)
kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8443:443

curl -k --resolve app.local:8443:127.0.0.1 https://app.local:8443/
curl -k --resolve api.local:8443:127.0.0.1 https://api.local:8443/
# -k because the certificate is self-signed (not trusted by a known CA)

# --- Final cleanup ---
kind delete cluster --name k8s-labs
```

## Key takeaways
- Path-based routing with rewriting is useful when several distinct
  applications share a single domain name (one certificate, one DNS entry)
- Host-based routing is closer to a real production setup, where each
  application service has its own subdomain
- The TLS Secret is just a key/certificate container: nothing prevents
  generating it manually (as here) or via a tool like cert-manager (out of
  scope for this lab, intentionally)
- On EKS, this same Ingress would be handled by an equivalent controller
  (ingress-nginx or the AWS Load Balancer Controller), with a certificate
  issued by ACM instead of a self-signed one

## Useful links
- [ingress-nginx — Rewrite annotations](https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration/annotations/#rewrite)
- [Kubernetes docs — Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)
- [Kubernetes docs — TLS Secrets](https://kubernetes.io/docs/concepts/configuration/secret/#tls-secrets)