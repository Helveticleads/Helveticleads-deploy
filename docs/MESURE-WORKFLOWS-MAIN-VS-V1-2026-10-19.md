# Mesure workflows `main` ↔ `v1` — 2026-10-19 (avant prochaine promotion)

À faire **avant toute promotion de `v1`** depuis `main` (et à chaque fois) :
ensembles de fichiers sous `.github/workflows/` sur `main` et sur `v1`,
puis appelants du parc. Si `v1 ⊄ main`, résoudre **avant** de déplacer le pointeur.

## Ensembles (mesurés ce jour)

| Ref | Fichiers `.github/workflows/` |
| --- | --- |
| `main` | actionlint, actions-heartbeat, deploy-infomaniak, detecteur-ecart, preuve-jeton-lecture, preuve-verrou-checkout, sonde-epingle, verifier-cibles |
| `v1` (= tip actuel, aligné `v1.2.4`) | **identique** |

- `v1 \ main` = ∅
- `main \ v1` = ∅ (au niveau des noms de workflows)

## `deploy-vite-standalone.yml`

- **Absent** de `main` et de **tous** les tags `v1` / `v1.2.x` mesurés.
- Retiré dans `14479f2` (« aucun appelant ») ; copie **locale** possible dans un clone, **pas** sur GitHub.
- Zéro `uses: …/deploy-vite-standalone.yml@…` dans un `.github/workflows/` du parc (seulement des `_DOCS` historiques).
- `docs/PROMOTION-V1.md` mentionne encore le nom — vestige à nettoyer à la prochaine édition.

## Appelants parc

| Workflow | Appelants |
| --- | --- |
| `deploy-infomaniak.yml@v1` | ~55 dépôts site (FR/DE helvetique / helvetic) |
| Workflow propre (pas le réutilisable) | Domisane, Hausana, monex, monjardinier, nuisibles-suisse, … |
| `deploy-vite-standalone` | **aucun** |

## Règle pour DEPLOY

Avant de déplacer `v1` : `comm` des listes `main` / `v1` sous `.github/workflows/`.
Si un fichier est sur `v1` et pas sur `main`, la promotion le **supprime** pour tout le parc au prochain run. Ne pas promouvoir dans cet état.
