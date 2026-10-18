# Inventaire — clé publique `helvetic-deploy-ci-v2`

Relevé du 2026-10-18. Ce fichier décrit la clé publique et les endroits où elle est autorisée. Il ne contient pas la clé privée.

## Empreinte

ED25519, commentaire `helvetic-deploy-ci-v2`.

`SHA256:DqVHx/gN8fidODUJzK4zUNBNMpWx2RLSW6Vf++qiQcY`

L'empreinte a été recalculée sur la ligne `authorized_keys` de `deploy` des cinq hôtes. Les cinq sont identiques.

## Où vit la privée

Retrouvée par Frédéric dans un classeur Excel sur son poste. Elle n'est pas dans `~/.ssh` de ce Mac. Elle ne doit pas être copiée dans ce dépôt.

Le secret GitHub qui est censé la porter s'appelle `DEPLOY_SSH_KEY`. Les valeurs des secrets ne sont pas lisibles : la présence du nom dans un dépôt ne prouve pas que la valeur est cette clé.

## Publique, compte `deploy`

| Hôte | Date du fichier `authorized_keys` |
|---|---|
| IONOS | 2026-09-16 05:14 +0200 |
| Hetzner | 2026-09-16 04:54 +0200 |
| Infomaniak FR | 2026-09-16 02:07 UTC |
| Infomaniak DE | 2026-09-16 02:08 UTC |
| LWS | 2026-09-16 03:36 +0200 |

La date est celle du fichier, pas celle de la ligne. Netcup ne porte pas cette publique.

## Où lire cet inventaire dans six mois

Les deux. Ce fichier, dans `Helveticleads-deploy`, pour les hôtes, l'empreinte et le nom du secret. Le gestionnaire de mots de passe, pour la privée et l'emplacement du classeur. Le classeur Excel n'est pas un registre : s'il est sur le Bureau ou dans iCloud Drive, il quitte la machine.
