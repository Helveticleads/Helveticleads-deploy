# Garde anti-perte — scripts

Décision testable hors hôte, sur le modèle de `ops/garde-sitemap/`.

| Script | Rôle |
|--------|------|
| `decider.sh` | Décision pure (3 branches) — paramètres lus par le workflow |
| `classer-etat.sh` | Adaptateur local (`BASE=…`) pour les preuves |
| `rollback.sh` | Restaure PREV, sinon `ROLLBACK_VERS_NEANT` |
| `preuves.sh` | Suite permanente (8 cas) |

Appel sous `set -e`, codes 0/1/2, périmètre du branchement : `APPEL-WORKFLOW.md`.

## Échelle (une question : a-t-on déjà servi des pages ?)

1. **Aucune release avec `index.html` non vide** → laisser passer  
   - `current` absent → `GATE_SKIP anti_perte:premiere_release`  
   - `current` présent (placeholder, lien cassé, …) → `GATE_SKIP anti_perte:hote_provisionne`
2. **Au moins une release avec page, mais PREV n’en sert aucune** → `GATE_FAIL anti_perte:current_casse_sur_site_servi`
3. **PREV pointe une release avec pages** → comparaison servi ↔ bâti (`exit 2`)

Relevé hôtes du 2026-10-19 : `releve-hotes-2026-10-19.md`.

## Libellés retirés = témoins d'ancienneté

`GATE_FAIL anti_perte:SSH_ou_current_absent` n'existe plus. Sa présence dans un journal **identifie** un tag antérieur à `v1.2.4`. Ne jamais réutiliser une chaîne retirée.

## Présence ≠ validité

- Lien `current` : non seulement présent — **sert des pages** (`PREV_AVEC_PAGES`).
- Release : non seulement un dossier — **`index.html` non vide** (`-size +0`).
- Précédent de rollback : non seulement `PREV` non vide — **restaurable** (`test -d`).
