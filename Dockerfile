FROM php:8.3-fpm-alpine

LABEL maintainer="panyingyun@gmail.com"

ENV SSH_PORT=8022 \
    PHORGE_GIT_USER=root \
    MYSQL_PORT=3306 \
    PROTOCOL=http

VOLUME /storage

EXPOSE 8022 80 443

# Switch the apk (Alpine package manager, the "apt" equivalent on Alpine)
# mirror to Huawei Cloud for faster downloads in CN.
RUN sed -i 's|dl-cdn.alpinelinux.org|mirrors.huaweicloud.com|g' /etc/apk/repositories

# Install runtime packages and build dependencies, then install PHP extensions.
# Uses the official PHP helper tools (`docker-php-ext-*`) and PECL for extensions like APCu.
RUN apk add --no-cache --virtual .build-deps \
        $PHPIZE_DEPS \
        freetype-dev libjpeg-turbo-dev libpng-dev zlib-dev libzip-dev oniguruma-dev libxml2-dev curl-dev openssl-dev openldap-dev

RUN apk add --no-cache \
        git \
        git-lfs \
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

# Configure Python: install pip and switch its index to the Huawei Cloud PyPI
# mirror (pip package downloads come from Huawei Cloud).
RUN apk add --no-cache py3-pip \
    && pip3 config set global.index-url https://mirrors.huaweicloud.com/repository/pypi/simple/

RUN docker-php-ext-configure gd --with-freetype=/usr/include/freetype2 --with-jpeg=/usr/include \
    && docker-php-ext-install -j"$(nproc)" opcache pcntl gd pdo_mysql mysqli mbstring zip ldap \
    && docker-php-ext-enable zip apcu ldap pcntl

RUN if [ -f /usr/libexec/git-core/git-http-backend ]; then ln -sf /usr/libexec/git-core/git-http-backend /usr/bin/git-http-backend; elif [ -f /usr/lib/git-core/git-http-backend ]; then ln -sf /usr/lib/git-core/git-http-backend /usr/bin/git-http-backend; fi \
    && apk del .build-deps \
    && rm -rf /var/cache/apk/*

# Download phorge sources from GitHub through the persistent git proxy.
# The same proxy is baked into /etc/gitconfig (see configs/gitconfig) so it
# survives image rebuilds and container restarts. Build with host networking
# so 127.0.0.1 inside the build container reaches the host proxy:
#   docker build --network host -t phorge-zh:latest .
# PHORGE_CACHEBUST is only there to invalidate this layer. Docker otherwise
# caches `git clone` and never fetches upstream again.
# (Offline fallback: vendor the sources into ./phorge-src/ and replace the
# git clone below with COPY ./phorge-src/... — see git history.)
ARG PHORGE_CACHEBUST=unknown
RUN echo "phorge cachebust=${PHORGE_CACHEBUST}" \
    && git config --global http.proxy http://127.0.0.1:7890 \
    && git config --global https.proxy https://127.0.0.1:7890 \
    && mkdir -p /var/www/phorge/ \
    && git clone https://github.com/phorgeit/arcanist.git /var/www/phorge/arcanist \
    && git clone https://github.com/phorgeit/phorge.git /var/www/phorge/phorge

# Patch arcanist's AWS client for custom HTTP S3 endpoints (RustFS/MinIO):
# allows http:// endpoints and fixes the SigV4 Host header on non-default ports.
COPY ./scripts/patch-aws-http.sh /patch-aws-http.sh
RUN chmod +x /patch-aws-http.sh && /patch-aws-http.sh && rm /patch-aws-http.sh

# Copy Chinese (zh_CN) language pack into phorge extensions directory.
# Phorge auto-discovers translation classes in src/extensions/ at runtime.
COPY ./extensions/ /var/www/phorge/phorge/src/extensions/

# copy nginx config (the repo provides a custom nginx.conf)
COPY ./configs/nginx-ph.conf /etc/nginx/sites-available/phorge.conf
COPY ./configs/nginx.conf /etc/nginx/nginx.conf
RUN mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled \
    && ln -sf /etc/nginx/sites-available/phorge.conf /etc/nginx/sites-enabled/phorge.conf \
    && mkdir -p /var/lib/nginx/tmp/client_body \
    && chown -R www-data:www-data /var/lib/nginx

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
