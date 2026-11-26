*This project has been created as part of the 42 curriculum by aluque-v.*

# Inception

## Description

Small web infrastructure running in Docker inside a VM: a WordPress site served over
HTTPS, with each service in its own container built from my own Dockerfiles
(base image `alpine:3.23`) and managed with Docker Compose.

- **nginx**: only entrypoint, port 443, TLSv1.2/1.3, self-signed certificate.
- **wordpress**: php-fpm 8.4 + WP-CLI, no web server.
- **mariadb**: the database, no web server.
- 2 named volumes (DB and WordPress files) stored in `/home/<login>/data`.
- 1 bridge network (`inception`).
- Passwords as Docker secrets, the rest of the config in `srcs/.env`.

```
browser --443--> nginx --9000--> wordpress --3306--> mariadb
```

## Instructions

Requirements: a Linux VM with Docker, the Compose plugin, `make` and `sudo`
(`fclean` needs it because MariaDB files belong to another UID).

1. Add `127.0.0.1 aluque-v.42.fr` to `/etc/hosts`.
2. Create `srcs/.env` (domain, data path, DB name, users, emails).
3. Create `secrets/` with `db_root_password.txt`, `db_password.txt`,
   `wp_admin_password.txt` and `wp_user_password.txt`.

Details for both files are in [DEV_DOC.md](DEV_DOC.md). Neither is in the repo.

```sh
make        # create data folders, build and start
make down   # stop containers
make clean  # down + remove images and volumes
make fclean # clean + delete host data
make re     # fclean + make
```

Then go to https://aluque-v.42.fr (admin panel at `/wp-admin`) and accept the
certificate warning.

## Project description

Each service has its own Dockerfile in `srcs/requirements/<service>/`, with a
`conf/` folder and a `tools/entrypoint.sh`. The compose file defines the services,
network, volumes, secrets and `restart: always`. The Makefile just wraps Compose.

Some decisions worth explaining:

- **Alpine 3.23**: small and quick to build. The subject forbids `latest`, so the
  version is pinned.
- **`exec` at the end of each entrypoint**, so the daemon is PID 1 and gets the
  SIGTERM from `docker stop`. Everything runs in the foreground (`daemon off;`,
  `php-fpm84 -F`, `mariadbd`), no `tail -f` or infinite loops.
- **Setup only on the first start**: each script checks for something that already
  exists (`/var/lib/mysql/mysql`, `wp-config.php`, the certificate) and skips the
  setup. Because of this, changing a secret later does nothing unless you run
  `make fclean`.
- **MariaDB first run**: a temporary `mariadbd --skip-networking` is started to
  create the DB, user and root password, then stopped before launching the real one.
- **Healthcheck**: WordPress waits until MariaDB is `healthy`, otherwise
  `wp core install` could run before the DB accepts connections.
- **WordPress is downloaded and installed by WP-CLI at runtime** into the volume,
  so nginx can read the same files. The script stops if the admin username
  contains "admin".

### Virtual Machines vs Docker

A VM runs a full OS with its own kernel on virtual hardware. A container is a
process on the host, isolated with namespaces and limited with cgroups, sharing the
host kernel. Containers are much lighter and start in seconds, but isolation is
weaker. Here the VM is the work machine and each service is a container inside it.

### Secrets vs Environment Variables

Environment variables are visible in `docker inspect` and passed to every child
process. Secrets are read-only files in `/run/secrets/`, only in the containers that
ask for them. I use `.env` for normal config and secrets for passwords; nginx gets no
secrets at all.

### Docker Network vs Host Network

With `network_mode: host` the container uses the host network directly, with no
isolation. A bridge network is private: containers find each other by service name
and nothing is reachable from outside unless published. Only nginx publishes a port
(443); 9000 and 3306 stay internal.

### Docker Volumes vs Bind Mounts

A bind mount is any host path mounted in the container, not managed by Docker. A
named volume is managed by Docker (`docker volume ...`). The subject asks for named
volumes stored in `/home/<login>/data`, so I use the `local` driver with
`type: none, o: bind, device: ${DATA_PATH}/...`. That's why the Makefile creates
those folders first.

## Resources

- [Docker docs](https://docs.docker.com/) and the
  [Compose file reference](https://docs.docker.com/reference/compose-file/)
  (secrets, volumes, startup order)
- [Alpine packages](https://pkgs.alpinelinux.org/packages)
- [NGINX docs](https://nginx.org/en/docs/) (ssl and fastcgi modules)
- [MariaDB Knowledge Base](https://mariadb.com/kb/en/)
- [PHP-FPM configuration](https://www.php.net/manual/en/install.fpm.configuration.php)
- [WP-CLI commands](https://developer.wordpress.org/cli/commands/)

**AI usage:** I used Claude to understand concepts (PID 1, namespaces, secrets,
volumes, FastCGI), to make a study plan, to review my compose file and scripts and
help read error logs, and to get a first structure for the docs, which I then
rewrote. The Dockerfiles, configs and scripts are my own.
