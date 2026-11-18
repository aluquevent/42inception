#!/bin/sh
set -e

DB_PASSWORD="$(cat /run/secrets/db_password)"
WP_ADMIN_PASSWORD="$(cat /run/secrets/wp_admin_password)"
WP_USER_PASSWORD="$(cat /run/secrets/wp_user_password)"

if echo "$WP_ADMIN_USER" | grep -qi 'admin'; then
	echo "wordpress: WP_ADMIN_USER can't contain 'admin'" >&2
	exit 1
fi

if [ ! -f wp-config.php ]; then
	wp core download --allow-root
	
	wp config create --allow-root \
		--dbname="$MYSQL_DATABASE" \
		--dbuser="$MYSQL_USER" \
		--dbpass="$DB_PASSWORD" \
		--dbhost=mariadb:3306
	wp core install --allow-root \
		--url="https://$DOMAIN_NAME" \
		--title="$WP_TITLE" \
		--admin_user="$WP_ADMIN_USER" \
		--admin_password="$WP_ADMIN_PASSWORD" \
		--admin_email="$WP_ADMIN_EMAIL" \
		--skip-email
	
	wp user create --allow-root "$WP_USER" "$WP_USER_EMAIL" \
		--role=author \
		--user_pass="$WP_USER_PASSWORD"
fi

chown -R nobody:nobody /var/www/html

exec php-fpm84 -F
