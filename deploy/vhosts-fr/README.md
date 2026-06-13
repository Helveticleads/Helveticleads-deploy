# Vhosts nginx — 3 nouveaux sites (préparation)

Fichiers **prêts mais non activés** — ne pas déployer sur nginx sans validation humaine.

| Fichier | Serveur | IP | Type |
|---------|---------|-----|------|
| `helvetique-maconnerie.ch.conf` | LWS FR | `180.149.199.219` | Prérendu (`$uri/index.html`) |
| `helvetique-carrelage.ch.conf` | LWS FR | `180.149.199.219` | Prérendu |
| `helvetique-elagage.ch.conf` | Infomaniak FR | `179.237.70.246` | Prérendu + proxy `/api/` |

## Activation (après validation)

1. Déployer le vhost sur le VPS cible (`sites-available` / `sites-enabled`).
2. Créer `/var/www/<domain>/releases/` et premier déploiement CI ou rsync manuel.
3. `nginx -t && systemctl reload nginx`
4. Certbot / TLS par domaine.

**Ne pas activer tant que le DNS et le premier build ne sont pas validés.**
