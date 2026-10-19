# Relevés 2026-10-19 — rendu générique et hors socle
> Fichier de résidence. Les en-têtes de compte rendu se dérivent de ce fichier ;
> ne pas retaper les chiffres ailleurs sans mettre à jour ici.

## En-tête (3 lignes)
1. Rendu, repris de `ops/mesure-rendu/mesurer-rendu.mjs` : `textLen ≥ 200` **et** `elements ≥ 20` (scripts/styles exclus, pas de compte de mots, pas `#root`). Quatre cas `ops/mesure-rendu/preuves.sh` : `root-vide` FAIL, `squelette-sans-corps` FAIL, `page-saine-construite` OK, `vite-plomberie-servi` OK. Mesure d'où vient le seuil : 8 sites live + 4 synthétiques ; shell Vite `#root` vide = faux positif.
2. Hors socle : **5** dépôts (schaedlinge sort dès mode non-workspace + garde rendu) ; ordre : monex → monjardinier → nuisibles → Domisane/Hausana.
3. Mode schaedlinge : **pas** ressusciter `deploy-vite-standalone`. Sur `main` la gate `/assets` écrit `GATE_SKIP assets:arbre_non_couvert:/_astro/` quand la home ne référence que `/_astro/` — plus un `GATE_OK` qui n'a rien ouvert. `SITE_CONFIG` ne lit toujours que `$SRC/assets/`. Coût inchangé : **½ j + 2–4 h**, sauf `sitemap.xml` plat dans le dist **et** docroot Netcup déjà `releases/current` (non relu).

---

## 1. Mesure rendu (page servie)
Critère, repris du script (pas écrit à côté) : **ET** `textLen ≥ 200` et `elements ≥ 20`, scripts/styles exclus, pas de troisième conjoint « mots ». Quatre cas : `root-vide` FAIL, `squelette-sans-corps` FAIL, `page-saine-construite` OK, `vite-plomberie-servi` OK (`ops/mesure-rendu/preuves.sh`). Implémentation : `ops/mesure-rendu/mesurer-rendu.mjs`.

| kind | `#root` | body_tags≈elements | text_chars | words | sample |
| --- | --- | --- | --- | --- | --- |
| vite-fr helvetique-plomberie.ch | oui | 916 | 8173 | 1168 | Plombier en Suisse romande… |
| vite-de helvetic-reinigung.ch | oui | 558 | 5943 | 751 | Startseite Dienstleistungen… |
| astro schaedlinge-schweiz.ch | non | 723 | 7825 | 1133 | Direkt zum Inhalt… |
| next domisane-suisse.ch | non | 725 | 8386 | 1277 | Aller au contenu Domisane… |
| next hausana-schweiz.ch | non | 720 | 8190 | 1130 | Zum Inhalt springen Hausana… |
| static monexterminateursuisse.ch | non | 401 | 4485 | 629 | Suisse romande Votre message… |
| static monjardiniersuisse.ch | non | 567 | 5453 | 819 | Suisse romande Intervention… |
| nuisibles-suisse.ch | non | 711 | 7596 | 1162 | Aller au contenu principal… |
| synth blank-empty | non | 0 | 0 | 0 | — |
| synth blank-root-empty | **oui** | 1 | 0 | 0 | — |
| synth blank-loading | oui | 1 | 10 | 1 | Loading... |
| synth spa-shell-vite | **oui** | 2 | 0 | 0 | — |

Verdict : `#root` seul ne mesure pas le rendu (faux positif shell vide). Seuil ET sépare live (≥4485 car. / ≥401 élém.) des blanches (≤10 / ≤2).

---

## 2. Hors socle (parc FR/DE)
| Classe | Dépôts | Motif restant |
| --- | --- | --- |
| CENTRAL `deploy-infomaniak@v1` | 54 | — |
| OWN | 5 | voir ci-dessous |
| ~~schaedlinge~~ | 0 motif structurel `#root` | entre via **mode** non-workspace |

Les 5 :

