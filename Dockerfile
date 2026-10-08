# Imagen del demo "Examen de Licencia de Héroe"
# Etapa 1 instala dependencias y corre los tests; la etapa final solo lleva lo necesario.

# ── Etapa 1: build y tests ─────────────────────────────────────────────
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY src ./src
COPY public ./public
COPY test ./test
RUN npm test

# Deja solo las dependencias de producción para la etapa final.
RUN npm prune --omit=dev

# ── Etapa 2: runtime ───────────────────────────────────────────────────
FROM node:22-alpine
ENV NODE_ENV=production \
    PORT=8080
WORKDIR /app

COPY --from=build --chown=node:node /app/package.json ./
COPY --from=build --chown=node:node /app/node_modules ./node_modules
COPY --from=build --chown=node:node /app/src ./src
COPY --from=build --chown=node:node /app/public ./public

# La imagen oficial de Node trae el usuario "node" (no root).
USER node
EXPOSE 8080
CMD ["node", "src/server.js"]
