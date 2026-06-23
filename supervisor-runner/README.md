# Supervisor runner (development scratch example)

Example of using the repository's base image in "Supervisor runner" mode: no
`supervisord.conf` or `conf.d/*.conf` file to provide. The configuration is
generated at startup from the `--supervisor-*` arguments passed via `command:` in
`docker-compose.yml`.

> For the canonical, copy-ready examples see [`../docs/examples/`](../docs/examples/).
> This folder builds from the repository sources and is used during development.

## Usage

```bash
docker compose up --build
# then: http://localhost:18080  (nginx -> php-fpm -> phpinfo)
```

## How it works

The image is built from the repository root (`Dockerfile.alpine`). Its standard
ENTRYPOINT `bin/docker-entrypoint` receives the **`--start-supervisor-cli`** option
(or `--start-backend` / `--start-frontend`): it then forwards all `--supervisor-*`
arguments to `bin/docker-supervisor-cli`, which:

1. Parses the `--supervisor-*` arguments.
2. Generates `/tmp/supervisord.conf` (`[supervisord]` + one `[program]` section **per** `--supervisor-program`).
3. Runs `exec supervisord -c ...`.

## `--supervisor-program` is repeatable

Each `--supervisor-program "<cmd>"` opens a new `[program]` section. This is the
correct way to supervise several services independently (e.g. nginx **and**
php-fpm, each restarted separately):

```yaml
command:
  - --start-supervisor-cli
  - --supervisor-program
  - php-fpm -F
  - --supervisor-program-name
  - php-fpm
  - --supervisor-program
  - nginx -g "daemon off;"
  - --supervisor-program-name
  - nginx
```

## Options and default values

Every option has a default, so the `command:` stays minimal (`--start-supervisor-cli`
+ one `--supervisor-program` per service). Mapping: `--supervisor-<a>-<b> VALUE` → `a_b=VALUE`.

| CLI argument | Directive | Default |
|---|---|---|
| `--supervisor-program "<cmd>"` | `command=<cmd>` | *(≥ 1 required)* |
| `--supervisor-program-name NAME` | `[program:NAME]` | `app`, `app2`… |
| `--supervisor-autostart BOOL` | `autostart=BOOL` | `true` |
| `--supervisor-autorestart BOOL` | `autorestart=BOOL` | `true` |
| `--supervisor-startretries N` | `startretries=N` | `3` |
| `--supervisor-stopasgroup BOOL` | `stopasgroup=BOOL` | `true` |
| `--supervisor-killasgroup BOOL` | `killasgroup=BOOL` | `true` |
| `--supervisor-user USER` | `user=USER` | `www-data` |
| `--supervisor-stdout-logfile PATH` | `stdout_logfile=PATH` | `/dev/stdout` |
| `--supervisor-stderr-logfile PATH` | `stderr_logfile=PATH` | `/dev/stderr` |

**Option scope**:

- placed **before** the 1st `--supervisor-program` → **global** default (all programs);
- placed **after** a `--supervisor-program` → overrides **that** program only.

**Extensible (no code change)**: any `--supervisor-<a>-<b> VALUE` option becomes
`a_b=VALUE`. E.g. `--supervisor-numprocs 4` → `numprocs=4`,
`--supervisor-stop-signal TERM` → `stop_signal=TERM`.

## Notes

- **Spaces / quotes**: one application command = **one line** in the `command:` list
  (one YAML item = one argv argument). It is written verbatim into `command=`.
- **`user=`**: defaults to `www-data` = the image's user, so no root is needed (the
  `setuid` is a no-op to the same user). To supervise a process as a *different*
  user, run the container as root (`user: "0"`).
- Started without any `--supervisor-program`, the script exits with an explicit message.
- Help: `docker run --rm <image> --start-supervisor-cli --help` (or `docker-supervisor-cli --help` inside the container).
