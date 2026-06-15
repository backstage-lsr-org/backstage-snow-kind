# Backstage × ServiceNow POC — Kind Edition

Single Docker image with Backstage + ServiceNow mock baked in. Deploy to kind with one command.

---

## Prerequisites

| Tool | Install |
|---|---|
| Node.js 20+ | https://nodejs.org |
| Yarn | `npm install -g yarn` or `corepack enable && yarn set version stable` |
| Docker | https://docs.docker.com/get-docker/ |
| kind | `brew install kind` |
| kubectl | `brew install kubectl` |

---

## Build the image

```bash
# First time: scaffolds Backstage, installs deps, builds, creates Docker image (~10 min)
./build.sh

# Build and push to DockerHub
./build.sh --push yourname/backstage-snow-poc

# Use a specific tag
./build.sh --push yourname/backstage-snow-poc:v1.0.0
```

The `build.sh` script:
1. Runs `npx @backstage/create-app` on your host (creates `.backstage-app/`)
2. Installs deps with `yarn install --immutable`
3. Adds `@roadiehq/backstage-plugin-servicenow`
4. Patches your customisations into the scaffold
5. Runs `yarn tsc && yarn build:backend` (produces `skeleton.tar.gz` + `bundle.tar.gz`)
6. Runs `docker build` using `Dockerfile` (which COPYs the pre-built dist)

> **Why host-build?** Backstage's `yarn build:backend` must run after `yarn install`
> in the monorepo workspace — it can't be replicated inside Docker without
> copying the entire source tree and running install again, which is slow and
> brittle. The host-build approach is the official recommended pattern.

---

## Deploy to kind

```bash
# Start the cluster and deploy (uses image you just built)
./setup.sh --image backstage-snow-poc:latest

# Or use a DockerHub image (no build needed, anyone can run this)
./setup.sh --image yourname/backstage-snow-poc:latest

# Tear down
./setup.sh --teardown
```

Open http://localhost:7007 → Catalog → payment-gateway → see ServiceNow data.

---

## Run locally (no kind needed)

```bash
docker run --rm -p 7007:7007 -p 8181:8181 backstage-snow-poc:latest
```

---

## Connect a real ServiceNow instance

Edit `k8s/01-configmap.yaml` and `k8s/02-secret.yaml`, then:

```bash
kubectl apply -f k8s/01-configmap.yaml -f k8s/02-secret.yaml
kubectl rollout restart deployment/backstage-snow-poc -n backstage-snow
```

No image rebuild needed — config is injected at runtime via env vars.

---

## Project layout

```
backstage-snow-poc/
├── build.sh              ← HOST build script (run this to build the image)
├── setup.sh              ← kind cluster bootstrap
├── Dockerfile            ← used by build.sh (not directly)
├── entrypoint.sh         ← shell supervisor (mock + backstage)
├── .dockerignore
│
├── mock/                 ← ServiceNow mock API (Express)
│   ├── server.js
│   └── package.json
│
├── backstage/
│   ├── app-config.yaml   ← Backstage config (env-var driven)
│   ├── catalog/
│   │   └── all.yaml      ← 5 seed components with SNow ci-sys-id annotations
│   └── patches/
│       ├── EntityPage.tsx ← adds ServiceNow card
│       └── App.tsx        ← wires ServiceNow API factory
│
└── k8s/
    ├── kind-cluster.yaml
    ├── 00-namespace.yaml
    ├── 01-configmap.yaml  ← edit to switch to real ServiceNow
    ├── 02-secret.yaml
    └── 03-deployment.yaml
```
