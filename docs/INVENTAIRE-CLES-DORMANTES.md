# Inventaire — cinq clés publiques non retirées

Relevé du 2026-10-18. Empreintes des clés publiques seulement. Aucune ligne d'`authorized_keys` n'a été modifiée.

Ces cinq clés ne sont pas retirées : la privée n'est pas sur ce Mac, aucun secret GitHub ne porte leur nom (seul `DEPLOY_SSH_KEY` existe, et sa valeur est illisible), et `deploy` ne peut pas lire `auth.log`. On ne peut donc prouver, pour aucune, qu'un déploiement ne s'en sert pas.

| Empreinte | Commentaire | Hôte | Compte | Fichier |
|---|---|---|---|---|
| `SHA256:hko4j4+wDduhUbzlabB+W8cM7nRNFpCaXYaH25tLT/E` | `ci-deploy-demenagements` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC |
| `SHA256:273/Uc0lsPCtNDxWNoNktvLGRMtivjFHv0cGTShZGvo` | `deploy-helveticleads` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC |
| `SHA256:BxhMVw9KQCQPSQtVGdPkjNEkkZ9Ks9mvjjtv/WuWS/I` | `ci_deploy_ia` | Infomaniak FR | deploy | 2026-09-16 02:07 UTC |
| `SHA256:/a9MJsa/laE6JE3RuEvlp4Im+I+8/yDWE3QjPuA4558` | `netcup-batiment-renovation` | Netcup | deploy et root | deploy 2026-08-07 22:46 +0200 ; root 2026-09-16 05:10 +0200 |
| `SHA256:IZ4/Frt87G8kg8SyuJskWXcfEuwM5fLVtwIgzDK/gb0` | `netcup-batiment-renovation` | Netcup | deploy et root | deploy 2026-08-07 22:46 +0200 ; root 2026-09-16 05:10 +0200 |

Toutes sont ED25519. La date est celle du fichier `authorized_keys`, pas celle de la ligne. Les deux clés Netcup portent le même commentaire et des empreintes différentes. La clé `helveticleads-netcup-2026-09-16` du compte root n'est pas dans cette liste : c'est la publique du poste, elle reste.

La décision de rotation revient à Frédéric.
