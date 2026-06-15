# =============================================================================
#  backstage-snow-poc — single image, batteries included
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

# Do NOT corepack enable here — let create-app decide which yarn it wants
WORKDIR /build

RUN npx --yes @backstage/create-app@latest \
    --skip-install \
    --path /build/app \
    --name backstage-snow-poc

WORKDIR /build/app

# ── PROBE: show us the exact scaffold state before touching anything ──────────
RUN echo "=== yarn version ===" && yarn --version && \
    echo "=== .yarnrc.yml ===" && (cat .yarnrc.yml 2>/dev/null || echo "NOT FOUND") && \
    echo "=== .yarnrc ===" && (cat .yarnrc 2>/dev/null || echo "NOT FOUND") && \
    echo "=== package.json scripts ===" && node -e "const p=require('./package.json');console.log(JSON.stringify(p.scripts,null,2))" && \
    echo "=== package.json packageManager ===" && node -e "const p=require('./package.json');console.log(p.packageManager||'NOT SET')" && \
    echo "=== top-level files ===" && ls -la && \
    echo "=== packages/ ===" && ls packages/ && \
    echo "=== packages/backend/package.json scripts ===" && node -e "const p=require('./packages/backend/package.json');console.log(JSON.stringify(p.scripts,null,2))"

CMD ["bash"]
