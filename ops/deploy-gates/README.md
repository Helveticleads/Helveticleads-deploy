# Gates build-time (avant rsync)

## `garde-noindex-racine.sh`

Refuse le déploiement si **`$SRC/index.html`** (racine du build) porte une
directive `noindex` — balise `meta robots` / `googlebot` / …, ou `X-Robots-Tag`
(`http-equiv` ou en-tête brut dans le fichier).

- **Racine seulement.** Une page interne (`/merci/`, etc.) en noindex est légitime.
- **Aucun drapeau de contournement.** Le seul passage : retirer le noindex du dépôt.
- **Motif imprimé** : directive + fichier + ligne + extrait.
- Branchée dans `deploy-infomaniak.yml` et `deploy-vite-standalone.yml`, étape
  **Gates build-time**, après présence de `index.html`, **avant** clé SSH / verrou / rsync.

Épreuve à blanc : `bash ops/deploy-gates/preuves-noindex.sh`
