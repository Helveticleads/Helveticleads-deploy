# Inventaire des clés de déploiement

Helveticleads est un **compte personnel** : pas de secret d’organisation.
`DEPLOY_SSH_KEY` est un secret de **dépôt**. Sa dispersion doit rester visible.

## Trois sources

| Source | Fichier / geste | Ce qu’elle capture |
|---|---|---|
| **(a) déclaré** | `depots-declares.txt` (commit) | Intention — se périme en silence |
| **(b) utilise** | workflows du dépôt | Référence `secrets.DEPLOY_SSH_KEY`, **ou** appel à `deploy-infomaniak.yml` / `deploy-vite-standalone.yml` (consommateurs via `secrets: inherit`) |
| **(c) porte** | API `GET …/actions/secrets` | Nom + `updated_at` — **jamais** la valeur |

(b) et (c) sont deux gestes séparés (commit vs saisie UI) : c’est le recoupement.
Deux sources dont l’une est un fichier tenu à la main n’en seraient pas un.

## Listes de sortie

1. **utilise mais ne porte pas**
2. **porte mais n’utilise pas**
3. **déclaré mais ni l’un ni l’autre**

Plus, pour chaque dépôt qui porte la clé : sa date de mise à jour.

## Recommandation (pose chez Frédéric)

Quatre clés **distinctes** autorisées sur le même compte `deploy@<hôte>`, pas une clé
copiée quatre fois. Même coût à poser ; révoquer un dépôt = retirer une ligne dans
`authorized_keys` au lieu d’une rotation sur quatre ; une fuite n’en compromet qu’un.

## Exécution

```bash
GH_TOKEN=… bash ops/inventaire-cles/sonde-inventaire-cles.sh
```

Workflow : `.github/workflows/sonde-inventaire-cles.yml` (schedule + dispatch).
