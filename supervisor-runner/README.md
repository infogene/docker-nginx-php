# Supervisor runner (générique)

Image Docker générique pilotée par Supervisor. L'utilisateur ne fournit **aucun**
fichier `supervisord.conf` ni `conf.d/*.conf` : la configuration est générée au
démarrage à partir des arguments `--supervisor-*` passés via `command:` dans
`docker-compose.yml`.

## Utilisation

```bash
docker compose up --build
```

## Comment ça marche

`entrypoint.sh` :

1. Parse les arguments `--supervisor-*`.
2. Génère `/etc/supervisor/supervisord.conf` (`[supervisord]` + `[program:<name>]`).
3. Lance `exec supervisord -c ...`.

Mapping des options → directives de la section `[program]` :

| Argument CLI                       | Directive générée        | Défaut         |
|------------------------------------|--------------------------|----------------|
| `--supervisor-program "<cmd>"`     | `command=<cmd>`          | *(obligatoire)*|
| `--supervisor-program-name NAME`   | `[program:NAME]`         | `app`          |
| `--supervisor-autostart BOOL`      | `autostart=BOOL`         | `true`         |
| `--supervisor-autorestart BOOL`    | `autorestart=BOOL`       | `true`         |
| `--supervisor-startretries N`      | `startretries=N`         | `3`            |
| `--supervisor-user USER`           | `user=USER`              | `root`         |
| `--supervisor-stdout-logfile PATH` | `stdout_logfile=PATH`    | `/dev/stdout`  |
| `--supervisor-stderr-logfile PATH` | `stderr_logfile=PATH`    | `/dev/stderr`  |

**Extensibilité (sans toucher au code)** : toute option `--supervisor-<a>-<b> VALUE`
devient `a_b=VALUE`. Exemples :

- `--supervisor-numprocs 4` → `numprocs=4`
- `--supervisor-stopwaitsecs 30` → `stopwaitsecs=30`
- `--supervisor-stop-signal TERM` → `stop_signal=TERM`

## Points d'attention

- **Espaces / guillemets** : mettez la commande applicative sur **une seule ligne**
  de la liste `command:` (un item YAML = un argument argv). Aucun re-découpage n'est
  fait, la commande est écrite telle quelle dans `command=`.
- **`user=`** : supervisord tourne en `root` (voir `Dockerfile`) afin de pouvoir
  basculer (`setuid`) vers l'utilisateur demandé, p. ex. `www-data`.
- Démarré sans `--supervisor-program`, l'entrypoint s'arrête avec un message d'erreur explicite.
- `--help` affiche l'aide : `docker run --rm <image> --help`.
