# =============================================================================
#  backstage-snow-poc  — single image, batteries included
# =============================================================================

# ── Stage 1: build mock ───────────────────────────────────────────────────────
FROM node:20-alpine AS mock-build

WORKDIR /mock

COPY mock/package.json .
RUN npm install --omit=dev

COPY mock/server.js .

# ── Stage 2: build Backstage ──────────────────────────────────────────────────
FROM node:20-bookworm-slim AS backstage-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

RUN npx --yes @backstage/create-app@latest \
    --skip-install \
    --path /build/app \
    --name backstage-snow-poc

WORKDIR /build/app

# Install dependencies
RUN yarn install

# Install ServiceNow plugin
RUN yarn --cwd packages/app add @roadiehq/backstage-plugin-servicenow

# Apply customizations
COPY backstage/app-config.yaml ./app-config.production.yaml
COPY backstage/catalog ./catalog
COPY backstage/patches/EntityPage.tsx ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx ./packages/app/src/App.tsx

# Build Backstage
RUN yarn build

# Debug (remove later if desired)
RUN ls -la packages/backend && \
    ls -la packages/backend/dist

# ── Stage 3: runtime ──────────────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

LABEL org.opencontainers.image.title="Backstage ServiceNow POC"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Mock server
WORKDIR /mock
COPY --from=mock-build /mock ./

# Backstage
WORKDIR /app

COPY --from=backstage-build /build/app/packages/backend/dist ./dist
COPY --from=backstage-build /build/app/app-config.production.yaml ./app-config.yaml
COPY --from=backstage-build /build/app/catalog ./catalog
COPY --from=backstage-build /build/app/node_modules ./node_modules
COPY --from=backstage-build /build/app/package.json ./package.json

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV NODE_ENV=production

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]