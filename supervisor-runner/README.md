# Supervisor runner (générique)

Exemple d'utilisation de l'image de base du dépôt en mode « runner Supervisor » :
aucun fichier `supervisord.conf` ni `conf.d/*.conf` à fournir. La configuration est
générée au démarrage à partir des arguments `--supervisor-*` passés via `command:`
dans `docker-compose.yml`.

## Utilisation

```bash
docker compose up --build
# puis : http://localhost:18080  (nginx -> php-fpm -> phpinfo)
```

## Comment ça marche

L'image est construite depuis la racine du dépôt (`Dockerfile.alpine`). Son ENTRYPOINT
standard `bin/docker-entrypoint` reçoit l'option **`--start-supervisor-cli`** : il
transmet alors tous les `--supervisor-*` à `bin/docker-supervisor-cli`, qui :

1. Parse les arguments `--supervisor-*`.
2. Génère `/tmp/supervisord.conf` (`[supervisord]` + une section `[program]` **par** `--supervisor-program`).
3. Lance `exec supervisord -c ...`.

## `--supervisor-program` est répétable

Chaque `--supervisor-program "<cmd>"` ouvre une nouvelle section `[program]`. C'est la
façon correcte de superviser plusieurs services indépendamment (ici nginx **et**
php-fpm, chacun redémarré séparément) :

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

## Options et valeurs par défaut

Toutes les options ont un défaut → le `command:` reste minimal (`--start-supervisor-cli`
+ un `--supervisor-program` par service). Mapping `--supervisor-<a>-<b> VALUE` → `a_b=VALUE`.

| Argument CLI                       | Directive             | Défaut         |
|------------------------------------|-----------------------|----------------|
| `--supervisor-program "<cmd>"`     | `command=<cmd>`       | *(≥1 requis)*  |
| `--supervisor-program-name NAME`   | `[program:NAME]`      | `app`, `app2`… |
| `--supervisor-autostart BOOL`      | `autostart=BOOL`      | `true`         |
| `--supervisor-autorestart BOOL`    | `autorestart=BOOL`    | `true`         |
| `--supervisor-startretries N`      | `startretries=N`      | `3`            |
| `--supervisor-stopasgroup BOOL`    | `stopasgroup=BOOL`    | `true`         |
| `--supervisor-killasgroup BOOL`    | `killasgroup=BOOL`    | `true`         |
| `--supervisor-user USER`           | `user=USER`           | `www-data`     |
| `--supervisor-stdout-logfile PATH` | `stdout_logfile=PATH` | `/dev/stdout`  |
| `--supervisor-stderr-logfile PATH` | `stderr_logfile=PATH` | `/dev/stderr`  |

**Portée des options** :

- placées **avant** le 1er `--supervisor-program` → défaut **global** (tous les programmes) ;
- placées **après** un `--supervisor-program` → surcharge **ce** programme uniquement.

**Extensibilité (sans toucher au code)** : toute option `--supervisor-<a>-<b> VALUE`
devient `a_b=VALUE`. Ex. `--supervisor-numprocs 4` → `numprocs=4`,
`--supervisor-stop-signal TERM` → `stop_signal=TERM`.

## Points d'attention

- **Espaces / guillemets** : une commande applicative = **une seule ligne** de la liste
  `command:` (un item YAML = un argument argv). Elle est écrite telle quelle dans `command=`.
- **`user=`** : par défaut `www-data` = l'utilisateur de l'image, donc aucun besoin de root
  (le `setuid` est un no-op vers le même utilisateur). Pour superviser un process sous un
  *autre* utilisateur, lancez le conteneur en root (`user: "0"`).
- Démarré sans aucun `--supervisor-program`, le script s'arrête avec un message explicite.
- Aide : `docker run --rm <image> --start-supervisor-cli --help` (ou `docker-supervisor-cli --help` dans le conteneur).
