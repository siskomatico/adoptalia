# Despliegue en Proxmox OCI (ProxMenux)

Imagen única (`Dockerfile` en la raíz): Express sirve la API, los uploads y el frontend Angular compilado.
MySQL va en su propio contenedor con la imagen oficial. `compose.yaml` (nginx + backend) sigue funcionando igual.

## Contenedores

| Contenedor | Imagen | Puerto | Volumen |
|---|---|---|---|
| adoptalia-app | `ghcr.io/siskomatico/adoptalia:latest` (este Dockerfile, paquete privado) | 3000 | `/app/public/uploads` |
| adoptalia-db | `mysql:8.0.45` (oficial, fijada por digest) | 3306 | `/var/lib/mysql` |

Se instalan con **ProxMenux → OCI manager Apps → Install an image that is not in the catalog → Read an oci-compose from a file of this host**, en modo avanzado y con IP fija:

- [docker/oci-compose.adoptalia-db.json](../docker/oci-compose.adoptalia-db.json): primero, y restaurar el volcado.
- [docker/oci-compose.adoptalia-app.json](../docker/oci-compose.adoptalia-app.json): después. Su comprobación de arranque (`/api/health/ready`) necesita la base de datos restaurada.

MySQL arranca sin `--collation-server` (el oci-compose no admite argumentos). Las tablas del volcado llevan su collation explícita, y tras restaurar se ejecuta `ALTER DATABASE adoptalia_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci` para que las tablas nuevas la hereden.

## Variables de adoptalia-app

| Variable | Valor |
|---|---|
| `DB_HOST` | IP de adoptalia-db |
| `DB_USER`, `DB_PASSWORD`, `DB_NAME` | las de MySQL |
| `JWT_SECRET` | mínimo 32 caracteres (el mismo de ahora, para no cerrar sesiones) |
| `TRUST_PROXY` | IP de cloudflared (`100.10.10.5`). La red de casa no es un rango privado, así que `uniquelocal` no la cubre |
| `CORS_ORIGINS` | vacío (mismo origen) |
| `WEB_DIR` | ya viene en la imagen (`/app/web`). Si se vacía, vuelve al modo clásico detrás de nginx |

## Variables de adoptalia-db

`MYSQL_ROOT_PASSWORD`, `MYSQL_DATABASE`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_INITDB_SKIP_TZINFO=1`.
Arranque con `--character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci`.

## Lo que hacía Docker y ahora hay que hacer a mano

- **Red aislada de la base de datos:** firewall de Proxmox en adoptalia-db que solo deje entrar al 3306 desde la IP de adoptalia-app.
- **Orden de arranque** (sustituye a los healthchecks y `depends_on`): `startup: order=1,up=30` en la db, `order=2` en la app.
- **`init: true`:** la imagen ya trae `tini`.
- **Permisos de uploads:** el entrypoint arranca como root, hace `chown` del volumen y baja al usuario `node`.

## Migración de datos

1. Volcado: `docker exec adoptalia-prod-db-1 mysqldump --single-transaction --routines --triggers -uroot -p adoptalia_db > adoptalia.sql`
2. Restaurar en adoptalia-db: `mysql -uroot -p adoptalia_db < adoptalia.sql`
3. Copiar `data/uploads/` al volumen `/app/public/uploads` de adoptalia-app.

## Prueba local

```bash
docker build -t adoptalia-oci:test .
python3 scripts/smoke-test.py --url http://127.0.0.1:18080 --allow-test-data
```
