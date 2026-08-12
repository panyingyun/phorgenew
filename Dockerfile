FROM php:8.3-fpm-alpine

LABEL maintainer="rrvenn@proton.me"

ENV SSH_PORT=8022 \
    PHORGE_GIT_USER=root \
    MYSQL_PORT=3306 \
    PROTOCOL=http

VOLUME /storage

EXPOSE 8022 80 443

# Install runtime packages and build dependencies, then install PHP extensions.
# Uses the official PHP helper tools (`docker-php-ext-*`) and PECL for extensions like APCu.
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        freetype-dev libjpeg-turbo-dev libpng-dev zlib-dev libzip-dev oniguruma-dev libxml2-dev curl-dev openssl-dev ldb-dev openldap-dev 

RUN apk add --no-cache \
        git \
        nginx \
        bash \
        libpng \
        libjpeg-turbo \
        freetype \
        icu-dev \
        mariadb-client \
        openssh \
        tini \
        oniguruma \
        zlib \
        libzip \
        mercurial \
        ca-certificates \
        subversion \
        sudo \
        supervisor \
        python3 \
        py3-pygments \
        wget \
        procps \
        imagemagick \
        libldap \
        git-daemon \
        postfix

RUN pecl install apcu
RUN docker-php-ext-enable apcu
RUN docker-php-ext-configure gd --with-freetype=/usr/include/freetype2 --with-jpeg=/usr/include \
    && docker-php-ext-install -j"$(nproc)" opcache pcntl gd pdo_mysql mysqli mbstring zip ldap \
    && docker-php-ext-enable zip apcu ldap pcntl

RUN if [ -f /usr/libexec/git-core/git-http-backend ]; then ln -sf /usr/libexec/git-core/git-http-backend /usr/bin/git-http-backend; elif [ -f /usr/lib/git-core/git-http-backend ]; then ln -sf /usr/lib/git-core/git-http-backend /usr/bin/git-http-backend; fi \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

# Download phorge sources
RUN mkdir -p /var/www/phorge/
RUN git clone https://github.com/phorgeit/arcanist.git /var/www/phorge/arcanist \
    && git clone https://github.com/phorgeit/phorge.git /var/www/phorge/phorge

# Copy Chinese (zh_CN) language pack into phorge extensions directory.
# Phorge auto-discovers translation classes in src/extensions/ at runtime.
COPY ./extensions/ /var/www/phorge/phorge/src/extensions/

# copy nginx config (the repo provides a custom nginx.conf)
COPY ./configs/nginx-ph.conf /etc/nginx/sites-available/phorge.conf
COPY ./configs/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled \
    && ln -sf /etc/nginx/sites-available/phorge.conf /etc/nginx/sites-enabled/phorge.conf

# copy git config
COPY ./configs/gitconfig /etc/gitconfig

# copy ssh key generation
COPY ./configs/regenerate-ssh-keys.sh /regenerate-ssh-keys.sh

# copy PHP config into locations used by the official PHP images
COPY ./configs/www.conf /usr/local/etc/php-fpm.d/www.conf
COPY ./configs/php.ini /usr/local/etc/php/php.ini
COPY ./configs/php-fpm.conf /usr/local/etc/php-fpm.conf
RUN mkdir -p /run/php && chown www-data:www-data /run/php

# copy supervisord config and startup script
COPY ./configs/supervisord.conf /etc/supervisord.conf
COPY ./scripts/startup.sh /startup.sh
COPY ./scripts/phorge-pdh-wrapper.sh /phorge-pdh-wrapper.sh
RUN chmod +x /phorge-pdh-wrapper.sh
RUN chmod +x /startup.sh

RUN mkdir -p /var/repo/

USER root

CMD [ "/startup.sh" ]
