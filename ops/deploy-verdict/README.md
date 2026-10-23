# Deploy — verdicts persistants

Quand un Deploy se termine, une **issue** du dépôt appelant reçoit un **commentaire**
(titre fixe `Deploy — verdicts`, label `deploy-verdict`).

| Classe | Origine | Label |
| --- | --- | --- |
| succes | step Cloturer apres succes | (base) |
| garde | fichier temoin `$RUNNER_TEMP/deploy-verdict.txt` (`GATE_FAIL …`) | `deploy-garde` |
| infra | `failure()` sans fichier temoin | `deploy-infra` |
| sabotage | verdict contenant `preuve_sabotage:` | + `deploy-sabotage` |

Chaque commentaire rappelle les **deux denominateurs KPI** : echecs Deploy × verdicts notifies.

`continue-on-error: true` sur les steps de notif/cloture — le job Deploy ne
redevient pas rouge si l'ecriture d'issue echoue. Dans ce cas le step ecrit :

```text
VERDICT NON NOTIFIÉ : <raison>
```

Les scripts s'executent depuis le checkout sparse de `Helveticleads/Helveticleads-deploy`
(`ops/deploy-verdict/`). `preuve-derive.sh` refuse tout autre prefixe.
