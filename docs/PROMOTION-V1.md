# Promotion du pointeur `v1`

## Modèle

| Ref | Nature | Qui la déplace |
|-----|--------|----------------|
| `v1.N.0` (ex. `v1.0.0`) | **Immuable** — SHA figé, trace | Créée une fois, jamais déplacée |
| `v1` | **Mobile** — pointeur délibéré | Un humain, par geste explicite |

Les 53 appelants référencent `…/deploy-*.yml@v1` (et `verifier-cibles.yml@v1` le cas échéant).
Ils ne pointent **jamais** sur `v1.N.0` ni sur `main`.

Un tag couvre **tout** le dépôt : `deploy-infomaniak`, `deploy-vite-standalone`,
`verifier-cibles` — même SHA.

## Promouvoir une nouvelle version vers le parc

1. Fusionner sur `main` le changement voulu (ex. #18) — **sans** déplacer `v1`.
2. Vérifier CI sur `main` (actionlint, preuves locales pertinentes).
3. Créer le tag immuable au SHA de `main` :
   ```bash
   git fetch origin main
   git tag -a v1.N.0 origin/main -m "Helveticleads-deploy v1.N.0 — <motif>"
   git push origin v1.N.0
   ```
4. Sonde KPI : lire l’écart `main` ↔ `v1` (doit montrer les commits à promouvoir).
5. Déplacer le pointeur mobile (force-with-lease sur le tag annoté) :
   ```bash
   git tag -d v1
   git tag -a v1 origin/main -m "Helveticleads-deploy v1 → v1.N.0 (<motif>)"
   git push origin refs/tags/v1 --force
   ```
   ⚠ Seul cas où `--force` sur un tag est attendu : promotion délibérée de `v1`.
6. Vérifier la sonde : `v1` = `v1.N.0` = `main` (ou écart = 0 commits).
7. Optionnel — un dépôt témoin : inspecter le run Deploy et confirmer
   `uses: …@v1` résolu au SHA attendu (voir `docs/PROMOTION-V1.md` § Preuve).

## Revenir en arrière

1. Identifier le SHA sûr (souvent `v1.(N-1).0`).
2. Recréer `v1` sur ce SHA et `git push origin refs/tags/v1 --force`.
3. Ne **pas** supprimer les tags `v1.N.0` (trace).
4. Les runs en cours qui avaient déjà résolu `@v1` gardent l’ancien SHA jusqu’au prochain déclenchement.

## Ce que ce modèle n’est pas

- Ce n’est **pas** `@main` : `main` bouge à chaque fusion ; `v1` seulement par geste.
- Ce n’est **pas** 53 PR par promotion : une seule opération de tag.
