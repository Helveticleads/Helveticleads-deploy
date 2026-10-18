# Inventaire — cinq clés publiques non retirées

Relevé du 2026-10-18. Empreintes des clés publiques seulement. Aucune ligne d'`authorized_keys` n'a été modifiée.

Ces cinq clés ne sont pas retirées : la privée n'est pas sur ce Mac, aucun secret GitHub ne porte leur nom (seul `DEPLOY_SSH_KEY` existe, et sa valeur est illisible), et `deploy` ne peut pas lire `auth.log`. On ne peut donc prouver, pour aucune, qu'un déploiement ne s'en sert pas.

| Empreinte | Commentaire | Hôte | Compte | Fichier | Relecture |
|---|---|---|---|---|---|---|
| `SHA256:hko4j4+wDduhUbzlabB+W8cM7nRNFpCaXYaH25tLT/E` | `ci-deploy-demenagements` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC | 2026-11-18 |
| `SHA256:273/Uc0lsPCtNDxWNoNktvLGRMtivjFHv0cGTShZGvo` | `deploy-helveticleads` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC | 2026-11-18 |
| `SHA256:BxhMVw9KQCQPSQtVGdPkjNEkkZ9Ks9mvjjtv/WuWS/I` | `ci_deploy_ia` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC | 2026-11-18 |
| `SHA256:/a9MJsa/laE6JE3RuEvlp4Im+I+8/yDWE3QjPuA4558` | `netcup-batiment-renovation` | Netcup | deploy et root | deploy 2026-08-07 22:46 +0200 ; root 2026-09-16 05:10 +0200 | 2026-11-18 |
| `SHA256:IZ4/Frt87G8kg8SyuJskWXcfEuwM5fLVtwIgzDK/gb0` | `netcup-batiment-renovation` | Netcup | deploy et root | deploy 2026-08-07 22:46 +0200 ; root 2026-09-16 05:10 +0200 | 2026-11-18 |

Relecture : le 2026-11-18, on relit ces cinq lignes. Trente jours après le relevé. La rotation, si elle a lieu, est décidée avant cette date par Frédéric.

Toutes sont ED25519. La date est celle du fichier `authorized_keys`, pas celle de la ligne. Les deux clés Netcup portent le même commentaire et des empreintes différentes. La clé `helveticleads-netcup-2026-09-16` du compte root n'est pas dans cette liste : c'est la publique du poste, elle reste.

La décision de rotation revient à Frédéric.

## Dernière connexion — à lire dans `auth.log` une fois `deploy` dans `adm`

`adm` ouvre `auth.log`. C'est le second chantier de `usermod -aG adm deploy` sur les cinq hôtes : pour chaque empreinte, la dernière ligne `Accepted publickey`, et l'adresse source. La commande n'a pas été exécutée. Les journaux sont encore refusés à `deploy` (vérifié sur ionos le 19 octobre, 00 h 59).

La requête, nouvelle session SSH après le `usermod`. Elle ne retire rien.

```bash
# Infomaniak FR — les trois clés du compte deploy
ssh infomaniak-fr 'for fp in \
  "SHA256:hko4j4+wDduhUbzlabB+W8cM7nRNFpCaXYaH25tLT/E" \
  "SHA256:273/Uc0lsPCtNDxWNoNktvLGRMtivjFHv0cGTShZGvo" \
  "SHA256:BxhMVw9KQCQPSQtVGdPkjNEkkZ9Ks9mvjjtv/WuWS/I"
do
  echo "== $fp"
  zgrep -h -F "$fp" /var/log/auth.log /var/log/auth.log.* 2>/dev/null | grep "Accepted publickey" | tail -1
done'

# Netcup — les deux empreintes, comptes deploy et root (root lit déjà auth.log)
ssh netcup 'for fp in \
  "SHA256:/a9MJsa/laE6JE3RuEvlp4Im+I+8/yDWE3QjPuA4558" \
  "SHA256:IZ4/Frt87G8kg8SyuJskWXcfEuwM5fLVtwIgzDK/gb0"
do
  echo "== $fp"
  zgrep -h -F "$fp" /var/log/auth.log /var/log/auth.log.* 2>/dev/null | grep "Accepted publickey" | tail -1
done'
```

Une ligne absente veut dire : aucune connexion acceptée avec cette empreinte dans les fichiers encore là. La rotation d'`auth.log` ne garde pas l'historique depuis le 16 septembre. La ligne, quand elle existe, porte l'heure et `from <adresse>`.
