# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY index.html vite.config.js ./
COPY src ./src
COPY public ./public
COPY scripts ./scripts
RUN npm run build

FROM node:22-alpine AS production
ENV NODE_ENV=production HOST=127.0.0.1 PORT=8787
WORKDIR /app
# LAN discovery and MAC lookup; no Flutter/build tooling in the runtime image.
RUN apk add --no-cache iproute2 iputils net-tools
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=build --chown=node:node /app/dist ./dist
COPY --chown=node:node server ./server
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["node", "server/healthcheck.mjs"]
CMD ["node", "server/server.mjs"]
