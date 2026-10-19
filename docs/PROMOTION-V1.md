# Promotion du pointeur `v1`

## Modèle

| Ref | Nature | Qui la déplace |
|-----|--------|----------------|
| `v1.N.0` (ex. `v1.0.0`) | **Immuable** — SHA figé, trace | Créée une fois, jamais déplacée |
| `v1` | **Mobile** — pointeur délibéré | Un humain, par geste explicite |

Les appelants référencent `…/deploy-*.yml@v1` (et `verifier-cibles.yml@v1` le cas échéant).
Ils ne pointent **jamais** sur `v1.N.0` ni sur `main`.

## Preuve d'un workflow réutilisable
Un workflow réutilisable **ne se teste pas chez lui**. Les variables de
contexte (`github.workflow_sha` vs `job.workflow_sha`, dépôt courant, etc.)
n'ont pas la même valeur selon qu'il tourne pour lui-même ou pour un
appelant. Toute preuve d'un câblage (checkout d'un script, secret hérité,
ref résolue) doit venir d'un dépôt appelant réel, épinglé temporairement
sur la ref sous test si besoin.


Un tag couvre **tout** le dépôt : `deploy-infomaniak`, `verifier-cibles` — même SHA.

## Protection du tag `v1*`

Ruleset GitHub **proteger-tags-v1** (cible `tag`, motif `refs/tags/v1*`) :
interdiction de mise à jour et de suppression, sauf contournement du rôle
**Admin** du dépôt. Un `--force` au hasard est refusé ; le déplacement reste un
geste délibéré du propriétaire.

Voir : https://github.com/Helveticleads/Helveticleads-deploy/rules/25349145

## Qui décide, sur quelle preuve

Frédéric décide. Un CI vert de Helveticleads-deploy ne suffit pas : il ne bâtit
aucun site.

Avant de déplacer `v1` :

1. Le changement est sur `main`, actionlint / preuves du dépôt verts.
2. **Épreuve** sur les sites dont le `build` lit l’historique git, **plus** un
   site dont le `build` ne le lit pas (témoin négatif : le clone complet ne
   casse rien ailleurs). Pas de déploiement, pas de bascule de `current`.
3. **GO explicite** de Frédéric entre l’épreuve et le déplacement du pointeur.

## Promouvoir une nouvelle version vers le parc

1. Fusionner sur `main` le changement voulu — **sans** déplacer `v1`.
2. Vérifier CI sur `main` (actionlint, preuves locales pertinentes).
3. Éprouver (sites à historique + témoin négatif). Obtenir le GO.
4. Créer le tag immuable au SHA de `main` :
   ```bash
   git fetch origin main
   git tag -a v1.N.0 origin/main -m "Helveticleads-deploy v1.N.0 — <motif>"
   git push origin v1.N.0
   ```
5. Sonde KPI : lire l’écart `main` ↔ `v1` (doit montrer les commits à promouvoir).
6. Déplacer le pointeur mobile (`--force-with-lease`, contournement Admin) :
   ```bash
   git fetch origin tag v1
   git tag -d v1
   git tag -a v1 origin/main -m "Helveticleads-deploy v1 → v1.N.0 (<motif>)"
   git push --force-with-lease=refs/tags/v1:$(git rev-parse refs/tags/v1^{}) origin refs/tags/v1
   ```
   Si `--force-with-lease` sur un tag annoté est refusé par le client, le
   contournement Admin + `git push origin refs/tags/v1 --force` reste le geste
   délibéré documenté ici — pas un réflexe hors procédure.
7. Vérifier la sonde : `v1` = `v1.N.0` = `main` (écart = 0 commits).
8. Optionnel — un dépôt témoin : run Deploy, confirmer `uses: …@v1` au SHA attendu.

## Revenir en arrière

1. Identifier le SHA sûr (souvent `v1.(N-1).0`).
2. Recréer `v1` sur ce SHA (même contournement Admin, même procédure).
3. Ne **pas** supprimer les tags `v1.N.0` (trace).
4. Les runs en cours qui avaient déjà résolu `@v1` gardent l’ancien SHA jusqu’au prochain déclenchement.

## Quelle version sert le parc

À tout moment : le SHA de `v1`. Les tags `v1.N.0` nomment les versions figées.
L’écart `v1..main` (sonde `sonde-epingle`) mesure le gel : s’il croît sans
promotion, le parc a cessé de bouger — ce n’est pas un silence sain.

## Ce que ce modèle n’est pas

- Ce n’est **pas** `@main` : `main` bouge à chaque fusion ; `v1` seulement par geste.
- Ce n’est **pas** N PR site par promotion : une seule opération de tag.
