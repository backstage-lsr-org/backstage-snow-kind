# =============================================================================
# Stage 1 - ServiceNow Mock
# =============================================================================
FROM node:20-alpine AS mock-build

WORKDIR /mock

COPY mock/package.json .
RUN npm install --omit=dev

COPY mock/server.js .

# =============================================================================
# Stage 2 - Backstage Build
# =============================================================================
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

# Create Backstage app
RUN printf 'backstage-snow-poc\n' | \
    npx --yes @backstage/create-app@latest --skip-install

RUN mv /build/backstage-snow-poc /build/app

WORKDIR /build/app

# Install dependencies
RUN yarn install

# Install ServiceNow plugin
RUN yarn --cwd packages/app add @roadiehq/backstage-plugin-servicenow

# Custom files
COPY backstage/app-config.yaml ./app-config.production.yaml
COPY backstage/catalog ./catalog
COPY backstage/patches/EntityPage.tsx ./packages/app/src/components/catalog/EntityPage.tsx
COPY backstage/patches/App.tsx ./packages/app/src/App.tsx

# Build
RUN yarn build

# Verify output exists
RUN ls -la packages/backend && \
    ls -la packages/backend/dist

# =============================================================================
# Stage 3 - Runtime
# =============================================================================
FROM node:20-bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

ENV NODE_ENV=production

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

# Entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 7007 8181

ENTRYPOINT ["/entrypoint.sh"]