# Restauration helvetic-comms — du fichier Storage Box au service qui répond

Procédure écrite le 2026-10-19 après un essai réel (dump de la nuit
`20261019T002144Z` → Postgres 17 jetable → comptages OK).

À lire **sans** accès à la machine `comms` : ce document vit dans le dépôt
`helvetic-comms` (clone local / GitHub) et une copie dans
`Helveticleads-deploy/docs/RESTAURATION-COMMS.md`.

## Ce dont on a besoin

| Élément | Où | Remarque |
|---|---|---|
| Dump données | Storage Box, dossier `postgres/` | `helvetic_comms-YYYYMMDDTHHMMSSZ.sql.gz.age` |
| Dump rôles | Storage Box, dossier `roles/` | `helvetic_comms-roles-….sql.gz.age` (depuis 2026-10-19) |
| Artefact Minio (optionnel) | Storage Box, dossier `minio/` | médias ; pas bloquant pour l’API seule |
| Clé **privée** age | Gestionnaire de mots de passe de Frédéric, et/ou `~/.config/age/helvetic-backup-2026-10.key` sur son Mac | **Jamais** sur comms. Sans elle les fichiers sont illisibles. |
| Clé publique (réf.) | `/etc/comms/backup.age.pub` sur le VPS, ou `ops/backup/backup.age.pub` dans le dépôt | Sert à chiffrer, pas à déchiffrer |
| Identité SSH Storage Box | `/etc/comms/ssh/id_ed25519_storagebox` sur comms, ou copie ops hors machine | Pour lister / récupérer les fichiers |

Avant le 2026-10-19 il n’y a **pas** de dump `roles/` sur la Box. Pour un
dump plus ancien : créer à la main les rôles `comms_owner`, `comms_admin`,
`comms_tenant`, `comms_webchat` (LOGIN, sans mot de passe fort si la base
n’écoute que en local) **avant** le restore des données, sinon les `GRANT`
en fin de dump échouent — les tables sont là, le service non.

## Ordre exact

### 1. Récupérer les deux fichiers les plus récents

Depuis une machine qui a l’identité Storage Box (souvent l’ancien VPS encore
joignable, ou un poste ops) :

```bash
# lister — vérifier noms et tailles (pas seulement le code de retour)
ssh storagebox 'ls -l postgres' | tail
ssh storagebox 'ls -l roles' | tail

scp storagebox:postgres/helvetic_comms-STAMP.sql.gz.age ./
scp storagebox:roles/helvetic_comms-roles-STAMP.sql.gz.age ./
# STAMP données et STAMP rôles du même run de backup de préférence
```

Tailles attendues (ordre de grandeur 2026-10) : données ~500 Ko chiffrées,
rôles beaucoup plus petits.

### 2. Déchiffrer (sur le Mac / poste qui a la privée)

```bash
age -d -i ~/.config/age/helvetic-backup-2026-10.key \
  -o helvetic_comms-STAMP.sql.gz \
  helvetic_comms-STAMP.sql.gz.age

age -d -i ~/.config/age/helvetic-backup-2026-10.key \
  -o helvetic_comms-roles-STAMP.sql.gz \
  helvetic_comms-roles-STAMP.sql.gz.age

gunzip -k helvetic_comms-STAMP.sql.gz
gunzip -k helvetic_comms-roles-STAMP.sql.gz
```

La clé se lit depuis le fichier d’identité ou le gestionnaire (export temporaire
fichier 600). Ne jamais coller la privée dans un chat, un ticket ou un journal.

### 3. Postgres 17 + rôles puis données

```bash
# stack minimale ou docker
docker run -d --name comms-pg-restore -e POSTGRES_PASSWORD=… -p 127.0.0.1:5432:5432 postgres:17
# attendre pg_isready

# 1) rôles d’abord
psql -U postgres -f helvetic_comms-roles-STAMP.sql

# 2) base applicative
psql -U postgres -c "CREATE DATABASE helvetic_comms;"
psql -U postgres -d helvetic_comms -v ON_ERROR_STOP=1 -f helvetic_comms-STAMP.sql
```

Sans l’étape rôles, `ON_ERROR_STOP=1` s’arrête sur `role "comms_owner" does not exist`
(et cousins). Avec les rôles, les `GRANT` passent.

### 4. Remonter le service

- `docker compose` : postgres, redis, minio (si besoin des médias)
- Variables `/etc/comms/deploy.env` + `/opt/comms/.env` (restituer depuis
  coffre ops, pas depuis le dump SQL)
- `systemctl start docker nginx comms.socket comms.service`
- DNS / certificats vers `comms.premiumhelveticleads.ch` et
  `widget.premiumhelveticleads.ch`

### 5. Vérifier que c’est bon

```bash
# comptages — comparer à ce qu’on savait juste avant l’incident
psql -U postgres -d helvetic_comms -c "
SELECT 'tables', COUNT(*) FROM information_schema.tables WHERE table_schema='public'
UNION ALL SELECT 'messages', COUNT(*) FROM messages
UNION ALL SELECT 'calls', COUNT(*) FROM calls
UNION ALL SELECT 'conversations', COUNT(*) FROM conversations
UNION ALL SELECT 'contacts', COUNT(*) FROM contacts
UNION ALL SELECT 'tenants', COUNT(*) FROM tenants
UNION ALL SELECT 'phone_numbers', COUNT(*) FROM phone_numbers;"

curl -fsS https://comms.premiumhelveticleads.ch/api/health
# Twilio : un webhook de test ou un appel d’essai si la ligne le permet
```

Référence d’essai du 2026-10-19 (dump 00:21 UTC vs prod le matin) :

| | Dump | Live |
|---|---:|---:|
| tables | 39 | 39 |
| messages | 127 | 157 |
| calls | 20 | 34 |
| conversations | 36 | 40 |
| contacts | 34 | 38 |
| tenants | 5 | 5 |
| phone_numbers | 13 | 13 |

Même nombre de tables + écart de lignes cohérent avec le temps écoulé = restore réussi.

## Ce qui est mort tant que comms l’est

- `comms.premiumhelveticleads.ch` — API (Twilio voice/SMS/status, inbox SSE,
  softphone, service CRM, auth console)
- `widget.premiumhelveticleads.ch` — loader/panel webchat + appels API publics
  (config, funnel, stream)
- Postgres / Redis / Minio locaux (données d’appel, sessions, médias)

Conséquence : pendant l’arrêt, les webhooks Twilio ne sont pas reçus — pas
d’enregistrement applicatif, pas de lead créé par cette voie pour les appels
de ce créneau.

## Ne pas confondre

- Présence d’un `.age` sur la Box ≠ dump restaurable (il faut la privée + les rôles).
- Code de retour `scp` ≠ fichier arrivé (le send vérifie la taille distante).
- Boot invité (~10–23 s) ≠ durée d’extinction panneau Hostinger (minutes).
