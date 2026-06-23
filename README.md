# nginx-php — Docker image for PHP web applications

A general-purpose Docker image for PHP web applications, built on the **official PHP
image** (`php:*-fpm`) and shipped in **Alpine** and **Debian** variants.

Maintained by [Infogene](https://infogene.fr) ·
Image: [`ghcr.io/infogene/nginx-php`](https://github.com/infogene/docker-nginx-php/pkgs/container/nginx-php)

> Not to be confused with an official `php` image. See the
> [PHP Docker Hub page](https://hub.docker.com/_/php/) for the upstream PHP image.

## Table of contents

- [Features](#features)
- [Quick start](#quick-start)
- [Using the image](#using-the-image)
- [Run modes](#run-modes)
- [Services: backend, frontend, cron](#services-backend-frontend-cron)
- [Generic Supervisor mode](#generic-supervisor-mode---start-supervisor-cli)
- [Other executions](#other-executions)
- [Environment variables](#environment-variables)
- [Ports](#ports)
- [Customizing the image](#customizing-the-image)
- [Examples](#examples)
- [How it works](#how-it-works)

## Features

- **PHP-FPM + Nginx** out of the box, Symfony-friendly configuration.
- **Alpine & Debian variants**, PHP 8.4 (configurable via `PHP_VERSION`).
- **Non-root execution** (`www-data`, uid/gid 1000); Nginx listens on port **8080**.
- **Supervisor** as the process supervisor (PID 1): automatic restart, clean
  shutdown, logs to `stdout`/`stderr`.
- Common PHP extensions preinstalled (`opcache`, `apcu`, `redis`, `intl`, `pdo_*`,
  `zip`, `xdebug` disabled by default…), **Composer**, **Node 24** + **Yarn**.
- **Option-driven** entrypoint: backend / frontend / cron / worker / CLI, with
  overridable commands.

## Quick start

```shell
docker run -d --name my-webapp -p 8080:8080 ghcr.io/infogene/nginx-php:latest
```

Open http://localhost:8080: the page shows the default `phpinfo()` (placeholder).

## Using the image

### Mount your application

The application is served from `/application` (`$APP_DIR`), document root `/application/public`.

```shell
docker run -d --name my-webapp -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest
```

### Build your own image

```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

COPY --chown=www-data:www-data ./ /application
```

You can add PHP extensions just like with the official image, via
`docker-php-ext-configure` / `docker-php-ext-install` (or the bundled installer):

```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

RUN install-php-extensions gd
```

## Run modes

| Option | Effect |
|---|---|
| `--mode-prod` | Production mode (**default**) |
| `--mode-dev` | Development mode: `APP_ENV=dev`, **xdebug enabled** |
| `--enable-xdebug` | Explicitly enable xdebug |

Without an option, the mode is derived from the `APP_ENV` variable (default: `prod`).

```shell
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest --mode-dev
```

## Services: backend, frontend, cron

The entrypoint starts the requested services under **Supervisor**. The image's
default command is `--start-backend --mode-prod`.

| Option | Starts | Default command |
|---|---|---|
| `--start-backend [CMD]` | Nginx + PHP-FPM | `php-fpm -F` + `nginx -g "daemon off;"` |
| `--start-frontend [CMD]` | Frontend server | `yarn --cwd frontend <env>` |
| `--start-all` | Backend **and** frontend | (their defaults) |
| `--start-cron` | Cron daemon | `www-data` crontab |

`--start-backend` and `--start-frontend` accept an **optional command** that
**overrides** the default startup:

```shell
# Default backend (Nginx + PHP-FPM)
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest --start-backend

# Overridden backend: PHP built-in web server
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest \
  --start-backend "php -S 0.0.0.0:8080 -t /application/public"
```

Backend and frontend are registered as **separate** Supervisor programs: each is
restarted independently.

### Cron

Provide your crontab and start cron mode (Nginx / PHP-FPM do not start):

```shell
docker run -d --name my-cron -v "$PWD:/application" \
  -v "$PWD/mycrontab:/var/spool/cron/crontabs/www-data" \
  ghcr.io/infogene/nginx-php:latest --start-cron
```

## Generic Supervisor mode (`--start-supervisor-cli`)

To supervise **any** command without providing a `supervisord.conf`, use
`--start-supervisor-cli` followed by `--supervisor-*` options. The Supervisor
configuration is generated at startup.

`--supervisor-program` is **repeatable** (one `[program]` section per occurrence).

```yaml
command:
  - --start-supervisor-cli

  - --supervisor-program
  - php bin/console messenger:consume async --time-limit=3600
  - --supervisor-program-name
  - messenger
  - --supervisor-startretries
  - "10"
```

| Option | Generated directive | Default |
|---|---|---|
| `--supervisor-program "<cmd>"` | `command=<cmd>` | *(≥ 1 required)* |
| `--supervisor-program-name NAME` | `[program:NAME]` | `app`, `app2`, … |
| `--supervisor-autostart BOOL` | `autostart` | `true` |
| `--supervisor-autorestart BOOL` | `autorestart` | `true` |
| `--supervisor-startretries N` | `startretries` | `3` |
| `--supervisor-stopasgroup BOOL` | `stopasgroup` | `true` |
| `--supervisor-killasgroup BOOL` | `killasgroup` | `true` |
| `--supervisor-user USER` | `user` | `www-data` |
| `--supervisor-stdout-logfile PATH` | `stdout_logfile` | `/dev/stdout` |
| `--supervisor-stderr-logfile PATH` | `stderr_logfile` | `/dev/stderr` |

**Option scope**: before the 1st `--supervisor-program` → **global** default (all
programs); after a `--supervisor-program` → overrides **that** program.

**Extensible**: any `--supervisor-<a>-<b> VALUE` option becomes `a_b=VALUE`
(e.g. `--supervisor-numprocs 4` → `numprocs=4`).

> `user` must match the container's current user (`www-data` by default); to
> supervise a different user, run the container as root (`--user 0`).

## Other executions

```shell
# Single command then exit (no services)
docker run --rm -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest --cli "php -v"

# Command at startup, before services
docker run -d -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest \
  --boot-cmd "php bin/console cache:clear" --start-backend

# Passthrough: any positional argument is executed as-is
docker run --rm -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest bash
```

## Environment variables

| Variable | Effect |
|---|---|
| `APP_ENV` | `dev` / `prod` (determines the mode when no `--mode-*` option) |
| `APP_BOOT_CMD` | Command run at startup (equivalent to `--boot-cmd`) |
| `APP_BOOT_PERMS_FLUSH` | If `true`, adjusts `/application` permissions (775, group `www-data`) |
| `APP_BOOT_PHP_XDEBUG_ENABLED` | If `true`, enables xdebug |
| `APP_BOOT_PHP_EXT_ENABLED` | Space-separated list of PHP modules to enable |
| `USER_ID` / `GROUP_ID` | `www-data` uid/gid (remapped at build time, default 1000) |

## Ports

| Port | Service |
|---|---|
| `8080` | Nginx (HTTP) |
| `3000` | Frontend server (dev) |
| `9000` | PHP-FPM (internal) |

## Customizing the image

```shell
make build-tag 8.4   # local build of the 8.4-alpine / 8.4-debian variants
make build-tag       # `latest` variants
make push-tag 8.4    # push to ghcr.io/infogene/nginx-php
```

## Examples

Ready-to-run Docker Compose files are provided in
[`docs/examples/`](docs/examples/):

- [Nginx + PHP-FPM backend](docs/examples/backend-nginx-phpfpm.yml)
- [Backend with overridden command](docs/examples/backend-custom-command.yml)
- [All services](docs/examples/all-services.yml)
- [Multiple Supervisor programs](docs/examples/supervisor-multi-programs.yml)
- [Background worker](docs/examples/supervisor-worker.yml)

## How it works

- **Entrypoint**: `bin/docker-entrypoint` parses the options, prepares the mode
  (dev/prod, xdebug), runs any `--boot-cmd`, then registers the requested services
  and launches a **single `supervisord`** (via `bin/docker-supervisor-cli`).
- **`docker-supervisor-cli`** generates `supervisord.conf` from the `--supervisor-*`
  options and execs `supervisord`. It is used internally by `--start-backend` /
  `--start-frontend`, and directly via `--start-supervisor-cli`.
- **Non-root**: the image runs as `www-data`; Nginx is granted the
  `cap_net_bind_service` capability but the vhost listens on `8080`.
- **Variants**: `Dockerfile.alpine` (default, `Dockerfile` is a symlink to it) and
  `Dockerfile.debian`.

Full option help: `docker run --rm ghcr.io/infogene/nginx-php:latest --help`.
