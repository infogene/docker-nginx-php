ARG PHP_VERSION='8.4'
ARG DEB_VERSION='bookworm'
ARG APP_ENV='prod'

FROM php:${PHP_VERSION}-fpm-${DEB_VERSION}

LABEL application.mode='production'
LABEL maintainer='mZammouri <mohamed.zammouri@infogene.fr>'

ARG APP_DIR='/application'

ENV DEBIAN_FRONTEND=noninteractive

# Install packages
RUN apt update -yqq && \
    apt install -yqq sudo make curl wget zip vim nano git openssl nginx cron \
#    libssl-dev libfreetype6-dev libjpeg62-turbo-dev libmcrypt-dev libpng-dev libxslt1-dev libzip-dev icu-devtools \
    && \
    rm -rf /var/lib/apt/lists/*

## Generate certs
RUN openssl req -x509 -nodes -newkey rsa:4096  \
    -keyout /etc/ssl/private/main.key.pem  \
    -out /etc/ssl/certs/main.crt.pem  \
    -sha256 -days 365 -subj '/CN=localhost' && \
    mkdir -p /etc/nginx/ssl/certs/ && \
    ln -sf /etc/ssl/private/main.key.pem /etc/nginx/ssl/certs/main.key.pem && \
    ln -sf /etc/ssl/certs/main.crt.pem /etc/nginx/ssl/certs/main.crt.pem

## Install Symfony binary
RUN wget https://get.symfony.com/cli/installer -O - | bash && \
    mv /root/.symfony5/bin/symfony /usr/local/bin/symfony

## Docker php ext installer
RUN curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o /usr/local/bin/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions

## Install php ext : Better install with https://github.com/mlocati/docker-php-extension-installer
RUN install-php-extensions  opcache-stable \
                            redis-stable \
                            intl-stable \
                            pdo_pgsql-stable \
                            pdo_mysql-stable && \
    IPE_DONT_ENABLE=1 \
    install-php-extensions  xdebug-stable && \
    install-php-extensions  @composer

## Copy bin & conf
COPY ./bin/* /usr/local/bin/
COPY ./conf/nginx.vhost.conf /etc/nginx/conf.d/default.conf
COPY ./conf/php.ini /usr/local/etc/php/conf.d/php.ini
COPY ./conf/crontab /var/spool/cron/crontabs/www-data

RUN chmod +x /usr/local/bin/*

RUN mkdir -p /var/www && \
    chown -R www-data:www-data /var/www && \
    chown -R www-data:www-data /var/spool/cron/crontabs/www-data && \
    touch /var/log/cron.log && \
    chown -R :www-data /var/log/cron.log && \
    chmod +x /usr/local/bin/* && \
    rm /etc/nginx/sites-*/* && \
    echo 'alias ll="ls -hal"'     >>  /etc/bash.bashrc && \
    echo 'export PS1="\[\e[32m\]\u\[\e[m\]@\[\e[35m\]\h\[\e[m\]:\[\e[36m\]\w\[\e[m\]\\$ "' >> /etc/bash.bashrc && \
    echo 'umask 0002' >> /etc/bash.bashrc

COPY --chown=www-data:www-data ./src ${APP_DIR}

WORKDIR ${APP_DIR}

EXPOSE 80 443

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

CMD ["--mode-prod"]