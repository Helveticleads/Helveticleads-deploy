# Garde marqueurs de conflit Git

Refuse un fichier qui contient **les trois** marqueurs `<<<<<<<` / `=======` / `>>>>>>>` en début de ligne.

- Un titre setext Markdown (`=======` seul) **passe**.
- Échappatoire documentation : une ligne `garde-marqueurs-ignore` (seule sur la ligne, éventuellement dans un commentaire) **ignore le fichier entier (annoncé GATE_SKIP, une ligne par fichier + count)**.

Preuves : `./preuves.sh`

Appelée depuis `deploy-infomaniak.yml` et `deploy-vite-standalone.yml` avant le build. Les appelants épinglés `@v1` ne la voient qu'après promotion de `v1`.
