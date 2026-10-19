# Garde actifs — préfixe

`classer-refs.sh` lit `index.html`.

| Références | Fichiers | Jeton |
|---|---|---|
| `/assets/*.js\|css` manquant ou vide | `--local` | `GATE_FAIL build:asset_manquant_ou_vide:…` |
| `/assets/*.js\|css` présents | `--local` | `GATE_OK assets:prefixe_assets n=…` |
| seulement `/_astro/*.js\|css` | non lus | `GATE_SKIP assets:arbre_non_couvert:/_astro/` |
| aucune | — | `GATE_OK assets:aucune_reference` |

`GATE_SKIP` nomme l'arbre non couvert. Un `GATE_OK` exigerait d'avoir ouvert le fichier. Schaedlinge (`/_astro/`) ne passe pas cette garde en silence : le skip est le jeton, pas une acceptation du préfixe.

`preuves.sh` : couple `/assets/` (absent FAIL / présent OK), couple `/_astro/` (absent et présent → le même SKIP), et le compte `astro-regex-assets-voit` = 0 (ce que l'ancienne boucle voyait avant d'écrire `GATE_OK`).
