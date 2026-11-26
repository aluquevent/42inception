# Developer Documentation

This document explains how to set up the project from scratch, build and run it,
manage the containers and volumes, and where the data lives.

## 1. Set up the environment from scratch

### Prerequisites

- **VM / OS:** a Linux virtual machine with a
  browser or port-fowarding enabled. Ideally the VM user is your 42 login, so `/home/<login>` is your home.
- **Docker + Compose plugin:** install the necessary packages (docker docker-cli docker-cli-compose for Alpine)

  ```sh
  sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ```

  Compose v2 is required (`docker compose`, with a space), not the old
  `docker-compose` binary. Check with `docker --version` and `docker compose version`.
- **make, sudo, git:** `sudo apt install make git`.
- **User in the `docker` group**, so Docker runs without `sudo`:

  ```sh
  sudo usermod -aG docker $USER   # then log out and back in
  ```

Then clone the repository inside the VM:

```sh
git clone <repo-url> ~/inception && cd ~/inception
```

### Domain

The site is served on `<login>.42.fr`, which must resolve to the machine. There is
no real DNS: add it to `/etc/hosts` on the machine where the browser runs.

```sh
echo "127.0.0.1 aluque-v.42.fr" | sudo tee -a /etc/hosts
getent hosts aluque-v.42.fr   # should print: 127.0.0.1 aluque-v.42.fr
```

### Configuration file: `srcs/.env`

Not versioned (ignored in `.gitignore`). It holds **non-sensitive** configuration
only. It is used twice: Compose passes it to the containers (`env_file: .env`) and
reads `DATA_PATH` from it for the volume paths, and the Makefile `include`s it to
know where to create the data folders.

| Variable | Description | Example |
|---|---|---|
| `DOMAIN_NAME` | Domain served by NGINX, used in the certificate CN and as the WordPress URL | `aluque-v.42.fr` |
| `DATA_PATH` | Host folder where both volumes store their data (subject: `/home/<login>/data`) | `/home/aluque-v/data` |
| `MYSQL_DATABASE` | Name of the database created for WordPress | `wordpress` |
| `MYSQL_USER` | MariaDB user WordPress connects with (has all privileges on `MYSQL_DATABASE` only) | `wp_user` |
| `WP_TITLE` | Title of the WordPress site | `Inception` |
| `WP_ADMIN_USER` | WordPress administrator username. Can't contain "admin" (the entrypoint refuses to start otherwise) | `aluque-v_master` |
| `WP_ADMIN_EMAIL` | Administrator email | `aluque-v_master@example.com` |
| `WP_USER` | Second WordPress user, created with the `author` role | `aluque-v_peer` |
| `WP_USER_EMAIL` | Email of the second user | `aluque-v_peer@example.com` |

Create it:

```sh
cat > srcs/.env << 'EOF'
DOMAIN_NAME=aluque-v.42.fr
DATA_PATH=/home/aluque-v/data

MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user

WP_TITLE=Inception

WP_ADMIN_USER=aluque-v_master
WP_ADMIN_EMAIL=aluque-v_master@example.com
WP_USER=aluque-v_peer
WP_USER_EMAIL=aluque-v_peer@example.com
EOF
```

### Secrets: `secrets/`

Not versioned. One password per file, at the root of the repo. Compose mounts each
one read-only in `/run/secrets/<name>` inside the services that declare it, and the
entrypoints read them with `cat`.

| File | Used by | Purpose |
|---|---|---|
| `db_root_password.txt` | mariadb | Password of MariaDB `root@localhost` |
| `db_password.txt` | mariadb, wordpress | Password of `MYSQL_USER` |
| `wp_admin_password.txt` | wordpress | Password of `WP_ADMIN_USER` |
| `wp_user_password.txt` | wordpress | Password of `WP_USER` |

Generate random ones:

```sh
mkdir -p secrets
for s in db_root_password db_password wp_admin_password wp_user_password; do
	openssl rand -base64 18 | tr -d '\n' > "secrets/$s.txt"
done
chmod 600 secrets/*.txt
```

`tr -d '\n'` avoids a trailing newline ending up inside the password.

## 2. Build and launch

```sh
make
```

That's all: it creates the data folders, then runs
`docker compose -f srcs/docker-compose.yml up -d --build`, which builds the three
images from `srcs/requirements/*/Dockerfile` and starts the containers in the background.

### Makefile targets

| Target | What it does |
|---|---|
| `make` / `make up` | Runs `dirs`, then `docker compose up -d --build` (build images + start containers in background) |
| `make dirs` | `mkdir -p $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress`: the volume paths must exist before `up` |
| `make down` | `docker compose down`: stops and removes containers and the network. Images, volumes and data are kept |
| `make clean` | `docker compose down --rmi all -v`: also removes the images and the Docker volume objects. Files in `$DATA_PATH` are **kept** (volumes are bind-backed) |
| `make fclean` | `clean` + `sudo rm -rf $(DATA_PATH)`: deletes all persistent data. `sudo` is needed because MariaDB files belong to the container's `mysql` UID |
| `make re` | `fclean` then `all`: full rebuild from zero |

### Startup order

1. **mariadb** starts first. Its healthcheck runs `mariadb-admin ping` every 5s
   (up to 10 retries) until the server answers, then the container becomes `healthy`.
