#!/bin/sh
set -e

SSL_DIR=/etc/nginx/ssl

if [ ! -f "$SSL_DIR/inception.crt" ]; then
    mkdir -p "$SSL_DIR"
    openssl req -x509 -noenc -newkey rsa:2048 -days 365 \
        -keyout "$SSL_DIR/inception.key" \
        -out "$SSL_DIR/inception.crt" \
        -subj "/CN=$DOMAIN_NAME"
fi

sed -i "s/__DOMAIN_NAME__/$DOMAIN_NAME/" /etc/nginx/nginx.conf

exec nginx

