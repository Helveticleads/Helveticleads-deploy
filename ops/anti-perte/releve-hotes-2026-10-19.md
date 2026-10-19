# Relevé hôtes — quatre nuisibles neufs (2026-10-19)

Lecture seule, `deploy@179.237.70.246` (Infomaniak FR). Voir `releve-hotes-2026-10-19.tsv`.

## 1. Les quatre portent-ils `releases/placeholder` ?

Oui, les quatre. `current` → `releases/placeholder` partout. Pas un accident isolé : état normal d’un hôte fraîchement provisionné dans ce parc (trois créés à la même seconde `12:47:15` UTC le 17 oct.).

## 2. Contenu du placeholder

Dossier **nu** : 0 fichier, pas d’`index.html`. Déjà « non complet » pour le test `find … -name index.html`. Pas besoin d’une condition de contenu supplémentaire pour ce lot (un `index.html` vide n’a pas été observé ; le critère garde `-size +0` par prudence).

## 3. Qui le pose, pourquoi

- nginx : `root /var/www/<domaine>/current;` (mesuré sur pro-nuisibles).
- `placeholder/` et le lien `current` créés ensemble (mêmes mtimes), propriétaire `deploy:deploy` (sauf le lien rongeurs : `root:root`).
- Rôle : donner une racine existante à nginx avant le premier déploiement réel — raisonnable, à intégrer, pas à supprimer.

## Conséquence pour `v1.2.4`

Sur pro / guêpes / punaise : `PREV` résout → comparaison → inventaire servi vide → `servi_vide`. `premiere_release` n’est jamais atteint. Rongeurs : placeholder + deux releases pleines (sept.) — autre profil ; contournement manuel hors périmètre.
