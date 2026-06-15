# =============================================================================
#  backstage-snow-poc  — single image, batteries included
#
#  Stage 1  – build the ServiceNow mock (tiny)
#  Stage 2  – build Backstage from the official @backstage/create-app scaffold
#  Stage 3  – minimal runtime, both services started via s6-overlay
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
    python3 make g++ git curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Create a fresh Backstage app (non-interactive)
RUN npx --yes @backstage/create-app@latest \
    --skip-install \
    --path /build/app \
    --name backstage-snow-poc 2>&1 | tail -5

WORKDIR /build/app

# Pin catalog-model to avoid peer-dep conflicts with plugin
RUN yarn install --frozen-lockfile 2>&1 | tail -10

# Install the Roadie ServiceNow plugin (best community plugin for SNow)
RUN yarn --cwd packages/app add \
    @roadiehq/backstage-plugin-servicenow 2>&1 | tail -5

# Copy our custom files over the scaffold
COPY backstage/app-config.yaml          ./app-config.production.yaml
COPY backstage/catalog/                 ./catalog/
COPY backstage/patches/EntityPage.tsx   ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx          ./packages/app/src/App.tsx

# Build frontend + backend
RUN yarn build 2>&1 | tail -30

# Prune dev deps for runtime
RUN find . -name "node_modules" -prune -o -name "*.ts" -print | head -5 && \
    yarn workspaces focus --all --production 2>&1 | tail -5 || true

# ── Stage 3: minimal runtime ──────────────────────────────────────────────────
FROM node:20-bookworm-slim AS runtime

LABEL org.opencontainers.image.title="Backstage ServiceNow POC" \
      org.opencontainers.image.description="Backstage + ServiceNow mock — no real SNow instance needed" \
      org.opencontainers.image.source="https://github.com/your-org/backstage-snow-poc"

# s6-overlay for process supervision (run mock + backstage in one container)
ENV S6_VERSION=3.1.6.2
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl xz-utils python3 make g++ libsqlite3-dev \
    && ARCH=$(uname -m | sed 's/x86_64/x86_64/;s/aarch64/aarch64/') \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-noarch.tar.xz" \
       | tar -C / -Jxp \
    && curl -fsSL "https://github.com/just-containers/s6-overlay/releases/download/v${S6_VERSION}/s6-overlay-${ARCH}.tar.xz" \
       | tar -C / -Jxp \
    && rm -rf /var/lib/apt/lists/*

# ── Mock server ───────────────────────────────────────────────────────────────
WORKDIR /mock
COPY --from=mock-build /mock ./

# ── Backstage ─────────────────────────────────────────────────────────────────
WORKDIR /app
COPY --from=backstage-build /build/app/packages/backend/dist/        ./dist/
COPY --from=backstage-build /build/app/app-config.production.yaml    ./app-config.yaml
COPY --from=backstage-build /build/app/catalog/                      ./catalog/
COPY --from=backstage-build /build/app/node_modules/                 ./node_modules/
COPY --from=backstage-build /build/app/packages/backend/node_modules/ ./packages/backend/node_modules/

# ── s6 service definitions ────────────────────────────────────────────────────
# Service: servicenow-mock
RUN mkdir -p /etc/s6-overlay/s6-rc.d/servicenow-mock
COPY <<'EOF' /etc/s6-overlay/s6-rc.d/servicenow-mock/type
longrun
EOF
COPY <<'EOF' /etc/s6-overlay/s6-rc.d/servicenow-mock/run
#!/command/execlineb -P
export MOCK_PORT 8181
cd /mock
/usr/local/bin/node server.js
EOF
RUN chmod +x /etc/s6-overlay/s6-rc.d/servicenow-mock/run

# Service: backstage
RUN mkdir -p /etc/s6-overlay/s6-rc.d/backstage
COPY <<'EOF' /etc/s6-overlay/s6-rc.d/backstage/type
longrun
EOF
COPY <<'EOF' /etc/s6-overlay/s6-rc.d/backstage/run
#!/command/execlineb -P
export NODE_ENV production
export POSTGRES_HOST localhost
export POSTGRES_PORT 5432
cd /app
/usr/local/bin/node dist/index.cjs.js --config app-config.yaml
EOF
RUN chmod +x /etc/s6-overlay/s6-rc.d/backstage/run

# Activate both services in the bundle
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/servicenow-mock \
    && touch /etc/s6-overlay/s6-rc.d/user/contents.d/backstage

EXPOSE 7007 8181

ENV NODE_ENV=production

ENTRYPOINT ["/init"]
