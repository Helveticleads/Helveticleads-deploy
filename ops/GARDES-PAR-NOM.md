# Gardes du socle — nom exigé vs effet recherché

Filtre : si la garde exige un **nom** (fichier, sélecteur, étape) différent de l’**effet** qu’elle veut prouver, c’est une garde par nom.

| Garde | Exige (nom) | Cherche à prouver (effet) | Verdict |
|-------|-------------|---------------------------|---------|
| `ops/garde-sitemap/mesurer-effet.mjs` | — | sitemap non vide dont les URL = pages HTML indexables | **effet** (référence) |
| `guard-sitemap-equality.mjs` (sites) | **`routes.json`** | inventaire des pages prérendues indexables = locs du sitemap | **par nom** — `routes.json` atteste la liste des routes du build Vite/React ; à mesurer à la place : les `index.html` du dist (comme `mesurer-effet`) |
| Build `index.html` | fichier présent (désormais non vide) | le build a produit une entrée | effet (présence+taille) |
| Build assets référencés | chemins `/assets/*` non vides | les assets cités par l’entrée existent | effet |
| Build anti `SITE_CONFIG` | motif dans les bundles | pas de référence nue → page blanche | proxy raisonnable (effet « pas de motif interdit ») |
| Anti-perte `decider.sh` | — | site jamais servi / current cassé / comparaison | **effet** (pages sous releases/) |
| Anti-perte 301 | — | URL disparue a un 301 vers le bâti | effet |
| `post_http_root` | ~~`#root`~~ → `mesurer-rendu` | la page servie a du contenu | **effet** (après conversion) |
| `post_assets` | HTTP 200 sur assets cités | assets joignables en prod | effet |
| Rendu Playwright | ~~`#root`~~ → textLen≥200 **et** elements≥20 | la page a rendu du contenu | **effet** (après conversion) |
| Rendu heuristique | ~~`SITE_CONFIG` dans JS~~ → même `mesurer-rendu` | idem si Playwright KO | **effet** (après conversion) |
| Verrou `taken_at` | fichier témoin (désormais illisible ⇒ stale) | le verrou est encore tenu | présence≠validité (corrigé) |

## `routes.json` — quoi mesurer à la place

**Ce qu’il est censé attester :** la liste des routes prérendues (souvent émise par le pipeline Vite), pour la comparer au sitemap.

**Ce qu’on mesurerait à la place :** l’existence des pages elles-mêmes — ensemble des chemins `**/index.html` (hors 404) dans le dist, filtrés noindex — exactement l’entrée de `mesurer-effet.mjs`. Tant qu’une garde site exige le fichier `routes.json`, rongeurs/guêpes (autres producteurs) restent rouges pour un défaut de forme, pas d’effet.
