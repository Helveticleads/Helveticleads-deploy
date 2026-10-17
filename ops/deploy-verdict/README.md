# Deploy — verdicts persistants

Quand un Deploy échoue, une **issue** du dépôt appelant reçoit un **commentaire**
(titre fixe `Deploy — verdicts`, label `deploy-verdict`). Le corps de l’issue n’est
pas réécrit. Un Deploy en **succès** commente puis ferme l’issue.

## Classes

| Classe | Origine | Label |
|--------|---------|-------|
| garde | fichier témoin `$RUNNER_TEMP/deploy-verdict.txt` (ligne `GATE_FAIL …`) | `deploy-garde` |
| infra | `failure()` sans fichier témoin | `deploy-infra` |
| sabotage | verdict contenant `preuve_sabotage:` | + `deploy-sabotage` (exclu du KPI) |

## Notification en panne

`continue-on-error: true` sur les steps de notif/clôture — le job Deploy ne
redevient pas rouge. En cas d’échec d’écriture d’issue, le step écrit dans
`$GITHUB_STEP_SUMMARY` :

```text
VERDICT NON NOTIFIÉ : <raison>
```

Le KPI croise runs Deploy en échec × verdicts produits ; un écart signale cette panne.

## Dérive

Ces scripts ne s’installent **nulle part** hors du dépôt. Le workflow les exécute
depuis le checkout sparse de `Helveticleads/Helveticleads-deploy` (`ops/deploy-verdict/`).
`preuve-derive.sh` refuse tout autre préfixe de chemin.
