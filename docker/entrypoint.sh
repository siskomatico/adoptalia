#!/bin/sh
# Arranca como root solo para dejar los uploads escribibles y baja a "node".
# Necesario en LXC de Proxmox (OCI): el punto de montaje nuevo pertenece a root.
set -e
UPLOADS=/app/public/uploads
if [ "$(id -u)" = 0 ]; then
  mkdir -p "$UPLOADS/imagenes" "$UPLOADS/perfiles"
  chown -R node:node "$UPLOADS"
  exec su-exec node "$@"
fi
exec "$@"
