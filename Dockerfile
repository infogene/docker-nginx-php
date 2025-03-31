ARG PHP_VERSION='8.4'
ARG DEB_VERSION='bookworm'
ARG APP_ENV='prod'

FROM php:${PHP_VERSION}-fpm-${DEB_VERSION}

LABEL application.mode='production'
LABEL maintainer='mZammouri <mohamed.zammouri@infogene.fr>'

ARG APP_DIR='/application'

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR ${APP_DIR}

# Install packages
RUN apt update --yes -q && \
    apt install --no-install-recommends --yes -q  sudo make curl wget zip nano git openssl nginx cron bash && \
    apt-get autoremove -yq && \
    apt-get autoclean -yq && \
    rm -rf /var/lib/apt/lists/*

## Docker php ext installer : Better install with https://github.com/mlocati/docker-php-extension-installer
RUN curl -sSL https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions -o /usr/local/bin/install-php-extensions && \
    chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions  opcache-stable \
                            redis-stable \
                            intl-stable \
                            pdo_pgsql-stable \
                            pdo_mysql-stable  \
                            zip-stable \
                            http-stable && \
    IPE_DONT_ENABLE=1 \
    install-php-extensions  xdebug-stable && \
    install-php-extensions  @composer

### Install Symfony binary, node + yarn
#RUN wget https://get.symfony.com/cli/installer -O - | bash && \
#    mv /root/.symfony5/bin/symfony /usr/local/bin/symfony && \
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | sh - >/dev/null 2>&1 && \
    curl -sSL https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - >/dev/null 2>&1 && \
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
    apt-get update --yes -q && \
    apt-get install --no-install-recommends --yes -q nodejs yarn && \
    apt-get autoremove -yq && \
    apt-get autoclean -yq && \
    rm -rf /var/lib/apt/lists/*

## Copy App
COPY ./ /usr/local/share/application-src

RUN cp /usr/local/share/application-src/bin/* /usr/local/bin/ && \
    cp /usr/local/share/application-src/conf/nginx.vhost.conf /etc/nginx/conf.d/default.conf && \
    cp /usr/local/share/application-src/conf/php.ini /usr/local/etc/php/conf.d/php.ini && \
    cp /usr/local/share/application-src/conf/crontab /var/spool/cron/crontabs/www-data && \
    cp -rpf /usr/local/share/application-src/src/* ${APP_DIR} && \
    chmod +x /usr/local/bin/* && \
    mkdir -p /var/www && \
    touch /var/log/cron.log && \
    chown -R www-data:www-data /application && \
    chown -R www-data:www-data /var/www && \
    chown -R www-data:www-data /var/spool/cron/crontabs/www-data && \
    chown -R :www-data /var/log/cron.log && \
    rm /etc/nginx/sites-*/* && \
    echo 'alias ll="ls -hal"'     >>  /etc/bash.bashrc && \
    echo 'export PS1="\[\e[32m\]\u\[\e[m\]@\[\e[35m\]\h\[\e[m\]:\[\e[36m\]\w\[\e[m\]\\$ "' >> /etc/bash.bashrc && \
    echo 'umask 0002' >> /etc/bash.bashrc && \
    rm -rf /var/lib/apt/lists/* && \
    rm -rf /var/www/.cache/* && \
    rm -rf /var/www/.composer/* && \
    rm -rf /var/cache/*

EXPOSE 80

ENTRYPOINT ["/usr/local/bin/docker-entrypoint"]

CMD ["--mode-prod"]