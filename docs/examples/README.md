# Docker Compose examples

Ready-to-run examples for `ghcr.io/infogene/nginx-php`. Each file is
self-contained: `docker compose -f <file>.yml up`.

| File | Demonstrates |
|---|---|
| [`backend-nginx-phpfpm.yml`](backend-nginx-phpfpm.yml) | Default backend: Nginx + PHP-FPM |
| [`backend-custom-command.yml`](backend-custom-command.yml) | `--start-backend "<cmd>"`: overriding the backend command |
| [`all-services.yml`](all-services.yml) | `--start-all`: backend + frontend under a single supervisord |
| [`supervisor-multi-programs.yml`](supervisor-multi-programs.yml) | `--start-supervisor-cli`: multiple explicit Supervisor programs |
| [`supervisor-worker.yml`](supervisor-worker.yml) | Background worker (Symfony Messenger), hardened |
| [`production-hardened.yml`](production-hardened.yml) | Nginx + PHP-FPM with healthcheck, `cap_drop: ALL`, `no-new-privileges`, read-only rootfs, resource limits |
| [`hardened-php-builtin.yml`](hardened-php-builtin.yml) | Same lockdown with PHP's built-in server: a single process, only `/tmp` writable |
| [`backend-user-root.yml`](backend-user-root.yml) | Default backend with the container running as root (minimal capabilities) |

Each example references the published image (`image:`). To test against the
repository sources, uncomment the `build:` block present in each file.

> The hardened examples expect the `[supervisord] logfile=/dev/null` fix in
> `bin/docker-supervisor-cli` (so supervisord never writes into the read-only
> `/application`). Rebuild the image from the current sources (`make build-tag`)
> if you are pinning an older published tag.

See the [main README](../../README.md) for the full list of options.