| Dépôt | Stack | Filet actuel | Manque vs socle |
| --- | --- | --- | --- |
| FR-monexterminateursuisse.ch | HTML root | verrou + rsync + atomique + HTTP + gardes locales | anti-perte, sitemap-effet, rendu générique socle |
| FR-monjardiniersuisse.ch | HTML root | verrou + rsync + atomique + HTTP **seul** | le plus nu |
| FR-nuisibles-suisse.ch | build→dist | verrou + deployer.sh + audits build | anti-perte centrale |
| FR-domisane-suisse.ch | Next+PM2 | verrou + rsync + pm2 delete/start | hors famille Vite |
| DE-hausana-schweiz.ch | Next+PM2 | idem (Netcup) | idem |

Ordre de bascule : **monex → monjardinier** d’abord (Ecotox facturé / plus nu).

---

## 3. Mode non-workspace sur `deploy-infomaniak.yml` (schaedlinge)
### Ce que le workflow suppose aujourd’hui (workspace)
| Étape | Hypothèse figée |
| --- | --- |
| input `artifact` | **required** — nom package pnpm `@workspace/…` |
| Setup | `pnpm/action-setup` + cache pnpm |
| Install | `pnpm install --frozen-lockfile` (exige `pnpm-lock.yaml` + workspace) |
| Build | `pnpm --filter ${artifact} run build` |
| `SRC` | `$(pnpm --filter … cwd)/dist/public` |
| Gate assets | boucle `/assets/*.(js | css)` dans `index.html` |
| Gate SITE_CONFIG | `grep` sous `$SRC/assets/` |
| Preuve sabotage | chemin sous `dist/public` |

### Ce qu’est schaedlinge (mesuré)
| Fait | Valeur |
| --- | --- |
| Lockfile | `package-lock.json` (npm) — **pas** de `pnpm-lock.yaml` |
| Workspace | non (package à la racine) |
| Build | `npm run build` (Astro) |
| Sortie | `dist/` (pas `dist/public`) — `test -f dist/index.html` dans son deploy |
| Assets home live | **0** URL `/assets/*` ; chemins `/_astro/…` |
| Sitemap | `sitemap-index.xml` 200 ; `sitemap.xml` 404 |
| Hôte actuel | Netcup `159.195.149.181` (pas Infomaniak FR/DE typique) |

### Ce qui change pour le mode (paramètres, un seul workflow)
1. `artifact` **optionnel** ; si vide → mode racine.
2. Inputs ajoutés (ex.) : `package_manager` (`pnpm`\|`npm`), `build_command`, `output_dir` (défaut `dist/public` workspace / `dist` standalone).
3. Install / build branchés sur ces inputs (54 appelants inchangés si défauts = comportement actuel).
4. Gates `/assets` et `SITE_CONFIG` : déjà tolérantes si zéro match / pas de dossier `assets/` — **pas de skip render** ; le rendu générique couvre Astro.
5. Appelant schaedlinge : thin `workflow_call` + `host` / `domain` / `output_dir=dist` / `build_command=npm run build`.

### Coût
- **Demi-journée** (≈ 3–4 h) : 1 PR Helveticleads-deploy (mode + défauts rétrocompatibles) + 1 PR DE-schaedlinge (appelant) + 1 deploy de preuve.
- **Plus que demi-journée si** : la garde sitemap-par-effet refuse un `sitemap-index.xml` Astro sans `sitemap.xml` plat, ou si le docroot Netcup diverge du schéma `releases/current` attendu par l’anti-perte — alors +2–4 h de preuves ciblées, toujours sans second workflow.

Ne **pas** restaurer `deploy-vite-standalone.yml` (supprimé faute d’appelant ; un seul site ne justifie pas un second chemin).

---

## 4. Anti-marqueurs (état)
Drafts ouverts, **GO fusion suspendu** (quatre nuisibles) :

- Helveticleads-deploy `#34` — script + `GATE_SKIP` + step `deploy-infomaniak`
- FR-helvetique-nuisibles `#54`, FR-monexterminateursuisse `#12`, FR-helvetique-paysagiste `#14`

---

## 5. Dossiers clos (réf.)
- Hausana : `pm2 delete`+`start` depuis `current`, deploy vert, HTTPS 200.
- Domisane mémoire : plateau ~226–231 Mo / 10 min (pas une fuite).
- Échappatoire marqueurs : `garde-marqueurs-ignore` + `GATE_SKIP` bruyant.