# syntax=docker/dockerfile:1
# Imagen única de adoptalia: el backend Express sirve también el frontend Angular compilado.
# Pensada para Proxmox OCI (ProxMenux), donde no hay Docker ni red interna entre contenedores.
# MySQL va en su propio contenedor con la imagen oficial.

# ── Frontend ──
FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914 AS web
WORKDIR /web
COPY frontend/package.json frontend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci
COPY frontend/ ./
RUN npm run build -- --configuration production

# ── Runtime ──
FROM node:22-alpine@sha256:fe4f6d74e20370acb04ad889077d14d0f64a9c8ea6a42bc60cddf1e844699914
# tini como PID 1 (reenvía SIGTERM y recoge zombis) y su-exec para bajar de root a "node".
# Van en la imagen porque Proxmox OCI no usa Docker y no existe "init: true".
RUN apk add --no-cache su-exec tini
ENV NODE_ENV=production PORT=3000 WEB_DIR=/app/web
WORKDIR /app
COPY backend/package.json backend/package-lock.json ./
RUN --mount=type=cache,target=/root/.npm npm ci --omit=dev && npm cache clean --force
COPY backend/ ./
COPY --from=web /web/dist/adoptalia-frontend/browser ./web
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN mkdir -p public/uploads/imagenes public/uploads/perfiles && chown -R node:node public/uploads
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s CMD wget -qO- http://127.0.0.1:3000/api/health/live || exit 1
# Proxmox importa StopSignal de la imagen; server.js hace el apagado ordenado con SIGTERM.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/sbin/tini", "-s", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["node", "server.js"]
