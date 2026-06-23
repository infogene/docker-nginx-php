# Exemples Docker Compose

Exemples prêts à l'emploi pour `ghcr.io/infogene/nginx-php`. Chaque fichier est
autonome : `docker compose -f <fichier>.yml up`.

| Fichier | Démontre |
|---|---|
| [`backend-nginx-phpfpm.yml`](backend-nginx-phpfpm.yml) | Backend par défaut : Nginx + PHP-FPM |
| [`backend-custom-command.yml`](backend-custom-command.yml) | `--start-backend "<cmd>"` : surcharge de la commande backend |
| [`all-services.yml`](all-services.yml) | `--start-all` : backend + frontend sous un seul supervisord |
| [`supervisor-multi-programs.yml`](supervisor-multi-programs.yml) | `--start-supervisor-cli` : plusieurs programmes Supervisor explicites |
| [`supervisor-worker.yml`](supervisor-worker.yml) | `--start-supervisor-cli` : worker en arrière-plan (Symfony Messenger) |

Chaque exemple référence l'image publiée (`image:`). Pour tester depuis les
sources du dépôt, décommentez le bloc `build:` présent dans chaque fichier.

Voir le [README principal](../../README.md) pour la liste complète des options.
