# Bascule api-server — runbook IONOS (1/5)

Réutilisable pour Hetzner → Infomaniak FR → LWS → Infomaniak DE : même **procédure commune**.  
Changer uniquement le bloc **Paramètres de cet hôte**.

**Exécution :** uniquement sur GO de Frédéric avec une **date** (fenêtre 22:00 Europe/Zurich).  
En cas d’anomalie : rollback immédiat, STOP. Pas d’aller-retour entre les étapes.

---

## Paramètres de cet hôte — IONOS seulement

À remplacer tel quel pour un autre hôte (ne pas mélanger avec la procédure).

| Clé | Valeur IONOS |
|---|---|
| SSH | `deploy@212.227.76.165` (clé `~/.ssh/id_ed25519_ionos`) |
| `API` | `/opt/helvetic-api/app/artifacts/api-server` |
| Unité systemd | `helvetic-api` |
| Env file | `/etc/helvetic/api.env` |
| `HOST_PROFILE` | `ionos` |
| Fenêtre | **22:00 Europe/Zurich** |
| Sonde — domaine | `helvetique-terrassement.ch` (0 lead / 7 j. ; **pas** monjardinier / monexterminateur) |
| Sonde — exclus | `monjardiniersuisse.ch`, `monexterminateursuisse.ch`, `debarrass-tout.be` |
| Sonde — marqueur | `BASCULE-IONOS-PROBE-<horodatage>` |
| Sonde — email | `bascule-ionos-probe+<horodatage>@premiumhelveticleads.ch` |
| `crm-sent` | `/var/lib/helvetic-api/crm-sent/` |
| Hors périmètre | `debarrass-tout.be` (pas de jeton / fiche / nginx) |

Prérequis binaire (déjà dans le dépôt) : `npm run build` → `dist/index.mjs` ; boot exige `HOST_PROFILE`.  
Ancien binaire (tous hôtes mesurés) : n’exige que `PORT` → ignore `HOST_PROFILE` tant qu’il tourne.

---

## Procédure commune — les cinq hôtes

Même chemin partout. Les chemins ci-dessous utilisent `$API` / l’unité / le profil du bloc paramètres.

### A. Drill rollback (avant la vraie bascule)

Préfixe **`dist.drill-`** uniquement (jamais `dist.bak-`).  
Script de rollback **à côté** de la sauvegarde, **même horodatage**, **pas dans `/tmp`**.

```bash
# Remplir depuis le bloc paramètres
API=/opt/helvetic-api/app/artifacts/api-server
UNIT=helvetic-api

STAMP=$(date +%Y%m%d-%H%M%S)
echo "STAMP=$STAMP"
# Ex. STAMP=20260927-220105 → dist.drill-20260927-220105 + rollback-drill-20260927-220105.sh

cp -a "$API/dist" "$API/dist.new"
mv "$API/dist" "$API/dist.drill-$STAMP"
mv "$API/dist.new" "$API/dist"

# Rollback littéral (horodatage figé dans le nom de fichier ET dans le corps)
cat > "$API/rollback-drill-$STAMP.sh" <<EOF
#!/bin/bash
set -euo pipefail
API=$API
UNIT=$UNIT
mv "\$API/dist" "\$API/dist.abort-drill-$STAMP"
mv "\$API/dist.drill-$STAMP" "\$API/dist"
systemctl restart "\$UNIT"
EOF
chmod +x "$API/rollback-drill-$STAMP.sh"
# Vérifier : cat "$API/rollback-drill-$STAMP.sh"

bash "$API/rollback-drill-$STAMP.sh"
systemctl is-active "$UNIT"
sleep 60
systemctl is-active "$UNIT"
# attendu : active ×2

# Retirer le drill AVANT de poser le vrai contenu
rm -rf "$API/dist.drill-$STAMP" "$API/dist.abort-drill-$STAMP" "$API/rollback-drill-$STAMP.sh"
test ! -e "$API/dist.new"
```

