# nginx-php — Docker image for PHP web applications

Image Docker générique pour applications web PHP, basée sur l'image **PHP officielle**
(`php:*-fpm`) et fournie en variantes **Alpine** et **Debian**.

Maintenue par [Infogene](https://infogene.fr) ·
Image : [`ghcr.io/infogene/nginx-php`](https://github.com/infogene/docker-nginx-php/pkgs/container/nginx-php)

> À ne pas confondre avec une image `php` officielle. Voir la
> [page Docker Hub de PHP](https://hub.docker.com/_/php/) pour l'image PHP amont.

## Sommaire

- [Caractéristiques](#caractéristiques)
- [Démarrage rapide](#démarrage-rapide)
- [Utiliser l'image](#utiliser-limage)
- [Modes de fonctionnement](#modes-de-fonctionnement)
- [Services : backend, frontend, cron](#services--backend-frontend-cron)
- [Mode Supervisor générique](#mode-supervisor-générique---start-supervisor-cli)
- [Variables d'environnement](#variables-denvironnement)
- [Ports](#ports)
- [Personnaliser l'image](#personnaliser-limage)
- [Exemples](#exemples)
- [Fonctionnement interne](#fonctionnement-interne)

## Caractéristiques

- **PHP-FPM + Nginx** prêts à l'emploi, configuration Symfony-friendly.
- **Variantes Alpine & Debian**, PHP 8.4 (paramétrable via `PHP_VERSION`).
- **Exécution non-root** (`www-data`, uid/gid 1000) ; Nginx écoute sur le port **8080**.
- **Supervisor** comme superviseur de processus (PID 1) : redémarrage automatique,
  arrêt propre, logs vers `stdout`/`stderr`.
- Extensions PHP courantes préinstallées (`opcache`, `apcu`, `redis`, `intl`, `pdo_*`,
  `zip`, `xdebug` désactivé par défaut…), **Composer**, **Node 24** + **Yarn**.
- Entrypoint **piloté par options** : backend / frontend / cron / worker / CLI,
  commandes surchargeables.

## Démarrage rapide

```shell
docker run -d --name my-webapp -p 8080:8080 ghcr.io/infogene/nginx-php:latest
```

Ouvrez http://localhost:8080 : la page affiche le `phpinfo()` par défaut (placeholder).

## Utiliser l'image

### Monter votre application

L'application est servie depuis `/application` (`$APP_DIR`), document root `/application/public`.

```shell
docker run -d --name my-webapp -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest
```

### Construire votre propre image

```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

COPY --chown=www-data:www-data ./ /application
```

Vous pouvez ajouter des extensions PHP comme avec l'image officielle, via
`docker-php-ext-configure` / `docker-php-ext-install` :

```dockerfile
FROM ghcr.io/infogene/nginx-php:latest

RUN install-php-extensions gd
```

## Modes de fonctionnement

| Option | Effet |
|---|---|
| `--mode-prod` | Mode production (**défaut**) |
| `--mode-dev` | Mode développement : `APP_ENV=dev`, **xdebug activé** |
| `--enable-xdebug` | Active explicitement xdebug |

Sans option, le mode est déduit de la variable `APP_ENV` (défaut : `prod`).

```shell
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest --mode-dev
```

## Services : backend, frontend, cron

L'entrypoint démarre les services demandés sous **Supervisor**. La commande par
défaut de l'image est `--start-backend --mode-prod`.

| Option | Démarre | Commande par défaut |
|---|---|---|
| `--start-backend [CMD]` | Nginx + PHP-FPM | `php-fpm -F` + `nginx -g "daemon off;"` |
| `--start-frontend [CMD]` | Serveur frontend | `yarn --cwd frontend <env>` |
| `--start-all` | Backend **et** frontend | (leurs défauts) |
| `--start-cron` | Démon cron | crontab de `www-data` |

`--start-backend` et `--start-frontend` acceptent une **commande optionnelle** qui
**surcharge** le démarrage par défaut :

```shell
# Backend par défaut (Nginx + PHP-FPM)
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest --start-backend

# Backend surchargé : serveur web intégré de PHP
docker run -d -p 8080:8080 -v "$PWD:/application" \
  ghcr.io/infogene/nginx-php:latest \
  --start-backend "php -S 0.0.0.0:8080 -t /application/public"
```

Backend et frontend sont enregistrés comme des programmes Supervisor **distincts** :
chacun est redémarré indépendamment.

### Cron

Fournissez votre crontab et lancez le mode cron (Nginx / PHP-FPM ne démarrent pas) :

```shell
docker run -d --name my-cron -v "$PWD:/application" \
  -v "$PWD/mycrontab:/var/spool/cron/crontabs/www-data" \
  ghcr.io/infogene/nginx-php:latest --start-cron
```

## Mode Supervisor générique (`--start-supervisor-cli`)

Pour superviser **n'importe quelle** commande sans fournir de fichier
`supervisord.conf`, utilisez `--start-supervisor-cli` suivi d'options `--supervisor-*`.
La configuration Supervisor est générée au démarrage.

`--supervisor-program` est **répétable** (une section `[program]` par occurrence).

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

| Option | Directive générée | Défaut |
|---|---|---|
| `--supervisor-program "<cmd>"` | `command=<cmd>` | *(≥ 1 requis)* |
| `--supervisor-program-name NAME` | `[program:NAME]` | `app`, `app2`, … |
| `--supervisor-autostart BOOL` | `autostart` | `true` |
| `--supervisor-autorestart BOOL` | `autorestart` | `true` |
| `--supervisor-startretries N` | `startretries` | `3` |
| `--supervisor-stopasgroup BOOL` | `stopasgroup` | `true` |
| `--supervisor-killasgroup BOOL` | `killasgroup` | `true` |
| `--supervisor-user USER` | `user` | `www-data` |
| `--supervisor-stdout-logfile PATH` | `stdout_logfile` | `/dev/stdout` |
| `--supervisor-stderr-logfile PATH` | `stderr_logfile` | `/dev/stderr` |

**Portée des options** : avant le 1er `--supervisor-program` → défaut **global** (tous
les programmes) ; après un `--supervisor-program` → surcharge **ce** programme.

**Extensible** : toute option `--supervisor-<a>-<b> VALUE` devient `a_b=VALUE`
(ex. `--supervisor-numprocs 4` → `numprocs=4`).

> `user` doit valoir l'utilisateur courant du conteneur (`www-data` par défaut) ;
> pour superviser un autre utilisateur, lancez le conteneur en root (`--user 0`).

## Autres exécutions

```shell
# Commande unique puis sortie (aucun service)
docker run --rm -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest --cli "php -v"

# Commande au démarrage, avant les services
docker run -d -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest \
  --boot-cmd "php bin/console cache:clear" --start-backend

# Passthrough : tout argument positionnel est exécuté tel quel
docker run --rm -v "$PWD:/application" ghcr.io/infogene/nginx-php:latest bash
```

## Variables d'environnement

| Variable | Effet |
|---|---|
| `APP_ENV` | `dev` / `prod` (détermine le mode si aucune option `--mode-*`) |
| `APP_BOOT_CMD` | Commande exécutée au démarrage (équivaut à `--boot-cmd`) |
| `APP_BOOT_PERMS_FLUSH` | Si `true`, ajuste les permissions de `/application` (775, groupe `www-data`) |
| `APP_BOOT_PHP_XDEBUG_ENABLED` | Si `true`, active xdebug |
| `APP_BOOT_PHP_EXT_ENABLED` | Liste de modules PHP à activer (séparés par des espaces) |
| `USER_ID` / `GROUP_ID` | uid/gid de `www-data` (remap au build, défaut 1000) |

## Ports

| Port | Service |
|---|---|
| `8080` | Nginx (HTTP) |
| `3000` | Serveur frontend (dev) |
| `9000` | PHP-FPM (interne) |

## Personnaliser l'image

```shell
make build-tag 8.4   # build local des variantes 8.4-alpine / 8.4-debian
make build-tag       # variantes `latest`
make push-tag 8.4    # push vers ghcr.io/infogene/nginx-php
```

## Exemples

Des fichiers Docker Compose prêts à l'emploi sont fournis dans
[`docs/examples/`](docs/examples/) :

- [Backend Nginx + PHP-FPM](docs/examples/backend-nginx-phpfpm.yml)
- [Backend avec commande surchargée](docs/examples/backend-custom-command.yml)
- [Tous les services](docs/examples/all-services.yml)
- [Plusieurs programmes Supervisor](docs/examples/supervisor-multi-programs.yml)
- [Worker en arrière-plan](docs/examples/supervisor-worker.yml)

## Fonctionnement interne

- **Entrypoint** : `bin/docker-entrypoint` analyse les options, prépare le mode
  (dev/prod, xdebug), exécute l'éventuel `--boot-cmd`, puis enregistre les services
  demandés et lance un **unique `supervisord`** (via `bin/docker-supervisor-cli`).
- **`docker-supervisor-cli`** génère le `supervisord.conf` à partir des options
  `--supervisor-*` et exécute `supervisord`. Il est utilisé en interne par
  `--start-backend` / `--start-frontend`, et directement via `--start-supervisor-cli`.
- **Non-root** : l'image tourne en `www-data` ; Nginx reçoit la capability
  `cap_net_bind_service` mais le vhost écoute sur `8080`.
- **Variantes** : `Dockerfile.alpine` (défaut, `Dockerfile` y est lié) et
  `Dockerfile.debian`.

Aide complète des options : `docker run --rm ghcr.io/infogene/nginx-php:latest --help`.
