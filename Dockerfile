# =============================================================================
#  backstage-snow-poc — single image, batteries included
#
#  create-app 0.7.x dropped --name/--path flags; we pipe the name via stdin.
#  Build sequence:
#    1. scaffold (echo name | npx create-app --skip-install)
#    2. yarn install
#    3. patch our files in
#    4. yarn tsc && yarn build:backend  →  produces skeleton.tar.gz + bundle.tar.gz
#    5. copy artefacts into a lean runtime image
# =============================================================================

# ── Stage 1: ServiceNow mock ─────────────────────────────────────────────────
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# ── Stage 2: Backstage build ──────────────────────────────────────────────────
FROM node:20-bookworm-slim AS backstage-build

ENV PYTHON=/usr/bin/python3
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ git curl ca-certificates build-essential libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# create-app 0.7.x: interactive only, pipe the app name through stdin
RUN echo "backstage-snow-poc" | npx --yes @backstage/create-app@latest --skip-install 2>&1

# The app is created in a directory named after the app: backstage-snow-poc/
WORKDIR /build/backstage-snow-poc

# Show which yarn version the scaffold chose
RUN echo "=== yarn version ===" && yarn --version && \
    echo "=== package scripts ===" && \
    node -e "const p=require('./package.json');console.log(JSON.stringify(p.scripts,null,2))" && \
    echo "=== packageManager field ===" && \
    node -e "const p=require('./package.json');console.log(p.packageManager||'(not set)')"

# Install all workspace deps
RUN yarn install --immutable 2>&1 | tail -15

# Add the Roadie ServiceNow plugin
RUN yarn --cwd packages/app add \
    @roadiehq/backstage-plugin-servicenow 2>&1 | tail -5

# ── Patch our files over the scaffold defaults ────────────────────────────────
COPY backstage/app-config.yaml          ./app-config.production.yaml
COPY backstage/catalog/                 ./catalog/
COPY backstage/patches/EntityPage.tsx   ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx          ./packages/app/src/App.tsx

# Generate TS type definitions, then build the backend bundle
RUN yarn tsc 2>&1 | tail -5

# Full output — no tail, so we see every line including real errors
RUN yarn build:backend --config app-config.production.yaml 2>&1; echo "BUILD_EXIT:$?"

# Broad search: find everything produced, regardless of where it landed
RUN echo "=== all dist dirs ===" && find . -name "dist" -not -path "*/node_modules/*" | sort && \
    echo "=== all tarballs ===" && find . -name "*.tar.gz" -not -path "*/node_modules/*" | sort && \
    echo "=== packages/backend full tree ===" && find packages/backend -not -path "*/node_modules/*" | sort && \
    echo "=== root ls ===" && ls -la

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

# Yarn config for workspaces focus
COPY --from=backstage-build /build/backstage-snow-poc/.yarn        ./.yarn
COPY --from=backstage-build /build/backstage-snow-poc/.yarnrc.yml  ./ 2>/dev/null || true
COPY --from=backstage-build /build/backstage-snow-poc/backstage.json ./ 2>/dev/null || true

# Skeleton: restores the package.json tree so yarn can install prod deps
COPY --from=backstage-build \
    /build/backstage-snow-poc/yarn.lock \
    /build/backstage-snow-poc/package.json \
    /build/backstage-snow-poc/packages/backend/dist/skeleton.tar.gz \
    ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

# Install only production deps
RUN yarn workspaces focus --all --production 2>&1 | tail -10

# Catalog lives outside the bundle — copy separately
COPY --from=backstage-build /build/backstage-snow-poc/catalog/ ./catalog/

# Bundle: the compiled backend + embedded static frontend
COPY --from=backstage-build \
    /build/backstage-snow-poc/packages/backend/dist/bundle.tar.gz \
    /build/backstage-snow-poc/app-config.production.yaml \
    ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz && \
    mv app-config.production.yaml app-config.yaml

# ── Process supervisor ────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]
