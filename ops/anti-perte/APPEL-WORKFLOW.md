# Appel depuis le workflow — pièges et périmètre

Branché dans `deploy-infomaniak.yml` : checkout `_anti_perte`, puis
`decider.sh` (paramètres issus des lectures SSH) et `rollback.sh` (pipe SSH).

## Codes de sortie de `decider.sh`

| Code | Sens | Suite attendue |
|------|------|----------------|
| 0 | `GATE_SKIP anti_perte:premiere_release` **ou** `…:hote_provisionne` | laisser passer (pas de comparaison) |
| 1 | `GATE_FAIL …` | refuser le déploiement |
| 2 | `ANTI_PERTE_ETAT=prev_valide` | **continuer** — comparer servi ↔ bâti |

`2` signifie « tout va bien, enchaîne », pas une erreur.

### Piège `set -e`

Le step de déploiement est en `set -euo pipefail`. Un `exit 2` du script **tue le job** avant lecture de toute variable.

Capturer sans que `set -e` s’en mêle (déjà en place dans le YAML) :

```bash
set +e
DEC_OUT=$(… bash "_anti_perte/ops/anti-perte/decider.sh" 2>&1)
DEC_RC=$?
set -e
```

Ne jamais écrire `bash decider.sh` nu sous `set -e`.

## Périmètre du branchement

**Extraits** (scripts) :

- classification d’état (`PREV` / release complète / première release / `current` cassé) → `decider.sh`
- rollback post-garde → `rollback.sh`

**Restent volontairement** dans le YAML (hors script de décision) :

- `GATE_FAIL anti_perte:hote_injoignable` — sonde SSH avant toute lecture distante
- `GATE_FAIL anti_perte:bati=0` — inventaire du build local
- la comparaison servi ↔ bâti (301 mesurées) et ses jetons (`current_absent`, `servi_vide`, `perdues=…`)

« La garde anti-perte est extraite » = classification d’état + rollback, pas tout le fichier.

## Preuves vs exécution distante

Les cas de `preuves.sh` prouvent la **logique** sur un arbre local. Ils ne prouvent pas l’exécution SSH (timeouts, `readlink` distant, connexions coupées). Le filet workflow pour ça reste `hote_injoignable`. Logique prouvée ≠ transport distant prouvé.
