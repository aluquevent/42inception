#!/bin/sh
set -e

DB_ROOT_PASSWORD="$(cat /run/secrets/db_root_password)"
DB_PASSWORD="$(cat /run/secrets/db_password)"

mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

if [ ! -d /var/lib/mysql/mysql ] ; then
	mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db > /dev/null

	mariadbd --user=mysql --skip-networking &
	pid="$!"

	i=0
	until mariadb-admin ping --silent 2> /dev/null; do
		i=$((i + 1))
		if [ "$i" -ge 30 ]; then
			echo "mariadb: temporary server did not start" >&2
			exit 1
		fi
		sleep 1
	done
	
	mariadb -u root << EOF
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF

	kill "$pid"
	wait "$pid"
fi

exec mariadbd --user=mysql
