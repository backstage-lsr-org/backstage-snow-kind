#!/usr/bin/env bash
# =============================================================================
#  build.sh — scaffolds Backstage on the host, patches it, builds the image
#
#  Usage:
#    ./build.sh                          # build locally, tag backstage-snow-poc:latest
#    ./build.sh --push yourname/bs-poc  # also push to DockerHub
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${SCRIPT_DIR}/.backstage-app"
IMAGE_TAG="backstage-snow-poc:latest"
PUSH=false
PUSH_TAG=""

# ── Args ──────────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --push) PUSH=true; PUSH_TAG="$2"; IMAGE_TAG="$2"; shift 2 ;;
    --tag)  IMAGE_TAG="$2"; shift 2 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

info()    { echo -e "\033[0;36m[INFO]\033[0m $*"; }
success() { echo -e "\033[0;32m[✓]\033[0m $*"; }
error()   { echo -e "\033[0;31m[ERROR]\033[0m $*"; exit 1; }

# ── Preflight ─────────────────────────────────────────────────────────────────
command -v node  >/dev/null || error "node not found"
command -v yarn  >/dev/null || error "yarn not found"
command -v docker >/dev/null || error "docker not found"

info "Node: $(node --version)  Yarn: $(yarn --version)"

# ── Step 1: Scaffold ─────────────────────────────────────────────────────────
if [[ -d "$APP_DIR" ]]; then
  info "Existing scaffold found at $APP_DIR — skipping create-app"
else
  info "Scaffolding Backstage app..."
  mkdir -p "$(dirname "$APP_DIR")"
  cd "$(dirname "$APP_DIR")"
  echo "backstage-snow-poc" | npx --yes @backstage/create-app@latest --skip-install 2>&1 | tail -5
  mv backstage-snow-poc "$APP_DIR"
  success "Scaffold created at $APP_DIR"
fi

cd "$APP_DIR"

# ── Step 2: Install deps ──────────────────────────────────────────────────────
info "Installing dependencies..."
yarn install --immutable 2>&1 | tail -5
success "Deps installed"

# ── Step 3: Add ServiceNow plugin ────────────────────────────────────────────
info "Adding Roadie ServiceNow plugin..."
yarn --cwd packages/app add @roadiehq/backstage-plugin-servicenow 2>&1 | tail -3
success "Plugin added"

# ── Step 4: Patch our files in ───────────────────────────────────────────────
info "Patching custom files..."
cp "${SCRIPT_DIR}/backstage/app-config.yaml"          ./app-config.production.yaml
cp -r "${SCRIPT_DIR}/backstage/catalog/"              ./catalog/
cp "${SCRIPT_DIR}/backstage/patches/EntityPage.tsx"   ./packages/app/src/components/catalog/EntityPage.tsx
cp "${SCRIPT_DIR}/backstage/patches/App.tsx"          ./packages/app/src/App.tsx
success "Files patched"

# ── Step 5: Build ─────────────────────────────────────────────────────────────
info "Running yarn tsc..."
yarn tsc 2>&1 | tail -3

info "Running yarn build:backend..."
yarn build:backend --config app-config.production.yaml 2>&1 | tail -10

# Verify tarballs exist
ls packages/backend/dist/skeleton.tar.gz >/dev/null || error "skeleton.tar.gz not found!"
ls packages/backend/dist/bundle.tar.gz   >/dev/null || error "bundle.tar.gz not found!"
success "Build complete: $(ls -lh packages/backend/dist/*.tar.gz | awk '{print $5, $9}')"

# ── Step 6: Copy mock into app dir so it's in docker build context ────────────
info "Copying ServiceNow mock..."
cp -r "${SCRIPT_DIR}/mock"          ./mock
cp    "${SCRIPT_DIR}/entrypoint.sh" ./entrypoint.sh
chmod +x ./entrypoint.sh

# ── Step 7: Docker build using the scaffolded Dockerfile ─────────────────────
info "Building Docker image: ${IMAGE_TAG}"

# Wrap the scaffolded packages/backend/Dockerfile to also include our mock
cat > /tmp/backstage-snow-Dockerfile << 'INNEREOF'
# ── Re-use the official scaffolded Dockerfile, then add mock on top ───────────

# Stage A: build mock
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# Stage B: official Backstage backend image (uses host-built dist/)
FROM node:20-bookworm-slim AS backstage

ENV PYTHON=/usr/bin/python3
ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

COPY --chown=node:node .yarn          ./.yarn
COPY --chown=node:node .yarnrc.yml    ./
COPY --chown=node:node backstage.json ./

COPY --chown=node:node yarn.lock package.json packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

RUN yarn workspaces focus --all --production 2>&1 | tail -5

COPY --chown=node:node catalog/                         ./catalog/
COPY --chown=node:node packages/backend/dist/bundle.tar.gz \
                        app-config.production.yaml      ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz && \
    mv app-config.production.yaml app-config.yaml

# ── Stage C: final image with both services ───────────────────────────────────
FROM backstage AS final

# Add mock (runs as root to copy, then switch back)
USER root
WORKDIR /mock
COPY --from=mock-build /mock ./
COPY --chown=node:node entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
WORKDIR /app

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]
INNEREOF

docker build \
  -f /tmp/backstage-snow-Dockerfile \
  -t "${IMAGE_TAG}" \
  .

success "Image built: ${IMAGE_TAG}"

# ── Step 8: Optionally push ───────────────────────────────────────────────────
if $PUSH; then
  info "Pushing ${PUSH_TAG}..."
  docker push "${PUSH_TAG}"
  success "Pushed!"
fi

echo ""
echo "  Test locally:  docker run --rm -p 7007:7007 -p 8181:8181 ${IMAGE_TAG}"
echo "  Backstage:     http://localhost:7007"
echo "  SNow mock:     http://localhost:8181/health"