2. **wordpress** has `depends_on: mariadb: condition: service_healthy`, so it only
   starts once the database accepts connections. On the first run it downloads
   WordPress, writes `wp-config.php`, installs the site and creates both users.
3. **nginx** has `depends_on: wordpress` and starts last. It generates its
   self-signed certificate if missing and starts listening on 443.

All services have `restart: always`.

### What each entrypoint does

| Service | First run only | Every start |
|---|---|---|
| mariadb | If `/var/lib/mysql/mysql` is missing: `mariadb-install-db`, start a temporary `--skip-networking` server, create DB + user, set root password, stop it | `exec mariadbd --user=mysql` |
| wordpress | If `wp-config.php` is missing: `wp core download`, `wp config create` (host `mariadb:3306`), `wp core install`, `wp user create` | Check `WP_ADMIN_USER` has no "admin", `chown` files to `nobody`, `exec php-fpm84 -F` |
| nginx | If the certificate is missing: `openssl req -x509` (RSA 2048, 365 days, CN = `$DOMAIN_NAME`) | Replace `__DOMAIN_NAME__` in `nginx.conf`, `exec nginx` (`daemon off;`) |

## 3. Managing containers and volumes

```sh
# State and logs
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f <service>   # mariadb | wordpress | nginx

# Shell inside a container (Alpine: sh, not bash)
docker exec -it <container> sh

# Volumes and network
docker volume ls
docker volume inspect mariadb_data        # check "device" points to $DATA_PATH/mariadb
docker network inspect inception          # the 3 containers and their IPs

# Images
docker images | grep inception
```

Rebuild and restart a single service after editing its files:

```sh
docker compose -f srcs/docker-compose.yml up -d --build <service>
```

Open the MariaDB client:

```sh
docker exec -it mariadb mariadb -u root -p          # root password: secrets/db_root_password.txt
docker exec -it mariadb mariadb -u <MYSQL_USER> -p <MYSQL_DATABASE>
```

Useful SQL checks: `SHOW DATABASES;`, `SELECT user, host FROM mysql.user;`,
`SELECT user_login FROM wp_users;` (inside the WordPress database).

Use WP-CLI inside the WordPress container:

```sh
docker exec -it wordpress wp user list --allow-root
```

Check TLS from the host:

```sh
openssl s_client -connect aluque-v.42.fr:443 -tls1_2 < /dev/null   # handshake OK
openssl s_client -connect aluque-v.42.fr:443 -tls1_1 < /dev/null   # must fail
```

## 4. Data storage and persistence

| Volume | Mounted in container at | Stored on host at |
|---|---|---|
| `mariadb_data` | `/var/lib/mysql` (mariadb) | `$DATA_PATH/mariadb` |
| `wordpress_data` | `/var/www/html` (wordpress and nginx) | `$DATA_PATH/wordpress` |

Both are **named volumes** using the `local` driver with
`driver_opts: { type: none, o: bind, device: ${DATA_PATH}/... }`. Docker manages
them as volumes (`docker volume ls`), but the files physically live in `$DATA_PATH`
on the host. The `device` folder must already exist, which is why `make dirs` runs
before `up`.

Lifecycle:

| Action | Containers | Images | Volume objects | Data in `$DATA_PATH` |
|---|---|---|---|---|
| `make down` | removed | kept | kept | **kept** |
| `make clean` | removed | removed | removed | **kept** |
| `make fclean` | removed | removed | removed | **deleted** |

Because the entrypoints only initialize when their marker is missing
(`/var/lib/mysql/mysql`, `wp-config.php`), a restart with existing data skips the
setup and reuses it. Consequences:

- Data survives `make down` / `make` and container crashes.
- Changing `srcs/.env` or `secrets/` after the first run does **not** update the
  existing database or users. To apply new values, run `make fclean && make`.
- After `make clean`, a new `make` re-creates the volume objects pointing at the same
  folders, so the old data comes back.

## 5. Project structure

```
.
├── Makefile                      # wrapper around docker compose + data dirs
├── README.md                     # project overview (graded)
├── USER_DOC.md                   # user / admin documentation
├── DEV_DOC.md                    # this file
├── secrets/                      # NOT versioned: one password per file
│   ├── db_root_password.txt
│   ├── db_password.txt
│   ├── wp_admin_password.txt
│   └── wp_user_password.txt
└── srcs/
    ├── .env                      # NOT versioned: non-sensitive config
    ├── docker-compose.yml        # services, network, volumes, secrets
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/mariadb-server.cnf   # datadir, socket, bind 0.0.0.0:3306
        │   └── tools/entrypoint.sh       # first-run DB/user setup + exec mariadbd
        ├── wordpress/
        │   ├── Dockerfile                # php84-fpm + extensions + WP-CLI
        │   ├── .dockerignore
        │   ├── conf/www.conf             # php-fpm pool, listen 0.0.0.0:9000
        │   ├── conf/zz-inception.ini     # PHP overrides (memory_limit)
        │   └── tools/entrypoint.sh       # WP-CLI install + exec php-fpm84 -F
        └── nginx/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/nginx.conf           # TLS 1.2/1.3 on 443, fastcgi to wordpress:9000
            └── tools/entrypoint.sh       # self-signed cert + exec nginx
```
