*This project has been created as part of the 42 curriculum by aluque-v.*

# Inception

## Description

Inception is a system administration project: set up a small web infrastructure
made of several services, each one running in its own Docker container, built from
my own Dockerfiles and orchestrated with Docker Compose inside a virtual machine.
The goal is to understand how containers, images, networks, volumes and secrets
work together, instead of just running ready-made images.

The stack serves a WordPress website over HTTPS:

- **NGINX**: the only entrypoint to the infrastructure, listening on port **443**
  with **TLSv1.2 / TLSv1.3** only (self-signed certificate).
- **WordPress + php-fpm**: runs the PHP application. Installed and configured
  automatically with WP-CLI. No web server inside this container.
- **MariaDB**: the database used by WordPress. No web server inside this container.
- **2 named volumes**: one for the database, one for the WordPress files, both
  stored on the host in `/home/<login>/data`.
- **1 bridge network** (`inception`) connecting the three containers.
- **Docker secrets** for every password. Non-sensitive config lives in `srcs/.env`.

```
            HTTPS :443
 browser ───────────────► nginx ──── fastcgi :9000 ───► wordpress ──── :3306 ───► mariadb
                            │                              │                         │
                            └──── wordpress_data ──────────┘                    mariadb_data
                                    (shared volume)
```

## Instructions

### Prerequisites

- A Linux virtual machine (Debian 13 recommended), with a browser to open the site.
- Docker Engine and the Docker Compose v2 plugin (`docker compose`, with a space).
- `make` and `sudo` (`make fclean` needs `sudo` to delete the data folder,
  because MariaDB writes files owned by another UID).
- Your user in the `docker` group, so Docker works without `sudo`.

### Configuration

1. Point the domain to the machine by adding this line to `/etc/hosts`:

   ```
   127.0.0.1   aluque-v.42.fr
   ```

