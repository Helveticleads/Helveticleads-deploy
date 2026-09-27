# Bascule IONOS — runbook (exécutable le jour J)

Hôte : `deploy@212.227.76.165`  
Unité : `helvetic-api`  
Dist servi : `/opt/helvetic-api/app/artifacts/api-server/dist/`  
Env : `/etc/helvetic/api.env`  
Profil : `HOST_PROFILE=ionos`  
Fenêtre : **22:00 Europe/Zurich** (0 lead / 7 j. comme 04/06/07/09–12/23 ; quelqu’un est réveillé pour un rollback).

**Interdit le jour J tant que GO explicite :** déploiement sur l’hôte, jetons CRM, nginx `debarrass-tout.be`.

---

## Prérequis (déjà construits)

- `reconciled/src/index.ts` — `HOST_PROFILE` → `setActiveHostProfile`, exige `PORT`
- `npm run build` → `dist/index.mjs` (+ `.map`)
- `npm run ci` = caractérisation + build + smoke boot
- Workflow CI : build/test seulement (aucun déploiement)

---

## HOST_PROFILE et l’ancien binaire

L’extract IONOS n’exige que `PORT`. `HOST_PROFILE` est **ignoré** par l’ancien binaire.  
→ Rollback de `dist/` seul suffit.

---

## Drill rollback (AVANT la vraie bascule) — préfixe `dist.drill-`

Ne pas utiliser `dist.bak-` ici : ce préfixe est réservé à la vraie bascule.

Au moment du premier rename, **écrire la commande de rollback avec le chemin littéral** (pas `$TS`) dans un fichier prêt à coller, puis l’exécuter.

```bash
API=/opt/helvetic-api/app/artifacts/api-server
DRILL=dist.drill-$(date +%Y%m%d-%H%M%S)
# Exemple si date = 20260927-220105 → DRILL=dist.drill-20260927-220105
# Remplacer ci-dessous par la valeur réelle affichée :
echo "DRILL=$DRILL"
cp -a "$API/dist" "$API/dist.new"
mv "$API/dist" "$API/$DRILL"
mv "$API/dist.new" "$API/dist"

# Écrire le rollback LITTERAL (exemple — ajuster l’horodatage réel) :
cat > /tmp/ROLLBACK-IONOS-DRILL.sh <<'EOF'
#!/bin/bash
set -euo pipefail
API=/opt/helvetic-api/app/artifacts/api-server
mv "$API/dist" "$API/dist.abort-drill"
mv "$API/dist.drill-20260927-220105" "$API/dist"
systemctl restart helvetic-api
EOF
# ↑ remplacer dist.drill-20260927-220105 par la valeur echo'ée de $DRILL

chmod +x /tmp/ROLLBACK-IONOS-DRILL.sh
bash /tmp/ROLLBACK-IONOS-DRILL.sh
systemctl is-active helvetic-api
sleep 60
systemctl is-active helvetic-api
# attendu : active ×2

# Nettoyer le drill AVANT de poser le vrai contenu
rm -rf "$API/dist.drill-"* "$API/dist.abort-drill" /tmp/ROLLBACK-IONOS-DRILL.sh
test ! -e "$API/dist.new"
```

Seulement si le drill est vert → bascule réelle.

---

## Bascule atomique (pas de rsync dans `dist/`)

```bash
API=/opt/helvetic-api/app/artifacts/api-server
BAK=dist.bak-$(date +%Y%m%d-%H%M%S)
echo "BAK=$BAK"
# 1) Vrai contenu déjà dans dist.new/ — vérifier
test -f "$API/dist.new/index.mjs"
test -s "$API/dist.new/index.mjs"
# 2) Écrire le rollback LITTERAL AVANT les renames (ajuster l’horodatage)
cat > /tmp/ROLLBACK-IONOS.sh <<EOF
#!/bin/bash
set -euo pipefail
API=/opt/helvetic-api/app/artifacts/api-server
mv "\$API/dist" "\$API/dist.failed"
mv "\$API/$BAK" "\$API/dist"
systemctl restart helvetic-api
EOF
chmod +x /tmp/ROLLBACK-IONOS.sh
# Vérifier le fichier : cat /tmp/ROLLBACK-IONOS.sh  (chemin dist.bak-… littéral, sans \$TS)
# 3) Deux renames
mv "$API/dist" "$API/$BAK"
mv "$API/dist.new" "$API/dist"
```

