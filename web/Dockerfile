# syntax=docker/dockerfile:1

# ---- Build stage: build the SPA and bundle the server ----
FROM node:24-alpine AS build
WORKDIR /app
ENV CI=1
RUN corepack enable
# Copy workspace manifests + lockfile first so deps are cached across source changes.
COPY package.json pnpm-workspace.yaml pnpm-lock.yaml ./
COPY web-ui/package.json web-ui/package.json
COPY server/package.json server/package.json
COPY contracts/package.json contracts/package.json
RUN pnpm install --frozen-lockfile
# Copy the rest of the source and build both packages.
COPY web-ui/ web-ui/
COPY server/ server/
COPY contracts/ contracts/
RUN pnpm --filter @planner/web-ui build && pnpm --filter @planner/web-server build

# ---- Runtime stage: one image serves the SPA and the API on one origin ----
FROM node:24-alpine
WORKDIR /app
ENV NODE_ENV=production
# A fixed uid/gid matches the workload security context and needs no writable home.
RUN addgroup -S -g 10001 planner && adduser -S -D -H -u 10001 -G planner planner
# The built SPA, served at '/'. serveStatic resolves this relative to cwd.
ENV SPA_DIST=/app/web-ui/dist
# The bundled server is self-contained and writes only to stdout/stderr, so the
# runtime works with a read-only root filesystem.
COPY --from=build --chown=10001:10001 /app/web-ui/dist /app/web-ui/dist
COPY --from=build --chown=10001:10001 /app/server/dist /app/server/dist
# Configuration is never baked into the image. Required at runtime:
#   VITE_GOOGLE_CLIENT_ID, GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET,
#   SESSION_COOKIE_KEY (64 hex chars), APP_VERSION
USER 10001:10001
EXPOSE 3000
CMD ["node", "server/dist/index.js"]