2. Create `srcs/.env` with the non-sensitive configuration (domain, data path,
   database name, WordPress usernames and emails). Every variable is described in
   [DEV_DOC.md](DEV_DOC.md#configuration-file-srcsenv).

3. Create the `secrets/` folder at the root of the repo with one password per file:
   `db_root_password.txt`, `db_password.txt`, `wp_admin_password.txt`,
   `wp_user_password.txt`. See [DEV_DOC.md](DEV_DOC.md#secrets-secrets).

Neither `srcs/.env` nor `secrets/` is committed to Git.

### Build & run

```sh
make        # create the data folders, build the 3 images and start the containers
make down   # stop and remove the containers (images, volumes and data are kept)
make clean  # down + remove the images and the Docker volumes (host data is kept)
make fclean # clean + delete the data folder on the host (full reset, uses sudo)
make re     # fclean + make: rebuild everything from zero
```

Then open **https://aluque-v.42.fr** (the site) or
**https://aluque-v.42.fr/wp-admin** (the admin panel). The browser will warn about
the self-signed certificate: this is expected, accept it to continue.

## Project description

### Use of Docker

Each service has its own image, built from a Dockerfile I wrote in
`srcs/requirements/<service>/`. No ready-made image from Docker Hub is used for the
services: the only thing pulled is the base image `alpine:3.23`. Each image is
named after its service (`mariadb:inception`, `wordpress:inception`,
`nginx:inception`).

Docker Compose (`srcs/docker-compose.yml`) describes the whole infrastructure in one
file: the three services, how to build them, the network that connects them, the
two volumes, the secrets each service receives, the start order and the restart
policy (`restart: always`, so a container that crashes is started again). The
Makefile is a thin wrapper around Compose that also creates the host data folders.

### Sources included

| Path | Purpose |
|---|---|
| `Makefile` | Entry point: creates the data folders and calls `docker compose` (`up`, `down`, `clean`, `fclean`, `re`) |
| `srcs/docker-compose.yml` | Defines the 3 services, the `inception` network, the 2 volumes and the 4 secrets |
| `srcs/.env` | Non-sensitive configuration (domain, data path, DB name, usernames, emails). Not versioned |
| `srcs/requirements/mariadb/` | MariaDB image: Dockerfile, server config (`conf/`), first-run DB/user setup (`tools/entrypoint.sh`) |
| `srcs/requirements/wordpress/` | WordPress image: php-fpm 8.4 + WP-CLI, pool config listening on `:9000`, install script |
| `srcs/requirements/nginx/` | NGINX image: TLS-only server config, script that generates the self-signed certificate |
| `secrets/` | One password per file, mounted as Docker secrets. Not versioned |

### Main design choices

1. **Base image**: `alpine:3.23` for all services.
    - **What:** a pinned version, never `latest`.
    - **Why:** the subject forbids `latest` and requires the penultimate stable version
      of Alpine or Debian. Alpine weighs ~8 MB, builds fast and ships fewer packages,
      which also means a smaller attack surface.
    - **Trade-off:** Alpine uses `musl` instead of `glibc`, and some package names are
      less intuitive (`php84-*`). Alpine was chosen for its size and simplicity.

2. **Entrypoint pattern**: `ENTRYPOINT` + script + `exec`.
    - **What:** each service has a `tools/entrypoint.sh` that sets up everything
      needed and ends with `exec <daemon>`.
    - **Why `exec`:** it replaces the shell, so the daemon becomes PID 1. It receives
      the `SIGTERM` sent by `docker stop` and shuts down cleanly. Otherwise PID 1 would
      be `sh`, which doesn't forward signals, and Docker would end up killing it with
      `SIGKILL` after 10 seconds.
    - **Foreground processes:** `daemon off;` (NGINX), `php-fpm84 -F` and `mariadbd`
      all run in the foreground without forking. The subject forbids hacks such as
      `tail -f`, `sleep infinity` or `while true`.
    - **`set -e`:** if any initialization step fails, the container exits instead of
      starting in a half-configured state.

3. **Skip initialization**: setup only runs on the first start.
    - **What:** each entrypoint checks for a marker before initializing:
        - MariaDB: the `/var/lib/mysql/mysql` system directory (created by
          `mariadb-install-db`).
        - WordPress: the `wp-config.php` file in `/var/www/html`.
        - NGINX: the certificate file `/etc/nginx/ssl/inception.crt`.
    - **Why:** containers can be stopped and recreated (`make down` / `make`) without
      losing data or trying to create the database, the users or the WordPress
      install twice.
    - **Consequence:** changing a secret after the first run has no effect, because
      the password is already stored in the database. To apply a new password, change
      it inside the app (or in SQL), or reset everything with `make fclean && make`.

4. **MariaDB bootstrap with a temporary server**.
    - **What:** on the first run, the entrypoint starts `mariadbd --skip-networking`
      in the background, waits until it answers, creates the database and the user,
      sets the root password, then stops it and starts the real server with `exec`.
    - **Why:** SQL commands need a running server, but the final server must be PID 1.
      `--skip-networking` makes sure nobody can connect from the network while root
      still has no password.

5. **Healthcheck + `depends_on: service_healthy`**.
    - **What:** MariaDB has a healthcheck (`mariadb-admin ping`), and WordPress only
      starts once MariaDB is reported `healthy`. NGINX starts after WordPress.
    - **Why:** a plain `depends_on` only waits for the container to *start*, not for
      the database to *accept connections*. Without the healthcheck, `wp core install`
      could run against a database that isn't ready yet and fail.

6. **WordPress installed with WP-CLI at runtime**.
    - **What:** the image only contains php-fpm and the `wp` binary. WordPress itself
      is downloaded, configured and installed by the entrypoint the first time, into
      the `wordpress_data` volume.
    - **Why:** the whole install is scripted and reproducible (no manual setup wizard),
      and the files end up in the volume, where NGINX can also read them.
    - **Admin username check:** the entrypoint refuses to start if `WP_ADMIN_USER`
      contains `admin`, as required by the subject.

7. **NGINX as the only entrypoint**.
    - **What:** only NGINX publishes a port (`443:443`). It serves static files from
      the shared volume and forwards `.php` requests to `wordpress:9000` with FastCGI.
    - **Why:** a single, TLS-only door into the infrastructure. `ssl_protocols TLSv1.2
      TLSv1.3;` rejects older protocols, and there is no listener on port 80.

### Virtual Machines vs Docker

A **virtual machine** emulates a full computer: a hypervisor runs a complete guest OS
with its own kernel on top of virtualized hardware. A **Docker container** is just an
isolated process on the host: it shares the host kernel and is isolated by Linux
namespaces (PID, network, mount...) and limited by cgroups.

| | Virtual Machine | Docker container |
|---|---|---|
| Isolation | Strong (separate kernel) | Process-level (shared kernel) |
| Boot time | Minutes | Seconds or less |
| Size | GBs (full OS) | MBs (only userland + app) |
| Resource overhead | High (reserved RAM/CPU) | Low |
| Portability | Heavy disk images | Image built from a Dockerfile, reproducible anywhere |

**In this project** both are used: the VM gives an isolated, disposable machine to
work on, and inside it each service runs in its own lightweight container. One
service per container keeps each one simple, replaceable and independently restartable.

### Secrets vs Environment Variables

**Environment variables** are easy to use but leak easily: they show up in
`docker inspect`, are inherited by every child process, and often end up in logs
or in the image history. **Docker secrets** are files mounted read-only in
`/run/secrets/<name>` and only in the containers that declare them.

| | Environment variables | Docker secrets |
|---|---|---|
| Visible in `docker inspect` | Yes | No (only the path) |
| Scope | Whole container + child processes | Only services that declare them |
| Storage in container | Process environment | Read-only file in `/run/secrets/` |
| Good for | Non-sensitive config | Passwords, keys, tokens |

**In this project**, non-sensitive config (domain name, DB name, usernames, emails)
lives in `srcs/.env`. Every password lives in `secrets/*.txt`, and each entrypoint
reads it with `cat /run/secrets/...` at runtime. MariaDB only gets the DB passwords,
WordPress only gets what it needs, and NGINX gets no secrets at all. Neither `.env` nor
`secrets/` is committed to Git.

### Docker Network vs Host Network

With the **host network** (`network_mode: host`), a container shares the host's
network stack: every port it opens is directly exposed on the machine and there is
no isolation between containers. A user-defined **Docker bridge network** creates a
private virtual network: containers get their own IPs, reach each other **by service
name** through Docker's embedded DNS, and nothing is reachable from outside unless
it is explicitly published with `ports:`.

| | Host network | Docker bridge network |
|---|---|---|
| Isolation | None (shares host stack) | Private network per project |
| Service discovery | `localhost` / host IPs | DNS by service name (`mariadb`, `wordpress`) |
| Exposed ports | Everything the process opens | Only what is in `ports:` |
| Port conflicts | With the host and other containers | None internally |

**In this project** all three services are on the `inception` bridge network
(`network: host`, `links` and `--link` are forbidden by the subject). Only NGINX
publishes a port (`443:443`). WordPress reaches MariaDB at `mariadb:3306` and NGINX
reaches php-fpm at `wordpress:9000`, but neither port is reachable from the host.

### Docker Volumes vs Bind Mounts

A **bind mount** mounts an arbitrary host path into the container. It depends on
the host's directory layout and permissions, and Docker doesn't manage it. A
**named volume** is a storage object managed by Docker (`docker volume ls/inspect/rm`).
It is declared in the compose file, has a name, and can be shared between services.

| | Bind mount | Named volume |
|---|---|---|
| Managed by Docker | No | Yes (`docker volume ...`) |
| Defined by | A host path | A name (+ optional driver options) |
| Location on host | Wherever you point it | `/var/lib/docker/volumes/` by default |
| Typical use | Dev: live-editing source code | Persistent app data (DBs, uploads) |

**In this project** the subject requires named volumes and data stored in
`/home/<login>/data`. So `mariadb_data` and `wordpress_data` are named volumes using
the `local` driver with `driver_opts` (`type: none`, `o: bind`,
`device: ${DATA_PATH}/...`). Docker manages them as volumes, but the data physically
lives in `$DATA_PATH`. That's why the Makefile creates those directories before `up`.
`wordpress_data` is mounted in both WordPress (to write files) and NGINX (to serve static files).

## Resources

### Documentation & references

- [Docker docs](https://docs.docker.com/)
- [Dockerfile reference](https://docs.docker.com/reference/dockerfile/)
- [Compose file reference](https://docs.docker.com/reference/compose-file/)
- [Compose: secrets](https://docs.docker.com/compose/how-tos/use-secrets/)
- [Compose: volumes (`driver_opts`)](https://docs.docker.com/reference/compose-file/volumes/)
- [Compose: startup order and healthchecks](https://docs.docker.com/compose/how-tos/startup-order/)
- [Docker networking (bridge)](https://docs.docker.com/engine/network/drivers/bridge/)
- [Alpine Linux packages](https://pkgs.alpinelinux.org/packages)
- [NGINX docs](https://nginx.org/en/docs/) and
  [`ngx_http_ssl_module`](https://nginx.org/en/docs/http/ngx_http_ssl_module.html)
- [NGINX `ngx_http_fastcgi_module`](https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/) (`mariadb-install-db`, `CREATE USER`, `GRANT`)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/) (`core download`, `config create`, `core install`, `user create`)
- [OpenSSL `req`](https://docs.openssl.org/master/man1/openssl-req/)

### AI usage

AI (Claude) was used as a learning and review assistant, not to generate the project:

- **Learning / explanations:** understanding Docker concepts (PID 1 and `exec`,
  namespaces vs VMs, secrets, named volumes with `driver_opts`, bridge networks)
  and the role of each service (php-fpm vs NGINX, FastCGI).
- **Roadmap:** drafting a personal step-by-step study guide for the project,
  with links to the official documentation for each step.
- **Review / debugging:** reviewing the Compose file and entrypoint scripts, and
  helping interpret error logs during testing.
- **Documentation:** drafting the structure and first version of `README.md`,
  `USER_DOC.md` and `DEV_DOC.md`, which I then reviewed and rewrote.

All Dockerfiles, configuration files and scripts were written and tested by me,
and checked against the official documentation listed above.
