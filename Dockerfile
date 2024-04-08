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
        apt-utils apt-transport-https ca-certificates build-essential rsync netcat-openbsd net-tools iputils-ping \
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
## Docker php ext installer
RUN curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o /usr/local/bin/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions

#
## Install php ext : Better install with https://github.com/mlocati/docker-php-extension-installer
RUN IPE_GD_WITHOUTAVIF=1 \
    install-php-extensions  apcu-stable \
                            bcmath-stable \
                            gd-stable \
                            intl-stable \
                            opcache-stable \
                            pdo_mysql-stable \
                            redis-stable \
                            simplexml-stable \
                            soap-stable \
                            sockets-stable \
                            xml-stable \
                            xsl-stable \
                            zip-stable && \
    IPE_DONT_ENABLE=1 \
    install-php-extensions  xdebug-stable && \
    install-php-extensions  @composer

#
## Copy bin & conf
COPY ./bin/* /usr/local/bin/
COPY ./conf/nginx.vhost.conf /etc/nginx/conf.d/default.conf
COPY ./conf/php-custom.ini /usr/local/etc/php/conf.d/php.ini
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
