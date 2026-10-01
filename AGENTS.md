# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

This repo builds a reusable **base Docker image** (`ghcr.io/infogene/nginx-php`) for running PHP web apps behind nginx + PHP-FPM. It is *not* an application — `src/public/index.php` is just a `phpinfo()` placeholder that users replace by mounting/copying their own app into `/application`. There is no test suite; "running" the project means building an image and starting a container.

## Conventions

**All documentation and code comments MUST be written in English** — READMEs, `docs/`, Docker Compose example comments, shell script comments, `usage()` help text, and user-facing error messages (`die`/`echo`). The user may converse in French, but everything written into the repository stays in English.

## Common commands

```bash
# Build images locally (Makefile wraps docker build). With no arg, builds `latest`.
make build-tag            # builds latest-debian, latest-alpine, tags latest -> alpine
make build-tag 8.4        # builds 8.4-debian, 8.4-alpine, tags 8.4 -> alpine
make push-tag [version]   # push to ghcr.io/infogene/nginx-php

# Build a single variant directly
docker build --build-arg PHP_VERSION=8.4 -f Dockerfile.alpine -t nginx-php:test .

# Run (default CMD is `--start-backend --mode-prod`; vhost listens on container port 8080)
docker run -d -p 8080:8080 -v "$PWD:/application" nginx-php:test
docker run -d -p 8080:8080 -v "$PWD:/application" nginx-php:test --mode-dev   # enables xdebug + logs
docker run -d -p 8080:8080 -v "$PWD:/application" nginx-php:test \
  --start-backend "php -S 0.0.0.0:8080 -t /application/public"                # override backend command
docker run --rm -v "$PWD:/application" nginx-php:test --cli "php -v"          # one-off command, no services
docker run --rm -v "$PWD:/application" nginx-php:test bash                    # passthrough: any args bypass flag parsing
```

`make` passes the version as a phony goal (the `%:` rule), so `make build-tag 8.4` works; the argument becomes `PHP_VERSION` and the tag suffix.

Ready-to-run Docker Compose examples live in `docs/examples/` (backend, custom command, all-services, supervisor multi-program, background worker). `supervisor-runner/` is a build-from-source scratch example used during development.

## Architecture

**Two parallel Dockerfiles, kept in lockstep.** `Dockerfile.alpine` (the default — `Dockerfile` is a symlink to it) and `Dockerfile.debian` install the same PHP extensions, Node 24 + yarn, and the same `bin/`/`conf/` files. They differ only in OS-specific details that **must both be updated** when changing build logic:

| | Alpine | Debian |
|---|---|---|
| `HOME_WWW` | `/home/www-data` | `/var/www` |
| `ETC_BASHRC` | `/etc/bash/bashrc` | `/etc/bash.bashrc` |
| nginx vhost dest | `/etc/nginx/http.d/default.conf` | `/etc/nginx/conf.d/default.conf` |
| cron daemon | `crond` (busybox) | `cron` |
| package mgr | `apk` | `apt` |

**Non-root by design.** The image runs as `USER www-data` (uid/gid 1000). nginx binds privileged-port-capable via `setcap cap_net_bind_service`, but the vhost listens on **8080** (not 80). `bin/docker-setup-www-user` runs at *build* time and can remap www-data's uid/gid to `USER_ID`/`GROUP_ID` to match the host user (only effective when the container starts as root, e.g. before the `USER` directive or with `--user 0`).

**Entrypoint = a flag-driven launcher that runs everything under Supervisor.** `bin/docker-entrypoint` (the active one) parses CLI flags into mode/service variables, runs setup → boot-cmd, then either execs a one-off (CLI/cron/passthrough) or **registers service programs and hands off to a single `supervisord` (PID 1)** via `bin/docker-supervisor-cli`. Key behaviors:
- Modes are mutually exclusive: `--mode-dev` forces xdebug on and `APP_ENV=dev`; `--mode-prod` is the default. With neither flag, `APP_ENV` env var decides.
- `--start-backend` and `--start-frontend` don't launch processes directly — they **append `--supervisor-program` entries to `SUPERVISOR_ARGS`** (via `register_supervisor_program`) and set `START_SUPERVISOR_CLI=1`. A single `start_supervisor_cli` then `exec docker-supervisor-cli "${SUPERVISOR_ARGS[@]}"`. This is why `--start-all` (backend + frontend) can run under one supervisord.
  - Backend default = two separate programs `php-fpm -F` + `nginx -g "daemon off;"` (independently supervised/restarted). Frontend default = `yarn --cwd frontend <APP_ENV>`.
  - Both accept an **optional command override**: `--start-backend "<cmd>"` / `--start-frontend "<cmd>"`. Parsing peeks `$2` and consumes it only if it doesn't start with `-` (so `--start-backend --mode-prod` is NOT treated as an override). An override collapses the backend to a single `[program:backend]`.
