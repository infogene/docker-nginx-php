# AGENTS.md

This file provides guidance to AI coding agents (Claude Code, Codex, …) when working with code in this repository. `CLAUDE.md` (gitignored, local) just imports it via `@AGENTS.md` — edit this file, not that one.

## What this is

This repo builds a reusable **base Docker image** (`ghcr.io/infogene/nginx-php`) for running PHP web apps behind nginx + PHP-FPM. It is *not* an application — `src/public/index.php` is just a `phpinfo()` placeholder that users replace by mounting/copying their own app into `/application`. There is no test suite; "running" the project means building an image and starting a container.

## Conventions

**All documentation and code comments MUST be written in English** — READMEs, `docs/`, Docker Compose example comments, shell script comments, `usage()` help text, and user-facing error messages (`die`/`echo`). The user may converse in French, but everything written into the repository stays in English.

## Common commands

```bash
# Build images locally (Makefile wraps `docker build --pull --no-cache`). With no arg, builds `latest`.
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

Ready-to-run Docker Compose examples live in `docs/examples/` (indexed in `docs/examples/README.md`; each has a commented-out `build:` block to test against local sources). Keep `README.md`, `docs/examples/` and the `usage()` text in `bin/docker-entrypoint` / `bin/docker-supervisor-cli` in sync when changing flags.

## Architecture

**Two parallel Dockerfiles, kept in lockstep.** `Dockerfile.alpine` (the default — `Dockerfile` is a symlink to it) and `Dockerfile.debian` install the same PHP extensions, Node 24 + yarn + pnpm + mjml, supercronic, and the same `bin/`/`conf/` files. They differ only in OS-specific details that **must both be updated** when changing build logic:

| | Alpine | Debian |
|---|---|---|
| `HOME_WWW` | `/home/www-data` | `/var/www` |
| `ETC_BASHRC` | `/etc/bash/bashrc` | `/etc/bash.bashrc` |
| nginx vhost dest | `/etc/nginx/http.d/default.conf` | `/etc/nginx/conf.d/default.conf` |
| nginx pid file | `/run/nginx/nginx.pid` (default) | `/run/nginx/nginx.pid` (`sed` on `nginx.conf`, default `/run/nginx.pid`) |
| node tarball | unofficial-builds `-musl` | nodejs.org glibc |
| `strip` for node | temporary `binutils` (`.strip-deps`) | already in the base (`$PHPIZE_DEPS`) |
| package mgr | `apk` | `apt` |

**Non-root by design.** The image runs as `USER www-data` (uid/gid 1000) and the vhost listens on **8080**. No binary carries file capabilities and there is no `sudo` (nor any setuid helper of ours): when the container runs as root, `docker-exec-www-data` drops to www-data with `setpriv`. Ports < 1024 therefore need root (or `--sysctl net.ipv4.ip_unprivileged_port_start=0`). `bin/docker-setup-www-user` runs at *build* time (as root, before `USER www-data`) and recreates www-data with `USER_ID`/`GROUP_ID`. Those are `ENV` (default 1000), not `ARG`, so remapping to a host uid means a derived image that sets them and re-runs the script as root.

**Entrypoint = a flag-driven launcher that runs everything under Supervisor.** `bin/docker-entrypoint` (the active one) parses CLI flags into mode/service variables, runs setup → boot-cmd, then either execs a one-off (CLI/cron/passthrough) or **registers service programs and hands off to a single `supervisord` (PID 1)** via `bin/docker-supervisor-cli`. Key behaviors:
- Modes are mutually exclusive: `--mode-dev` forces xdebug on and `APP_ENV=dev`; `--mode-prod` is the default. With neither flag, `APP_ENV` env var decides.
- `--start-backend` and `--start-frontend` don't launch processes directly — they **append `--supervisor-program` entries to `SUPERVISOR_ARGS`** (via `register_supervisor_program`) and set `START_SUPERVISOR_CLI=1`. A single `start_supervisor_cli` then `exec docker-supervisor-cli "${SUPERVISOR_ARGS[@]}"`. This is why `--start-all` (backend + frontend) can run under one supervisord.
  - Backend default = two separate programs `php-fpm -F` + `nginx -g "daemon off;"` (independently supervised/restarted). Frontend default = `yarn --cwd frontend <APP_ENV>`.
  - Both accept an **optional command override**: `--start-backend "<cmd>"` / `--start-frontend "<cmd>"`. Parsing peeks `$2` and consumes it only if it doesn't start with `-` (so `--start-backend --mode-prod` is NOT treated as an override). An override collapses the backend to a single `[program:backend]`.
- `--start-supervisor-cli` + `--supervisor-*` args: generic path forwarding everything verbatim to `docker-supervisor-cli`. `--supervisor-program` is repeatable (one `[program]` each); options before the 1st program are global defaults, options after override the current program; `--supervisor-<a>-<b> VALUE` → `a_b=VALUE`.
- `--start-cron` execs `supercronic /var/spool/cron/crontabs/www-data` (as www-data via `docker-exec-www-data`, not under supervisor) and is checked before the service-registration block. supercronic replaced crond/cron because those daemons need root to switch user per job (silently running nothing under the non-root image), and Debian's cron also rejects non-0600 crontabs and logs to a non-existent syslog. Its version + sha256 are `ARG`s in both Dockerfiles.
- When the container runs as root, the backend's nginx gets `-g "user www-data; daemon off;"` so workers can write the www-data-owned `/var/lib/nginx/tmp` (upload buffering).
- **Any positional argument triggers passthrough** (`exec "$@"`) — all flags are ignored. This is why `docker run ... bash` and `... ls -l` work.
- `validate_params` rejects contradictory flags (`--mode-dev` + `--mode-prod`; more than one of `--cli` / `--start-cron` / `--start-*` services) and implies `--start-backend` when no run mode is given. `--cli` and `--boot-cmd` run through `bash -c`.
- **Graceful stop**: the image's `STOPSIGNAL` is `SIGQUIT` (inherited from `php:*-fpm`); supervisord forwards each program's `stopsignal`. The backend registers php-fpm and nginx with `stopsignal=QUIT` + `stopwaitsecs=25`, and `conf/php-fpm.conf` (→ `php-fpm.d/zz-nginx-php.conf`) sets `process_control_timeout = 20s` — both are needed, otherwise in-flight requests get a 502.
- nginx `access.log`/`error.log` are symlinks to `/dev/stdout`/`/dev/stderr` (set in the Dockerfiles).
- `xdebug` is installed but disabled (`IPE_DONT_ENABLE=1`); it is enabled at runtime in dev mode (or `--enable-xdebug` / `APP_BOOT_PHP_XDEBUG_ENABLED`), and only when running as root — otherwise the entrypoint warns and continues, since `docker-php-ext-enable` writes to root-owned `conf.d`.

**`bin/docker-supervisor-cli`** generates `/tmp/supervisord.conf` (path overridable via `SUPERVISORD_CONF`) from `--supervisor-*` args, then `exec supervisord`. The `[supervisord]` section is `nodaemon=true` + `logfile=/dev/null`/`logfile_maxbytes=0` + `pidfile=/tmp/supervisord.pid` — supervisord never writes into the cwd (`/application`), so the image works under a **read-only root filesystem** and doesn't litter the app dir. It escapes `%` in commands (supervisord would parse it as a format string) and, unless `SUPERVISOR_EXIT_ON_FATAL=false`, adds `[eventlistener:fatal-listener]` (`bin/docker-supervisor-fatal-listener`) which stops supervisord when a program enters `FATAL`, so the container exits instead of running without that service. Every program gets defaults (`autostart`/`autorestart`/`stopasgroup`/`killasgroup=true`, `user=$(id -un)` — the user the container was launched as, so `--user 0` runs programs as root —, logs → `/dev/stdout`/`/dev/stderr`, `*_logfile_maxbytes=0` so `/dev/stdout` is accepted). Used both internally (backend/frontend) and directly (`--start-supervisor-cli`).

**Hardening note (read-only / `cap_drop`).** Running as www-data, every mode works with `cap_drop: ALL` (nothing added back) and `no-new-privileges`. Do not reintroduce `setcap` on nginx: a file capability makes `execve()` fail under `cap_drop: ALL` (unless re-added) and is refused under `no-new-privileges`. Running as root needs `SETUID`/`SETGID` (nginx workers, php-fpm pool and `setpriv` switch to www-data). For a read-only rootfs the writable paths are `/tmp`, `/run/nginx`, `/var/lib/nginx/tmp` (tmpfs, `mode=01777`); nginx logs are symlinked to stdout/stderr, so `/var/log/nginx` needs no tmpfs. See `docs/examples/production-hardened.yml` and `docs/examples/hardened-php-builtin.yml`.

`conf/supervisord.conf` is still copied to `/etc/supervisor/supervisord.conf` but is **not used** by the current entrypoint (leftover from the removed per-service-config entrypoint variants).

**`bin/` helper scripts** are all copied to `/usr/local/bin/` and on PATH inside the image:
- `docker-supervisor-cli` — generates `supervisord.conf` from `--supervisor-*` args and execs supervisord (see entrypoint section above).
- `docker-exec-www-data <cmd>` / `su-www-data` — drop to www-data via `setpriv` when root (keeping the environment, `HOME` set), else run directly. Used throughout the entrypoint to run app/yarn/git commands.
- `docker-phpmod-enable` / `docker-phpmod-disable` — wrap `docker-php-ext-enable` and comment out extension ini lines.
- `docker-permissions-flush` — `chown -R :www-data` + `chmod -R g+rwX,o-w` on `/application`, setgid on directories (no blanket 775: files keep their own execute bit).
- `docker-exec-cmd` — bare `exec "$@"` wrapper.
- `docker-motd-sysinfo` / `docker-setup-motd` — shell login banner.

**Runtime env vars** read by the entrypoint: `APP_ENV` (dev/prod), `APP_BOOT_CMD` (same as `--boot-cmd`), and the boolean (`1`/`true`) or list vars applied during setup, before the boot command: `APP_BOOT_PHP_XDEBUG_ENABLED`, `APP_BOOT_PHP_EXT_ENABLED` (space-separated, root only — warns otherwise), `APP_BOOT_PERMS_FLUSH` (runs `docker-permissions-flush`, dies on failure). `APP_DIR` defaults to `/application`.

**Runtime settings come from env vars.** `conf/php.ini` and `conf/php-fpm.conf` use `${VAR}` placeholders (expanded by PHP / PHP-FPM at startup); their defaults are the `ENV PHP_*` / `PHP_FPM_PM*` block near the end of both Dockerfiles — an unset variable would expand to an empty value, so every placeholder needs an `ENV` default. nginx cannot read env vars: `render_nginx_runtime_conf` (entrypoint, default backend only) writes `/tmp/nginx/runtime.conf` (`client_max_body_size` from `NGINX_CLIENT_MAX_BODY_SIZE`, default `PHP_POST_MAX_SIZE`), included by the vhost; the http-level `client_max_body_size 10M` is the fallback when nginx is started without the entrypoint (Alpine's `nginx.conf` declares its own at http level: the Alpine Dockerfile deletes it, a duplicate is fatal). pcov is loaded but `pcov.enabled=${PHP_PCOV_ENABLED}` (0).

**Health check.** `HEALTHCHECK CMD docker-healthcheck`: if the default backend was started (marker: `/tmp/nginx/runtime.conf`, rendered by the entrypoint), `curl /healthz`, which the vhost maps to PHP-FPM's `ping.path` (`/fpm-ping`, suppressed from the FPM access log — `access.suppress_path` needs PHP ≥ 8.2); otherwise healthy (cron, workers, CLI, custom backend).

**nginx vhost** (`conf/nginx.vhost.conf`) is Symfony-shaped: front controller is `/application/public/index.php`, only `index.php` may execute PHP (all other `.php` → 404), `fastcgi_pass 127.0.0.1:9000`, `client_max_body_size 10M`.

## Pinned versions and supply chain

Every download is pinned through `ARG`s at the top of its `RUN`, and verified with a sha256 when the artifact is a raw download: `IPE_VERSION`/`IPE_SHA256` (install-php-extensions), `COMPOSER_VERSION`, `NODE_VERSION`/`NODE_SHA256` (different tarball, hence different sha, per variant), `YARN_VERSION`, `PNPM_VERSION`, `MJML_VERSION`, `SUPERCRONIC_VERSION`/`SUPERCRONIC_SHA256`. Bump them in both Dockerfiles together. PHP extensions themselves follow IPE's defaults for the pinned IPE version, and the `php:*-fpm-*` base is intentionally unpinned (the monthly scheduled rebuild picks up its security fixes). OCI labels (`org.opencontainers.image.*`) are declared last; CI passes `VCS_REF=$CI_COMMIT_SHA` for `org.opencontainers.image.revision`.

## Image size

- `.dockerignore` is an allowlist (`bin/`, `conf/`, `src/`): a new directory the Dockerfiles `COPY` must be added there.
- Files deleted in a later layer still weigh in the image: clean up in the same `RUN` that creates them (npm cache, `/tmp/node-compile-cache`, apt lists; `apk add --no-cache`, no `apk update`).
- Node is trimmed at install: headers/docs removed, binary `strip`ped. pnpm comes from npm (4 MB) rather than its standalone binary (62 MB, bundles its own Node).
- Alpine: `'!python3-pyc'` in `/etc/apk/world` forbids the Python bytecode packages supervisor would pull in.
- Debian: `/etc/dpkg/dpkg.cfg.d/mariadb-client-trim` path-excludes the rarely used ~5 MB mariadb tools (binlog, slap, conv, plugin, tzinfo-to-sql, waitpid, perror, replace, resolve_stack_dump). To get one back: delete that file and `apt install --reinstall mariadb-client`.
- Debian's base `php:*-fpm` keeps `$PHPIZE_DEPS` (gcc/g++/binutils, ~300 MB) in its own layers; only flattening the image could reclaim it (deliberately not done: loses shared base layers and base metadata).
- Measure with the sum of `docker history` layer sizes: with the containerd image store, `docker image inspect .Size` also counts the compressed blobs.

## CI/CD

`.gitlab-ci.yml` is the source of truth for published images (GitLab is primary; the repo mirrors to GitHub). It includes Infogene's standard code-scan template plus:
- `docker-build` — matrix `PHP_VERSION` [8.4, 8.5] × `OS` [alpine, debian], serialized via `resource_group`, `DOCKER_BUILDKIT: 0`. Pushes `:<ref>-<php>-<os>` to the GitLab registry on every MR / default-branch commit; the `OS_LATEST` + `PHP_VERSION_LATEST` combination (alpine, 8.4) also owns bare `:<ref>`, `:<php>` and `:latest`.
- Releases happen on a **git tag** *and* on a **monthly scheduled pipeline** (version derived from the date, `vYY-MM-DD`, rebuilding with `--pull` for base-image security fixes): versioned + floating tags go to the GitLab registry, and `ghcr-push` mirrors them to `ghcr.io/infogene/nginx-php`.
- Adding a PHP version or OS means updating both matrices (`docker-build` and `ghcr-push`).

The `Makefile` is for local/manual builds and pushes the same image coordinates.
