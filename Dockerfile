# =============================================================================
#  backstage-snow-poc — host-build pattern
#
#  IMPORTANT: Do not run `docker build .` directly on this file.
#  Run ./build.sh instead — it scaffolds, installs, and builds on the host
#  first (which produces packages/backend/dist/skeleton.tar.gz and bundle.tar.gz),
#  then calls docker build with the correct context.
#
#  To build and push:
#    ./build.sh --push yourname/backstage-snow-poc
# =============================================================================

# ── Stage 1: ServiceNow mock ─────────────────────────────────────────────────
FROM node:20-alpine AS mock-build
WORKDIR /mock
COPY mock/package.json .
RUN npm install --omit=dev
COPY mock/server.js .

# ── Stage 2: Backstage runtime (host already ran yarn build:backend) ──────────
FROM node:20-bookworm-slim AS backstage

ENV PYTHON=/usr/bin/python3
ENV NODE_ENV=production
ENV NODE_OPTIONS="--no-node-snapshot"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3 g++ build-essential libsqlite3-dev && \
    rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /app

# Yarn config files (required by yarn workspaces focus)
COPY --chown=node:node .yarn          ./.yarn
COPY --chown=node:node .yarnrc.yml    ./ 
COPY --chown=node:node backstage.json ./

# skeleton.tar.gz restores the packages/*/package.json tree for yarn install
COPY --chown=node:node yarn.lock package.json packages/backend/dist/skeleton.tar.gz ./
RUN tar xzf skeleton.tar.gz && rm skeleton.tar.gz

# Install only production deps
RUN yarn workspaces focus --all --production 2>&1 | tail -5

# Catalog is read at runtime, not bundled
COPY --chown=node:node catalog/ ./catalog/

# bundle.tar.gz contains the compiled backend + embedded frontend assets
COPY --chown=node:node packages/backend/dist/bundle.tar.gz app-config.production.yaml ./
RUN tar xzf bundle.tar.gz && rm bundle.tar.gz && \
    mv app-config.production.yaml app-config.yaml

# ── Stage 3: final image with mock baked in ───────────────────────────────────
FROM backstage AS final

USER root
WORKDIR /mock
COPY --from=mock-build /mock ./

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER node
WORKDIR /app

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]
