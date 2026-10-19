# Inventaire — clés publiques hors ci-v2

Empreintes des clés publiques seulement. Aucune ligne d'`authorized_keys` n'a été modifiée. Remplace `INVENTAIRE-CLES-DORMANTES.md` : ce titre rangeait des clés actives avec des clés réellement dormantes.

La clé partagée `helvetic-deploy-ci-v2` (`SHA256:DqVHx/gN8fidODUJzK4zUNBNMpWx2RLSW6Vf++qiQcY`) est dans `INVENTAIRE-CLE-CI-V2.md`. Elle n'est pas ici.

## Clés actives — Infomaniak FR

Trois clés du compte `deploy`. Elles ont ouvert une session le 17 octobre 2026. Les adresses source sont Azure : runners GitHub Actions. Les retirer arrêterait la CI qui s'en sert.

Relevé `auth.log` du 2026-10-19T02:26:22+0200 (maximum des horodatages, pas `tail -1` du dernier fichier).

| Empreinte | Commentaire | Dernière connexion | Depuis | Usage |
|---|---|---|---|---|
| `SHA256:hko4j4+wDduhUbzlabB+W8cM7nRNFpCaXYaH25tLT/E` | `ci-deploy-demenagements` | 2026-10-17T15:33:41Z | 40.122.245.35 | runner GitHub (Azure) |
| `SHA256:273/Uc0lsPCtNDxWNoNktvLGRMtivjFHv0cGTShZGvo` | `deploy-helveticleads` | 2026-10-17T15:34:32Z | 128.85.45.65 | runner GitHub (Azure) |
| `SHA256:BxhMVw9KQCQPSQtVGdPkjNEkkZ9Ks9mvjjtv/WuWS/I` | `ci_deploy_ia` | 2026-10-17T17:23:28Z | 172.190.124.68 | runner GitHub (Azure) |

Acceptées gardées dans les cinq fichiers encore là : 31, 31 et 39. Fichier `authorized_keys` : 2026-09-16 02:07 UTC. Relecture : 2026-11-18.

## Clés dormantes — Netcup

Deux clés, même commentaire `netcup-batiment-renovation`, empreintes différentes, comptes `deploy` et `root`. Relevé journal systemd du 2026-10-19T02:26:54+0200 (`/var/log/auth.log` n'existe pas sur cet hôte).

| Empreinte | Acceptées | Dernière | Depuis | Statut |
|---|---|---|---|---|
| `SHA256:/a9MJsa/laE6JE3RuEvlp4Im+I+8/yDWE3QjPuA4558` | 0 | — | — | jamais ouverte |
| `SHA256:IZ4/Frt87G8kg8SyuJskWXcfEuwM5fLVtwIgzDK/gb0` | 362 | 2026-08-26T19:14:56+0200 | 176.98.214.49 (`deploy`) | rien depuis le 26 août |

Ce sont les seules candidates au retrait de cet inventaire. La décision reste à Frédéric. Relecture : 2026-11-18.

La clé `helveticleads-netcup-2026-09-16` du compte root n'est pas dans cette liste : publique du poste, elle reste.

Toutes les clés de ce fichier sont ED25519.
