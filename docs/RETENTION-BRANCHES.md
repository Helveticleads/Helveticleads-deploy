# Rétention des branches (règle — ne pas appliquer automatiquement)

Contexte : la règle « jamais `--delete-branch` à la fusion » est bonne au moment du merge.
Sans contrepartie, le dépôt et le parc accumulent des branches mortes (mesure : centaines
de branches de PR fusionnées + branches sans PR avec commits propres).

**Cette règle s’écrit ici. Elle ne s’exécute pas toute seule. Aucune suppression dans le
lot qui l’introduit.**

## Trois cas

| Cas | Critère | Délai | Action | Qui |
|-----|---------|------:|--------|-----|
| A — Fusionnée, sans commit unique | Branche dont tous les commits sont déjà dans la base de merge (`main` / branche cible) | **30 j** après merge | Suppression de la ref distante | Opérateur Helveticleads, après liste sèche |
| B — Fusionnée, travail resté dehors | Branche mergeée **mais** des commits de la branche ne sont pas ancêtres de `main` (rebase/squash partiel, commits orphelins utiles) | **90 j** après merge, ou dès archivage manuel du travail | Ne pas supprimer tant que les commits hors `main` n’ont pas de destination (autre branche / cherry-pick / abandon documenté) | Auteur de la PR + opérateur |
| C — Sans PR | Branche distante sans PR ouverte ni fusionnée associée | **60 j** sans push | Inventaire ; suppression seulement si l’auteur confirme « abandon » | Auteur de la branche |

## Garde-fous

- Jamais de `git push --delete` en masse sans liste publiée 48 h avant.
- Jamais `--force` sur `main`.
- Les tags `v1` / `v1.N.0` et les branches d’ops actives (`ops/*`, `fix/*` ouvertes) hors délai.
- Premium-Suisse-Leads : même règle, inventaire séparé (volume plus élevé).

## Exécution (quand on l’activera)

1. Script d’inventaire (lecture seule) → TSV : repo, branche, cas A/B/C, âge, URL PR.
2. Revue humaine.
3. Suppressions une à une ou par lot nommé, jamais `git add -A` / jamais stash.
