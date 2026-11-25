# User Documentation

This document explains how to use the Inception stack: what it provides, how to
start and stop it, how to reach the website, where the credentials are and how to
check that everything works. No Docker knowledge is needed beyond copying commands.

All commands are run from the root of the repository.

## 1. Services provided

The stack hosts a **WordPress website served over HTTPS**. It is made of three
services, each in its own container:

| Service | Role | Reachable from outside? |
|---|---|---|
| NGINX | Web server and the only entrypoint. Handles HTTPS (TLSv1.2/1.3) and forwards PHP requests to WordPress | Yes, only on port **443** (HTTPS) |
| WordPress (php-fpm) | Runs the WordPress site and its admin panel | No, only through NGINX |
| MariaDB | Database storing posts, pages, users and settings | No, only WordPress can reach it |

The data (database + website files) is kept on the machine in
`/home/<login>/data`, so it survives restarts.

## 2. Start and stop the project

```sh
make        # start: build the images (if needed) and start the 3 containers
make down   # stop: stop and remove the containers, all data is kept
```

The first `make` takes a bit longer: it builds the images, downloads WordPress and
initializes the database. Later starts reuse the existing data.

Other commands, use them with care:

| Command | What happens | Website data |
|---|---|---|
| `make down` | Stops the containers | **Kept** |
| `make clean` | Stops the containers, deletes the images and the Docker volumes | **Kept** (files stay in `/home/<login>/data`) |
| `make fclean` | `clean` + deletes `/home/<login>/data` (asks for your `sudo` password) | **Deleted**: posts, users and settings are lost |
| `make re` | `fclean` + `make`: fresh install from zero | **Deleted**, then a new empty site is created |

## 3. Access the website and the administration panel

- Website: `https://aluque-v.42.fr`
- Admin panel: `https://aluque-v.42.fr/wp-admin`

Log into the admin panel with the WordPress administrator username (`WP_ADMIN_USER`
in `srcs/.env`) and its password (`secrets/wp_admin_password.txt`). A second,
non-admin user (`WP_USER`, role *author*) can log in too and write posts.

Things to know:

- **Certificate warning:** the site uses a self-signed certificate, so the browser
  shows a "Your connection is not private" warning. This is expected. Click
  *Advanced* → *Accept the risk / Proceed* to continue.
- **Only HTTPS works.** `http://aluque-v.42.fr` (port 80) is refused on purpose.
- **The domain must point to the machine.** If the browser can't find the site,
  check that `/etc/hosts` contains:

  ```
  127.0.0.1   aluque-v.42.fr
  ```

  (If you browse from another computer, use the VM's IP address instead of `127.0.0.1`.)

## 4. Credentials

Passwords are stored in files, never in the code. **Never write real passwords in
this document or commit them to Git.**

| Credential | Location |
|---|---|
| MariaDB root password | `secrets/db_root_password.txt` |
| MariaDB user password | `secrets/db_password.txt` |
| WordPress admin password | `secrets/wp_admin_password.txt` |
| WordPress user password | `secrets/wp_user_password.txt` |
| Usernames / emails | `srcs/.env` |

To read one:

```sh
cat secrets/wp_admin_password.txt
```

### Changing a password

The passwords are only read **the first time** the stack is installed. After that
they are stored inside the database, so editing the file alone changes nothing.
Two options:

- **Keep the site:** change the password from the admin panel
  (*Users* → *Profile* → *Set New Password*). Then also update the file in
  `secrets/` so it stays the reference.
- **Start over:** edit the file, then run `make fclean && make`.
  ⚠ This deletes all the website content.

## 5. Check that services are running

```sh
docker compose -f srcs/docker-compose.yml ps   # list the containers and their state
docker logs <container>                        # show the logs: mariadb, wordpress or nginx
```

In the `ps` output, all three containers (`mariadb`, `wordpress`, `nginx`) should be
`Up`, and `mariadb` should show `(healthy)`. If a container keeps restarting, its
logs usually say why.

Quick checks:

- The site loads at `https://aluque-v.42.fr` (after accepting the certificate).
- From a terminal, HTTPS answers and HTTP doesn't:

  ```sh
  curl -kI https://aluque-v.42.fr   # expect: HTTP/1.1 200 OK (or a 30x redirect)
  curl -I  http://aluque-v.42.fr    # expect: connection refused
  ```

- You can log into `https://aluque-v.42.fr/wp-admin` with the admin account.
- After `make down` then `make`, your posts and settings are still there.
