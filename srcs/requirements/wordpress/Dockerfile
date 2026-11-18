FROM alpine:3.23

RUN apk add --no-cache \
		php84 php84-fpm php84-mysqli php84-phar php84-curl \
        php84-mbstring php84-iconv php84-openssl curl

RUN curl -o /usr/local/bin/wp \
		https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
		&& chmod +x /usr/local/bin/wp

COPY conf/www.conf /etc/php84/php-fpm.d/www.conf
COPY conf/zz-inception.ini /etc/php84/conf.d/zz-inception.ini
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
