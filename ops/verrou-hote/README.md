# Verrou par hôte v2

Mutex sur la **machine cible** (`mkdir $HOME/.helveticleads-deploy-lock`), pas dans GitHub.
Deux sites du même VPS s’attendent ; deux hôtes restent parallèles.

## Pourquoi v2 (après #7 / #8)

#7 embarquait `prendre.sh` / `relacher.sh` dans un heredoc à l’intérieur d’un `run: |`.
Le corps du script était collé en **colonne 0** → YAML du workflow réutilisable invalide →
les callers `workflow_call` mouraient en 0 s. #8 a revert pour rétablir les déploiements.

**v2 :** scripts versionnés sous `ops/verrou-hote/`, exécutés par
`ssh … bash -s < ops/verrou-hote/prendre.sh` — aucun heredoc de script dans le YAML.

## Expiration (STALE)

Défaut **`STALE_SEC=1800` (30 min)**.

- Un Deploy site dure en pratique ~5–15 min ; 30 min ≈ 2× le chemin lent sans bloquer la nuit.
- Si le runner meurt sans `relacher`, un autre job reprend après 30 min (log `LOCK_STALE_RECLAIM`).
- `WAIT_MAX_SEC=2700` (45 min) : plafond d’attente si l’autre deploy est encore vivant.

## Couverture

Workflows réutilisables `deploy-infomaniak.yml` et `deploy-vite-standalone.yml` (~40 sites).
Les 16 publications manuelles (rsync hors Actions) restent hors verrou.

## Relâche

Step `if: always() && steps.verrou.outputs.held == '1'` — échec, annulation, succès.

## Preuves locales

```bash
bash ops/verrou-hote/preuves.sh
bash ops/verrou-hote/preuve-actionlint.sh
```
