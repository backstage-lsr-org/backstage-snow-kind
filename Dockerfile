# =============================================================================
#  backstage-snow-poc — single image, batteries included
#
#  Strategy: use the Dockerfile that @backstage/create-app generates at
#  packages/backend/Dockerfile — it is guaranteed correct for the version
#  installed. We extend it by also baking in the SNow mock.
# =============================================================================

# ── Stage 1: ServiceNow mock ─────────────────────────────────────────────────
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# ── Stage 2: scaffold Backstage + patch + build ───────────────────────────────
FROM node:20-bookworm-slim AS backstage-build

ENV PYTHON=/usr/bin/python3
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 make g++ git curl ca-certificates build-essential libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Scaffold — create-app 0.7.x is interactive; pipe the name via stdin
RUN echo "backstage-snow-poc" | npx --yes @backstage/create-app@latest --skip-install 2>&1 | tail -5

WORKDIR /build/backstage-snow-poc

# Install all deps with whichever yarn version the scaffold chose
RUN yarn install --immutable 2>&1 | tail -10

# Add the Roadie ServiceNow plugin
RUN yarn --cwd packages/app add @roadiehq/backstage-plugin-servicenow 2>&1 | tail -5

# Patch our custom files
COPY backstage/app-config.yaml        ./app-config.production.yaml
COPY backstage/catalog/               ./catalog/
COPY backstage/patches/EntityPage.tsx ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx        ./packages/app/src/App.tsx

# tsc is required before the backend build
RUN yarn tsc 2>&1 | tail -5

# Run the build — capture full output AND always print filesystem state after
# Use `|| true` so we see the find output even if build fails
RUN yarn build:backend --config app-config.production.yaml 2>&1 || true

# ALWAYS print what was produced (exit 1 forces Docker to show this layer's output)
RUN echo "BUILD OUTPUT SURVEY:" && \
    echo "--- tarballs ---" && find . -name "*.tar.gz" -not -path "*/node_modules/*" 2>/dev/null | sort || true && \
    echo "--- dist dirs ---" && find . -name "dist" -not -path "*/node_modules/*" 2>/dev/null | sort || true && \
    echo "--- packages/backend tree ---" && find packages/backend -not -path "*/node_modules/*" 2>/dev/null | sort && \
    echo "--- done ---" && \
    false

