# =============================================================================
#  backstage-snow-poc — single image, batteries included
#
#  Based on the OFFICIAL Backstage multi-stage Docker pattern (v1.51):
#  https://backstage.io/docs/deployment/docker
#
#  Stages:
#    mock-build        – builds the ServiceNow mock Express server
#    backstage-build   – scaffolds + fully builds Backstage inside Docker
#    runtime           – lean image; shell supervisor starts both processes
# =============================================================================

# ── Stage 1: ServiceNow mock ─────────────────────────────────────────────────
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# ── Stage 2: Full Backstage build inside Docker ───────────────────────────────
# (multi-stage / "all inside Docker" approach from the official docs)
FROM node:20-bookworm-slim AS backstage-build

ENV PYTHON=/usr/bin/python3
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ git curl ca-certificates build-essential libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Enable Corepack so the Yarn version declared in package.json is used
RUN corepack enable

WORKDIR /build

# Scaffold the app — this writes package.json, yarn.lock, .yarnrc.yml, etc.
RUN npx --yes @backstage/create-app@latest \
    --skip-install \
    --path /build/app \
    --name backstage-snow-poc 2>&1 | tail -5

WORKDIR /build/app

# Use the Yarn version pinned by create-app (Berry/4.x)
RUN yarn install --immutable 2>&1 | tail -10

# Add the Roadie ServiceNow plugin to the frontend package
RUN yarn --cwd packages/app add \
    @roadiehq/backstage-plugin-servicenow 2>&1 | tail -5

# ── Patch our customisations over the scaffold ────────────────────────────────
COPY backstage/app-config.yaml          ./app-config.production.yaml
COPY backstage/catalog/                 ./catalog/
COPY backstage/patches/EntityPage.tsx   ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx          ./packages/app/src/App.tsx

# Step 1: generate TypeScript type definitions (required before backend build)
RUN yarn tsc 2>&1 | tail -10

# Step 2: build backend — show FULL output so we can see errors
RUN yarn build:backend --config app-config.production.yaml 2>&1

# Debug: show everything produced so we know exact paths
RUN echo "=== packages/backend/ ===" && find packages/backend -not -path '*/node_modules/*' | sort && \
    echo "=== dist/ (if exists) ===" && (ls -lah packages/backend/dist/ 2>/dev/null || echo "NO DIST FOLDER") && \
    echo "=== root dist-types/ (if exists) ===" && (ls -lah dist-types/ 2>/dev/null || echo "NO DIST-TYPES")

# ── Stage 3: lean runtime ─────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

LABEL org.opencontainers.image.title="Backstage ServiceNow POC" \
      org.opencontainers.image.description="Backstage + ServiceNow mock — no real SNow instance needed"

ENV PYTHON=/usr/bin/python3
ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ build-essential libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# ── ServiceNow mock ───────────────────────────────────────────────────────────
WORKDIR /mock
COPY --from=mock-build /mock ./

# ── Backstage ─────────────────────────────────────────────────────────────────
WORKDIR /app

# Copy Yarn config so `yarn workspaces focus` works
COPY --from=backstage-build /build/app/.yarn        ./.yarn
COPY --from=backstage-build /build/app/.yarnrc.yml  ./
COPY --from=backstage-build /build/app/backstage.json ./

# Copy skeleton + lock files, extract to restore package.json tree
COPY --from=backstage-build \
    /build/app/yarn.lock \
    /build/app/package.json \
    /build/app/packages/backend/dist/skeleton.tar.gz \
    ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

# Install production deps only (leverages the package.json tree from skeleton)
RUN yarn workspaces focus --all --production 2>&1 | tail -10

# Copy our catalog (not inside the bundle)
COPY --from=backstage-build /build/app/catalog/ ./catalog/

# Copy the compiled backend bundle + both configs, then extract
COPY --from=backstage-build \
    /build/app/packages/backend/dist/bundle.tar.gz \
    /build/app/app-config.production.yaml \
    ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz && \
    mv app-config.production.yaml app-config.yaml

# ── Supervisor ────────────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]
