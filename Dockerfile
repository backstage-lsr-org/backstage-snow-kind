# =============================================================================
#  backstage-snow-poc  — single image, batteries included
#
#  Stage 1  – build the ServiceNow mock (tiny)
#  Stage 2  – scaffold + build Backstage with the SNow plugin
#  Stage 3  – minimal runtime, both processes started by a simple shell supervisor
# =============================================================================

# ── Stage 1: build mock ───────────────────────────────────────────────────────
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# ── Stage 2: scaffold + build Backstage ───────────────────────────────────────
FROM node:20-bookworm-slim AS backstage-build

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Create a fresh Backstage app (non-interactive)
RUN npx --yes @backstage/create-app@latest \
    --skip-install \
    --path /build/app \
    --name backstage-snow-poc 2>&1 | tail -5

WORKDIR /build/app

# Install all deps
RUN yarn install --frozen-lockfile 2>&1 | tail -10

# Install the Roadie ServiceNow plugin
RUN yarn --cwd packages/app add \
    @roadiehq/backstage-plugin-servicenow 2>&1 | tail -5

# Copy our customisations over the scaffold defaults
COPY backstage/app-config.yaml          ./app-config.production.yaml
COPY backstage/catalog/                 ./catalog/
COPY backstage/patches/EntityPage.tsx   ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx          ./packages/app/src/App.tsx

# Build frontend + backend bundles
RUN yarn build 2>&1 | tail -30

# ── Stage 3: minimal runtime ──────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

LABEL org.opencontainers.image.title="Backstage ServiceNow POC" \
      org.opencontainers.image.description="Backstage + ServiceNow mock — no real SNow instance needed" \
      org.opencontainers.image.source="https://github.com/your-org/backstage-snow-poc"

# Only native build tools needed at runtime (for better-sqlite3 rebuild)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Mock ──────────────────────────────────────────────────────────────────────
WORKDIR /mock
COPY --from=mock-build /mock ./

# ── Backstage ─────────────────────────────────────────────────────────────────
WORKDIR /app
COPY --from=backstage-build /build/app/packages/backend/dist/         ./dist/
COPY --from=backstage-build /build/app/app-config.production.yaml     ./app-config.yaml
COPY --from=backstage-build /build/app/catalog/                       ./catalog/
COPY --from=backstage-build /build/app/node_modules/                  ./node_modules/
COPY --from=backstage-build /build/app/packages/backend/node_modules/ ./packages/backend/node_modules/

# ── Supervisor entrypoint (no external downloads) ─────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7007 8181

ENV NODE_ENV=production

ENTRYPOINT ["/entrypoint.sh"]
