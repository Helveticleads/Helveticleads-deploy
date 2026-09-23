# Verrou par hôte — compte rendu

## Couverture (dénominateur)

**40 sites couverts / 56 mesurables** (4 hôtes), via le workflow réutilisable
`deploy-infomaniak.yml` (et `deploy-vite-standalone.yml` pour le même contrat).

**16 sites non couverts** : publication par rsync manuel (9 Hetzner DE,
schaedlinge-schweiz, helvetique-web, et autres sans `deploy.yml`). Un rsync
lancé à la main pendant un déploiement verrouillé **entrera quand même en
collision**. Ce verrou n’est pas total.

Hôtes couverts : LWS `180.149.199.219` (18) · Infomaniak FR `179.237.70.246` (13) ·
Infomaniak DE `179.237.70.207` (8) · IONOS `212.227.76.165` (1).

## Sonde droits (2026-09-23)

Chemin planifié `/var/www/.helveticleads-deploy-lock` :

| Hôte | mkdir `/var/www/…` | mkdir `$HOME/…` |
|---|---|---|
| LWS | **refusé** | OK |
| Infomaniak FR | OK | OK |
| Infomaniak DE | **refusé** | OK |
| IONOS | OK | OK |

→ défaut retenu : **`$HOME/.helveticleads-deploy-lock`** (`/home/deploy/…` pour l’utilisateur `deploy`). Toujours un mutex **par machine**.

## Mécanisme

Mutex **sur la machine cible**, pas GitHub concurrency.

- Prise : `mkdir $HOME/.helveticleads-deploy-lock` (atomique sur FS Linux)
- Métadonnées : `owner`, `taken_at`, `run_url`
- Relâche : `if: always()` si `LOCK_HELD=1`, seulement si `owner` == soi
- Orphelin : si âge > 1500 s (25 min) → `LOCK_STALE_RECLAIM` bruyant puis reprise
- Attente max : 2700 s (45 min) puis `LOCK_TIMEOUT` (échec, pas de deploy)

## Libération manuelle

Si plus rien ne se déploie sur un hôte :

```bash
ssh deploy@<HOST> 'rm -rf "$HOME/.helveticleads-deploy-lock" && echo LOCK_FORCE_CLEARED'
```

Ou :

```bash
ssh deploy@<HOST> 'bash -s' < ops/verrou-hote/liberer-manuel.sh
```

## Preuves locales

`bash ops/verrou-hote/preuves.sh` — atomicité, attente horodatée, hôtes
distincts, stale, timeout, relâche sur échec, pas de vol, neutralisation
grade 2, libération manuelle.

Preuve grade 1 **live** (deux deploys simultanés sur le même hôte) : hors de
ce dépôt (pas de `DEPLOY_SSH_KEY` ici) — nécessite GO explicite avant de
toucher un site en ligne.