Si le drill échoue → STOP (ne pas basculer).

### B. Bascule atomique

Pas de rsync dans `dist/`. Snapshot = premier `mv`. Script rollback **dans `$API/`**, même stamp que `dist.bak-`.

```bash
API=/opt/helvetic-api/app/artifacts/api-server
UNIT=helvetic-api
# PROFILE = valeur HOST_PROFILE du bloc paramètres (ex. ionos)

# 0) Vrai contenu déjà dans dist.new/
test -f "$API/dist.new/index.mjs" && test -s "$API/dist.new/index.mjs"
# Aucun dist.drill-* restant
test -z "$(ls -d "$API"/dist.drill-* 2>/dev/null || true)"

# 1) HOST_PROFILE dans l’env file AVANT rename (ancien binaire ignore la clé)
#    grep -q '^HOST_PROFILE=' … || echo 'HOST_PROFILE=<profil>' >> api.env
#    sinon remplacer la ligne existante — valeur = bloc paramètres

STAMP=$(date +%Y%m%d-%H%M%S)
echo "STAMP=$STAMP"

# 2) Rollback littéral À CÔTÉ de la future sauvegarde (avant les renames)
cat > "$API/rollback-$STAMP.sh" <<EOF
#!/bin/bash
set -euo pipefail
API=$API
UNIT=$UNIT
mv "\$API/dist" "\$API/dist.failed-$STAMP"
mv "\$API/dist.bak-$STAMP" "\$API/dist"
systemctl restart "\$UNIT"
EOF
chmod +x "$API/rollback-$STAMP.sh"
# Vérifier le littéral : cat "$API/rollback-$STAMP.sh"

# 3) Deux renames
mv "$API/dist" "$API/dist.bak-$STAMP"
mv "$API/dist.new" "$API/dist"

# 4) Restart + tenue
systemctl restart "$UNIT"
systemctl is-active "$UNIT"
sleep 60
systemctl is-active "$UNIT"
```

**Rollback sous pression** (même session ou une autre) :

```bash
bash /opt/helvetic-api/app/artifacts/api-server/rollback-<STAMP>.sh
```

Exemple si `STAMP=20260927-220310` :

```bash
bash /opt/helvetic-api/app/artifacts/api-server/rollback-20260927-220310.sh
```

Paired : `dist.bak-20260927-220310` ↔ `rollback-20260927-220310.sh`.

### C. Lead de preuve + nettoyage

Utiliser domaine / marqueur / email du **bloc paramètres** (jamais une boîte active du relevé).

Attendu : HTTP 201, `channels` contient `email` (et `crm` si le profil pousse).

Retrait : noter `lead_id` / `crm_lead_id` → supprimer fiche CRM → `rm -f $crm-sent/<lead_id>`.

### D. Anomalie

Première anomalie (drill, is-active, lead) → exécuter le `rollback-*.sh` (ou `rollback-drill-*.sh`) correspondant → **STOP**.

---

## Ordre jour J — IONOS (applique paramètres + procédure)

1. **A** Drill → is-active t+0 / t+60 → retirer `dist.drill-*` + `rollback-drill-*`.
2. Poser reconciled dans `dist.new/`.
3. `HOST_PROFILE=ionos` dans `/etc/helvetic/api.env`.
4. **B** Écrire `rollback-<STAMP>.sh` dans `$API/` → renames → restart → is-active t+0 / t+60.
5. **C** Sonde `helvetique-terrassement.ch` / `BASCULE-IONOS-PROBE-…` → nettoyage.
6. Sinon **D** rollback + STOP.

---

## Pour rejouer (Hetzner, IK-FR, LWS, IK-DE)

1. Dupliquer ce fichier ou ajouter un bloc paramètres (SSH, `HOST_PROFILE`, domaine sonde à zéro lead, exclus).
2. Exécuter **A → B → C** sans changer la procédure commune.
3. GO Frédéric + date ; fenêtre 22:00 Europe/Zurich sauf mesure contraire documentée.
