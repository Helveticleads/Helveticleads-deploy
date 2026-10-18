# Verrou par hôte v2

Mutex sur la **machine cible** (`mkdir $HOME/.helveticleads-deploy-lock`), pas dans GitHub.
Deux sites du même VPS s’attendent ; deux hôtes restent parallèles.

## Pourquoi v2 (après #7 / #8)

#7 embarquait `prendre.sh` / `relacher.sh` dans un heredoc à l’intérieur d’un `run: |`.
Le corps du script était collé en **colonne 0** → YAML du workflow réutilisable invalide →
les callers `workflow_call` mouraient en 0 s. #8 a revert pour rétablir les déploiements.

**v2 :** scripts versionnés sous `ops/verrou-hote/`, exécutés par
`ssh … bash -s < ops/verrou-hote/prendre.sh` — aucun heredoc de script dans le YAML.

## Expiration (STALE)

Défaut **`STALE_SEC=3600` (60 min)**.

- Un Deploy site observé (20–27) max ≈ 3 min ; 60 min laisse de la marge
  sans voler le verrou en cours. Le workflow ne redémarre pas d’api-server.
- Si le runner meurt sans `relacher`, un autre job reprend après 60 min (log `LOCK_STALE_RECLAIM`).
  Prix : un orphelin bloque l’hôte une heure — moins cher qu’un vol mid-bascule.
- `WAIT_MAX_SEC=5400` (90 min) : plafond d’attente du job avant `LOCK_TIMEOUT`.
  Distinct de STALE : WAIT_MAX = combien on attend son tour ; STALE = âge max de
  `taken_at` avant `LOCK_STALE_RECLAIM` (le battement s'est tu avec le runner).
- Pas de reprise automatique après `LOCK_TIMEOUT` : échec propre, relance manuelle.

## Heartbeat

Posé dans l'étape de déploiement de `deploy-infomaniak.yml`. `battement.sh`
réécrit `taken_at` dans une session `ssh` tenue par le runner, sans `nohup`.
La fin du step tue cette session. Si le runner meurt, ssh tombe, la boucle
reçoit SIGHUP, `taken_at` s'arrête, et `STALE` (60 min) reprend le verrou.
`relacher.sh` retire le répertoire dès que le job finit.

La forme écartée le 2026-10-18 : un `nohup` qui survivrait au job et laisserait
l'hôte bloqué jusqu'à un `rm`. Elle ne se pose pas.

## Pourquoi un seul Deploy à la fois sur le compte `deploy`

`rsync --delete` et la bascule de `current` (`ln -sfn` puis `mv -Tf`) touchent le
même compte. Deux publications simultanées sur ce compte s’écrasent. Rien d’autre
dans le workflow : pas de redémarrage d’api-server.

## Couverture

Workflow réutilisable `deploy-infomaniak.yml`. Il publie le contenu
(`releases/` et `current`). Il n'envoie pas le vhost nginx, le `.env`, ni `robots.txt`.
Un rsync lancé à la main sur le même compte passe à côté du verrou, même si le
dépôt a un `deploy.yml`. `FR-monjardiniersuisse.ch` et `FR-monexterminateursuisse.ch`
prennent déjà ce verrou dans leur propre workflow. `DE-schaedlinge-schweiz.ch` et
`FR-nuisibles-suisse.ch` publient par `deploy/deployer.sh`. `FR-domisane-suisse.ch`
et `DE-hausana-schweiz.ch` n'ont pas de script de publication dans le dépôt.

Les trois qui vont recevoir un workflow (domisane, hausana, schaedlinge-schweiz)
ne sont pas des workspaces pnpm : ils ne peuvent pas appeler `deploy-infomaniak.yml`.
Leur `deploy.yml` reprend le schéma monjardinier : `prendre.sh` avant le rsync,
`relacher.sh` ensuite, même répertoire de verrou, utilisateur `deploy`, checkout
de `ops/verrou-hote` sur `@v1`. Même exclusion : contenu seulement.

`helvetic-deploy-ci-v2` n'est pas dans `authorized_keys` de `deploy` sur Netcup
(`159.195.149.181`). Tant que cette clé publique n'y est pas, les workflows de
hausana et schaedlinge-schweiz ne peuvent pas se connecter. La poser, c'est ajouter
la publique (empreinte dans `docs/INVENTAIRE-CLE-CI-V2.md`) à ce fichier, pas la
privée. Ce n'est pas fait ici.

## Relâche

Step `if: always() && steps.verrou.outputs.held == '1'` — échec, annulation, succès.

## Sortie de secours (orphelin)

Si un job meurt sans relâcher et que STALE n’est pas encore atteint, le log
`LOCK_WAIT` / `LOCK_TIMEOUT` affiche :

```bash
ssh deploy@<HOST> 'rm -rf $HOME/.helveticleads-deploy-lock'
```

Équivalent versionné : `ops/verrou-hote/liberer-manuel.sh` (même effet, avec journal
owner/taken_at). Pas besoin de lire tout le dépôt : la commande est dans le log Actions.

## Preuves locales

```bash
bash ops/verrou-hote/preuves.sh
bash ops/verrou-hote/preuve-actionlint.sh
```