Le snapshot **est** le premier `mv`. Une seule sauvegarde `dist.bak-<horodatage>` ; le drill a été retiré.

### Rollback une commande (forme finale — exemple)

Après le snapshot du jour J, `/tmp/ROLLBACK-IONOS.sh` contient déjà le littéral. Exemple si `BAK=dist.bak-20260927-220310` :

```bash
mv /opt/helvetic-api/app/artifacts/api-server/dist /opt/helvetic-api/app/artifacts/api-server/dist.failed && mv /opt/helvetic-api/app/artifacts/api-server/dist.bak-20260927-220310 /opt/helvetic-api/app/artifacts/api-server/dist && systemctl restart helvetic-api
```

Ou : `bash /tmp/ROLLBACK-IONOS.sh`

---

## Ordre jour J (fenêtre **22:00 Europe/Zurich**)

1. Drill (`dist.drill-…`) + rollback littéral + `is-active` t+0 et t+60 → **retirer** tout `dist.drill-*`.
2. Poser le vrai contenu dans `dist.new/` (reconciled).
3. `HOST_PROFILE=ionos` dans `/etc/helvetic/api.env` **avant** le rename (ancien binaire ignore la clé).
4. Écrire `/tmp/ROLLBACK-IONOS.sh` avec chemin `dist.bak-…` **littéral**.
5. `mv dist → dist.bak-…` puis `mv dist.new → dist`.
6. `systemctl restart helvetic-api`
7. `systemctl is-active` immédiat, puis encore après **60 s**.
8. Lead de preuve (ci-dessous).
9. Si échec → `bash /tmp/ROLLBACK-IONOS.sh` (ou la commande littérale ci-dessus).

---

## Lead de preuve — domaine à zéro lead (pas monjardinier / monexterminateur)

Les boîtes actives (17 + 8 leads / 7 j.) ne doivent **pas** recevoir la sonde.

Domaine retenu : **`helvetique-terrassement.ch`** (0 lead sur le relevé ; jeton présent ; in-scope).  
Alternatives zéro lead in-scope : `domisane-suisse.ch`, `nuisibles-suisse.ch`.  
**Pas** `debarrass-tout.be` (hors périmètre).  
**Pas** `monjardiniersuisse.ch` / `monexterminateursuisse.ch`.

Marqueur :

- `name`: `BASCULE-IONOS-PROBE-<horodatage>`
- `email`: `bascule-ionos-probe+<horodatage>@premiumhelveticleads.ch` (boîte contrôlée)
- `phone`: numéro de test interne documenté
- `message`: `PROBE bascule api-server IONOS <horodatage> — à supprimer`
- Host / site : `helvetique-terrassement.ch`

Attendu : HTTP 201, `channels` avec `email` (et `crm` si push OK).

### Retrait après preuve

1. Noter `lead_id` et `crm_lead_id`.
2. CRM : supprimer la fiche (UI / admin — pas de régénération de jeton).
3. Hôte : `rm -f /var/lib/helvetic-api/crm-sent/<lead_id>`
4. E-mail déjà parti vers la boîte du domaine sondé (terrassement, inactive sur 7 j.) — libeller PROBE ; pas de fiche CRM laissée.

---

## Hors périmètre rappel

`debarrass-tout.be` : aucun jeton, aucune fiche, aucun nginx. Token absent → warn + e-mail continue (identique extract / reconciled).
