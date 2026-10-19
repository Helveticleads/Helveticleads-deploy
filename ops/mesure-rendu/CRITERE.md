# Critère de rendu — relevé 2026-10-19

## Mesure

Voir `releve-2026-10-19.tsv`. Pages saines : textLen 7 646–8 155, elements 670–925.
Pages cassées (racine vide / espaces) : textLen 0, elements 2–3.
`#root` et l’anti-bare-ref se trompent chacun dans un sens (casse les porte ; Astro/Next ne les ont pas).

## Seuil retenu (absolu, problème du jour)

La page a rendu si, sur le corps (scripts/styles exclus) :

- `textLen ≥ 200` **et** `elements ≥ 20`

`ET`, pas `OU` : un squelette (nav/pied) sans contenu aurait assez d’éléments et trop peu de texte — `OU` le laisserait passer.

Marge : la page saine la plus maigre mesurée fait 7 646 caractères (≈ 38× le seuil texte).

Implémenté : `mesurer-rendu.mjs` — Playwright mesure le corps **rendu** ; le repli et `post_http_root` mesurent le HTML **servi**. Plus de `#root` ni de `SITE_CONFIG` sur ce chemin.

## Réserve — piste rapport servi / bâti (ne pas écrire maintenant)

Un seuil absolu de 200 n’attrape que la page blanche. Une page qui ne rendrait qu’un dixième de son contenu (≈ 760 au lieu de 7 600) passerait.

Piste : comparer le texte visible du HTML servi à celui de `$SRC/index.html` (fichier déjà présent dans le workflow). Un rapport (ex. servi/bâti &lt; ½ ⇒ échec) évite un seuil arbitraire — même esprit que la garde anti-perte, appliqué au contenu d’une page plutôt qu’à l’inventaire d’URLs.

## Conséquence parc

`DE-schaedlinge-schweiz.ch` n’a plus de motif structurel pour rester hors socle (la garde cessera d’exiger `#root`). Chiffrage hors-socle : six → cinq, sans workflow écrit pour lui.