- `--start-supervisor-cli` + `--supervisor-*` args: generic path forwarding everything verbatim to `docker-supervisor-cli`. `--supervisor-program` is repeatable (one `[program]` each); options before the 1st program are global defaults, options after override the current program; `--supervisor-<a>-<b> VALUE` → `a_b=VALUE`.
- `--start-cron` still execs `crond`/`cron` directly (not via supervisor) and is checked before the service-registration block.
- **Any positional argument triggers passthrough** (`exec "$@"`) — all flags are ignored. This is why `docker run ... bash` and `... ls -l` work.
- `xdebug` is installed but disabled (`IPE_DONT_ENABLE=1`); it is only enabled at runtime in dev mode, and only when running as root.

**`bin/docker-supervisor-cli`** generates `/tmp/supervisord.conf` (path overridable via `SUPERVISORD_CONF`) from `--supervisor-*` args, then `exec supervisord`. The `[supervisord]` section is `nodaemon=true` + `logfile=/dev/null`/`logfile_maxbytes=0` + `pidfile=/tmp/supervisord.pid` — supervisord never writes into the cwd (`/application`), so the image works under a **read-only root filesystem** and doesn't litter the app dir. Every program gets defaults (`autostart`/`autorestart`/`stopasgroup`/`killasgroup=true`, `user=www-data`, logs → `/dev/stdout`/`/dev/stderr`, `*_logfile_maxbytes=0` so `/dev/stdout` is accepted). Used both internally (backend/frontend) and directly (`--start-supervisor-cli`).

**Hardening note (read-only / `cap_drop`).** nginx carries a `cap_net_bind_service` file capability (`setcap`, see Dockerfiles). Two consequences for hardened compose setups: (1) under `cap_drop: ALL` you must `cap_add: NET_BIND_SERVICE` or nginx `execve()` fails with EPERM even on 8080; (2) `no-new-privileges` is incompatible with the setcap'd nginx. Backends without file caps (e.g. `php -S`) have neither limitation. For a read-only rootfs the writable paths are `/tmp`, `/run/nginx`, `/var/lib/nginx/tmp`, `/var/log/nginx` (tmpfs, `mode=01777`). See `docs/examples/production-hardened.yml` and `docs/examples/hardened-php-builtin.yml`.

**Entrypoint variants** (only `docker-entrypoint` is wired into CMD): `docker-entrypoint-native` is the pre-Supervisor version (nginx in background + `php-fpm -F` as PID 1, frontend via `docker-exec-www-data`); `docker-entrypoint-supervisor` writes per-service configs to `/etc/supervisor/conf.d/`; `docker-entrypoint-old` is legacy. Switch by changing the `ENTRYPOINT` line in both Dockerfiles.

**`bin/` helper scripts** are all copied to `/usr/local/bin/` and on PATH inside the image:
- `docker-supervisor-cli` — generates `supervisord.conf` from `--supervisor-*` args and execs supervisord (see entrypoint section above).
- `docker-exec-www-data <cmd>` / `su-www-data` — drop to www-data via sudo when root, else run directly. Used throughout the entrypoint to run app/yarn/git commands.
- `docker-phpmod-enable` / `docker-phpmod-disable` — wrap `docker-php-ext-enable` and comment out extension ini lines.
- `docker-permissions-flush` — `chmod -R 775` + `chown -R :www-data /application` (gated at runtime by `APP_BOOT_PERMS_FLUSH`).
- `docker-motd-sysinfo` / `docker-setup-motd` — shell login banner.

**Runtime env vars** (consumed by entrypoint/scripts): `APP_ENV` (dev/prod), `APP_BOOT_CMD` (command run at startup), `APP_BOOT_PERMS_FLUSH`, `APP_BOOT_PHP_XDEBUG_ENABLED`, `APP_BOOT_PHP_EXT_ENABLED` (space-separated module list to enable). `APP_DIR` defaults to `/application`.

**nginx vhost** (`conf/nginx.vhost.conf`) is Symfony-shaped: front controller is `/application/public/index.php`, only `index.php` may execute PHP (all other `.php` → 404), `fastcgi_pass 127.0.0.1:9000`.

## CI/CD

`.gitlab-ci.yml` is the source of truth for published images (GitLab is primary; the repo mirrors to GitHub). It includes Infogene's standard code-scan template and a `docker-build` job that builds both variants with PHP 8.4 and pushes to the GitLab registry on every MR/default-branch commit. On a **git tag**, it additionally pushes versioned + `latest` tags to both the GitLab registry and `ghcr.io/infogene/nginx-php`. The `Makefile` is for local/manual builds and pushes the same image coordinates.
