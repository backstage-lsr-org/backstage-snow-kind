# Backstage × ServiceNow POC — Kind Edition

> **No ServiceNow license needed.** The image ships with a built-in mock API.  
> One image. One command. Anyone on your team can run it.

---

## What's inside the single Docker image

```
┌─────────────────────────────────────────────────────┐
│  Docker image: yourname/backstage-snow-poc:latest   │
│                                                     │
│  ┌─────────────────────────┐                        │
│  │  Backstage  :7007       │  – Full IDP            │
│  │  + ServiceNow plugin    │  – 5 seed services     │
│  └─────────────────────────┘  – Guest auth          │
│                                                     │
│  ┌─────────────────────────┐                        │
│  │  ServiceNow Mock  :8181 │  – Table API           │
│  │  (Express)              │  – Incidents/Changes   │
│  └─────────────────────────┘  – On-call roster      │
│                                                     │
│  Supervised by s6-overlay (both processes managed)  │
└─────────────────────────────────────────────────────┘
```

Both services start automatically inside one container.  
No external dependencies — works fully offline after `docker pull`.

---

## Prerequisites

| Tool | Install |
|---|---|
| Docker | https://docs.docker.com/get-docker/ |
| kind | `brew install kind` / https://kind.sigs.k8s.io |
| kubectl | `brew install kubectl` / https://kubernetes.io/docs/tasks/tools/ |

---

## Quick start (use pre-built image from DockerHub)

```bash
git clone https://github.com/your-org/backstage-snow-poc
cd backstage-snow-poc

# Start the kind cluster and deploy (pulls image from DockerHub)
./setup.sh --image your-dockerhub-user/backstage-snow-poc:latest

# Open Backstage
open http://localhost:7007
```

That's it. Navigate to **Catalog → payment-gateway** and you'll see ServiceNow incidents, changes, and on-call data.

---

## Build & push your own image

```bash
# Login to DockerHub first
docker login

# Build image + push + deploy all in one step
./setup.sh --build yourname/backstage-snow-poc

# Or just build locally (no push)
docker build -t yourname/backstage-snow-poc:latest .

# Load into kind without pushing to DockerHub
kind load docker-image yourname/backstage-snow-poc:latest --name backstage-snow-poc
kubectl apply -f k8s/
```

---

## Project layout

```
backstage-snow-poc/
├── Dockerfile                          # Single multi-stage build (Backstage + mock)
├── setup.sh                            # Bootstrap script
│
├── mock/
│   ├── server.js                       # ServiceNow mock (Express)
│   └── package.json
│
├── backstage/
│   ├── app-config.yaml                 # Backstage config (env-var driven)
│   ├── catalog/
│   │   └── all.yaml                    # 5 seed components with SNow annotations
│   └── patches/
│       ├── EntityPage.tsx              # Adds ServiceNow card to catalog
│       └── App.tsx                     # Wires ServiceNow API factory
│
└── k8s/
    ├── kind-cluster.yaml               # Kind cluster (port-mapped 7007 + 8181)
    ├── 00-namespace.yaml
    ├── 01-configmap.yaml               # Env config (edit to switch to real SNow)
    ├── 02-secret.yaml                  # Credentials
    └── 03-deployment.yaml              # Deployment + NodePort Services
```

---

## Switch to a real ServiceNow instance

No rebuild needed — just update the ConfigMap and Secret:

**1. Edit `k8s/01-configmap.yaml`:**
```yaml
data:
  SERVICENOW_BASE_URL: "https://your-instance.service-now.com"
  SERVICENOW_USERNAME: "your-api-user"
```

**2. Edit `k8s/02-secret.yaml`:**
```yaml
stringData:
  SERVICENOW_PASSWORD: "your-real-password"
  SERVICENOW_AUTH_B64: "<echo -n 'user:pass' | base64>"
```

**3. Update catalog annotations** in `k8s/01-configmap.yaml` or via a Backstage catalog processor with real CI sys_ids from your CMDB.

**4. Apply and restart:**
```bash
kubectl apply -f k8s/01-configmap.yaml -f k8s/02-secret.yaml
kubectl rollout restart deployment/backstage-snow-poc -n backstage-snow
```

---

## Mock API reference

All endpoints require `Authorization: Basic <any-base64>`.

| Endpoint | Description |
|---|---|
| `GET /health` | Health check |
| `GET /api/now/table/cmdb_ci_service` | List CIs |
| `GET /api/now/table/cmdb_ci_service/:sys_id` | Single CI |
| `GET /api/now/table/incident?sysparm_query=cmdb_ci=svc001` | Incidents for CI |
| `GET /api/now/table/change_request?sysparm_query=cmdb_ci=svc001` | Changes for CI |
| `GET /api/now/on_call_rota/whoisoncall?cmdb_ci=svc001` | On-call roster |

Seeded CIs: `svc001` Payment Gateway · `svc002` User Auth · `svc003` Notifications · `svc004` Reporting · `svc005` API Gateway

---

## Useful commands

```bash
# Check pod status
kubectl get pods -n backstage-snow

# Live logs
kubectl logs -f -l app=backstage-snow-poc -n backstage-snow

# Smoke test mock API
curl -u admin:admin http://localhost:8181/health
curl -u admin:admin "http://localhost:8181/api/now/table/cmdb_ci_service" | jq .

# Shell into pod
kubectl exec -it -n backstage-snow deploy/backstage-snow-poc -- sh

# Restart pod (picks up ConfigMap/Secret changes)
kubectl rollout restart deployment/backstage-snow-poc -n backstage-snow

# Tear everything down
./setup.sh --teardown
```

---

## CI/CD — auto-publish to DockerHub

Add these secrets to your GitHub repo:

| Secret | Value |
|---|---|
| `DOCKERHUB_USERNAME` | Your DockerHub username |
| `DOCKERHUB_TOKEN` | DockerHub access token (Settings → Security) |

Then every push to `main` builds and publishes `yourname/backstage-snow-poc:latest`.
Tagging `v1.2.3` also publishes `yourname/backstage-snow-poc:1.2.3`.

---

## Roadmap / next steps

- [ ] Persistent SQLite via PVC (data survives pod restarts)
- [ ] PostgreSQL option (add postgres StatefulSet to k8s/)
- [ ] Backstage Software Templates → create ServiceNow Change Requests
- [ ] CMDB catalog processor (auto-import CIs as Backstage components)
- [ ] Helm chart for production deployments
- [ ] SSO / OAuth2 login
