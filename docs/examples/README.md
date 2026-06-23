# Docker Compose examples

Ready-to-run examples for `ghcr.io/infogene/nginx-php`. Each file is
self-contained: `docker compose -f <file>.yml up`.

| File | Demonstrates |
|---|---|
| [`backend-nginx-phpfpm.yml`](backend-nginx-phpfpm.yml) | Default backend: Nginx + PHP-FPM |
| [`backend-custom-command.yml`](backend-custom-command.yml) | `--start-backend "<cmd>"`: overriding the backend command |
| [`all-services.yml`](all-services.yml) | `--start-all`: backend + frontend under a single supervisord |
| [`supervisor-multi-programs.yml`](supervisor-multi-programs.yml) | `--start-supervisor-cli`: multiple explicit Supervisor programs |
| [`supervisor-worker.yml`](supervisor-worker.yml) | `--start-supervisor-cli`: background worker (Symfony Messenger) |

Each example references the published image (`image:`). To test against the
repository sources, uncomment the `build:` block present in each file.

See the [main README](../../README.md) for the full list of options.
