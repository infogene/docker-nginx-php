ARG PHP_VERSION='8.1'
ARG APP_ENV='prod'

FROM php:${PHP_VERSION}-fpm as base

LABEL application.mode='production'
LABEL maintainer='mZammouri <mohamed.zammouri@infogene.fr>'

#
## Environment valiables
ENV DEBIAN_FRONTEND=noninteractive

#
## Install packages
RUN apt update -yqq && \
    apt install -yqq \
        apt-utils apt-transport-https ca-certificates build-essential rsync netcat iputils-ping \
        sudo make gnupg g++ zip vim nano curl wget git openssl nginx cron \
        libssl-dev libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libpng-dev libxslt1-dev libzip-dev icu-devtools && \
        rm -rf /var/lib/apt/lists/*

#
## Generate certs
RUN openssl req -x509 -nodes -newkey rsa:4096  \
    -keyout /etc/ssl/private/main.key.pem  \
    -out /etc/ssl/certs/main.crt.pem  \
    -sha256 -days 365 -subj '/CN=localhost' && \
    mkdir -p /etc/nginx/ssl/certs/ && \
    ln -sf /etc/ssl/private/main.key.pem /etc/nginx/ssl/certs/main.key.pem && \
    ln -sf /etc/ssl/certs/main.crt.pem /etc/nginx/ssl/certs/main.crt.pem

#
## Install libsodium
RUN curl -sSKL -O https://download.libsodium.org/libsodium/releases/libsodium-1.0.18-stable.tar.gz && \
    tar xfvz libsodium-1.0.18-stable.tar.gz  && \
    cd libsodium-stable && \
    ./configure && make && make check && make install

#
## Install php ext
RUN docker-php-ext-configure gd --with-freetype=/usr/include/ --with-jpeg=/usr/include/ && \
    docker-php-ext-configure zip && \
    docker-php-ext-configure sodium --with-sodium && \
    docker-php-ext-install -j$(nproc) bcmath intl pdo_mysql simplexml soap sockets sodium xml xsl zip && \
    pecl install apcu-5.1.22 && \
    pecl install redis-5.3.7 && \
    pecl install xdebug-3.2.0 && \
    pecl clear-cache && \
    docker-php-ext-enable apcu opcache redis

#
## Install composer
RUN curl -o composer.phar -sSL https://getcomposer.org/download/2.5.5/composer.phar && \
    mv composer.phar /usr/local/bin/composer && \
    chmod +x /usr/local/bin/composer*

#
## Copy bin & conf
COPY ./bin/* /usr/local/bin/
COPY ./conf/nginx.vhost.conf /etc/nginx/conf.d/default.conf
COPY ./conf/php-custom.ini /usr/local/etc/php/conf.d/php-custom.ini
COPY ./conf/crontab /var/spool/cron/crontabs/www-data

RUN chmod +x /usr/local/bin/*

#
## Install newrelic
ARG NEW_RELIC_AGENT_VERSION='10.7.0.319'
ARG NEW_RELIC_LICENSE_KEY=''
ARG NEW_RELIC_APPNAME=''
ARG NEW_RELIC_DAEMON_ADDRESS=''

RUN docker-install-newrelic

#
## Configure globals
ARG APP_DIR='/application'

RUN mkdir -p /var/www && \
    chown -R www-data:www-data /var/www && \
    chown -R www-data:www-data /var/spool/cron/crontabs/www-data && \
    touch /var/log/cron.log && \
    chown -R :www-data /var/log/cron.log && \
    chmod +x /usr/local/bin/* && \
    rm /etc/nginx/sites-*/* && \
    echo 'alias ll="ls -l"'     >>  /etc/bash.bashrc && \
    echo 'alias lh="ls -hal"'   >>  /etc/bash.bashrc && \
    echo 'export PS1="\[\e[32m\]\u\[\e[m\]@\[\e[35m\]\h\[\e[m\]:\[\e[36m\]\w\[\e[m\]\\$ "' >> /etc/bash.bashrc && \
    echo 'umask 0002' >> /etc/bash.bashrc

WORKDIR $APP_DIR

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

CMD ["--mode-prod"]

FROM base as base_prod

#
## Build App : No need to build in container in dev mode, since volume will be mounted
COPY --chown=www-data:www-data ./src $APP_DIR

CMD ["--mode-prod"]

FROM base as base_dev

ARG USER_ID
ARG GROUP_ID

RUN docker-php-ext-enable xdebug

RUN docker-setup-dev-user

CMD ["--mode-dev"]

FROM base_${APP_ENV}
