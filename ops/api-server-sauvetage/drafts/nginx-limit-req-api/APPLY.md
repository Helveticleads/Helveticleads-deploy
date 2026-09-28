## Où poser

1. Une fois : `http-snippet-limit_req-zone.conf` → `/etc/nginx/conf.d/`
2. Sur chaque `location /api/` qui `proxy_pass` vers `127.0.0.1:3000` :
   ajouter les deux lignes `limit_req` / `limit_req_status`.

Comptes vhosts → :3000 (mesure précédente) :
- ionos : 3 (+ debarrass hors réseau — ne pas toucher)
- lws : 18
- infomaniak-fr : 13
- infomaniak-de : 8
- hetzner : à confirmer au déploiement

Ordre serveur : IONOS → LWS → Infomaniak-FR → Infomaniak-DE → Hetzner.
`nginx -t` puis reload. Un serveur, attendre observation, suivant.

Hors périmètre : `domisane-suisse.ch`, `nuisibles-suisse.ch`.
