# Bascule IONOS — runbook (exécutable le jour J, pas maintenant)

Hôte : `deploy@212.227.76.165`  
Unité : `helvetic-api`  
Dist servi : `/opt/helvetic-api/app/artifacts/api-server/dist/`  
Env : `/etc/helvetic/api.env`  
Profil : `HOST_PROFILE=ionos`  
Fenêtre mesurée : **04:00 Europe/Zurich** (0 lead / 7 j. sur les 6 domaines IONOS ; autres heures à 0 : 06–07, 09–12, 22–23).

**Interdit ici :** push, déploiement, jetons CRM, nginx `debarrass-tout.be`.

---

## Prérequis (déjà construits en local)

- `reconciled/src/index.ts` — lit `HOST_PROFILE`, appelle `setActiveHostProfile`, exige `PORT`
- `npm run build` → `ops/api-server-sauvetage/dist/index.mjs` (+ `.map`)
- `npm run ci` = caractérisation extract+reconciled + build + smoke boot

---

## HOST_PROFILE et l’ancien binaire

L’extract IONOS (`from-hosts/ionos/src/index.ts`) n’exige que `PORT`. Aucune validation d’environnement stricte : une variable inconnue est **ignorée**.

→ L’ancien `dist/index.mjs` **démarre** avec `HOST_PROFILE=ionos` présent dans `api.env`.  
→ Le rollback de `dist/` seul suffit ; retirer `HOST_PROFILE` est cosmétique, pas bloquant.

---

## Bascule atomique (pas de rsync dans `dist/`)

```bash
API=/opt/helvetic-api/app/artifacts/api-server
TS=$(date +%Y%m%d-%H%M%S)
# 1) Poser le NOUVEAU contenu à côté, vérifier
mkdir -p "$API/dist.new"
# …copier index.mjs + index.mjs.map dans dist.new…
test -f "$API/dist.new/index.mjs"
test -s "$API/dist.new/index.mjs"
# 2) Deux renames — le service ne voit jamais d’état mélangé
mv "$API/dist" "$API/dist.bak-$TS"
mv "$API/dist.new" "$API/dist"
```

Le snapshot **est** le premier `mv`. Pas de copie séparée obligatoire.

---

## Drill rollback (AVANT la vraie bascule, le jour J)

Avec un `dist.new` **identique** à l’actuel (copie de preuve, pas le reconciled) :

```bash
API=/opt/helvetic-api/app/artifacts/api-server
TS=$(date +%Y%m%d-%H%M%S)
cp -a "$API/dist" "$API/dist.new"
mv "$API/dist" "$API/dist.bak-$TS"
mv "$API/dist.new" "$API/dist"
# rollback immédiat
mv "$API/dist" "$API/dist.abort-$TS"
mv "$API/dist.bak-$TS" "$API/dist"
systemctl restart helvetic-api
systemctl is-active helvetic-api
sleep 60
systemctl is-active helvetic-api
# attendu : active les deux fois ; pas de restart loop (RestartSec=3)
```

Seulement si le drill est vert → bascule réelle.

---

## Ordre jour J (fenêtre 04:00 Europe/Zurich)

1. Drill rollback (ci-dessus).
2. Construire / transporter le vrai `dist.new` (reconciled, `HOST_PROFILE=ionos` au boot).
3. Ajouter `HOST_PROFILE=ionos` dans `/etc/helvetic/api.env` **avant** le restart (l’ancien binaire tourne encore, ignore la clé).
4. Renames atomiques `dist` → `dist.bak-$TS`, `dist.new` → `dist`.
5. `systemctl restart helvetic-api`
6. `systemctl is-active` immédiat, puis encore après **60 s**.
7. Lead de preuve (ci-dessous).
8. Si échec → rollback une commande.

### Rollback une commande

```bash
API=/opt/helvetic-api/app/artifacts/api-server; TS=<horodatage>
mv "$API/dist" "$API/dist.failed-$TS" && mv "$API/dist.bak-$TS" "$API/dist" && systemctl restart helvetic-api
```

(`HOST_PROFILE` peut rester ; l’ancien binaire l’ignore.)

---

## Lead de preuve (vrai lead, identifiable)

Marqueur unique, jamais anonyme :

- `name`: `BASCULE-IONOS-PROBE-<TS>`
- `email`: `bascule-ionos-probe+<TS>@premiumhelveticleads.ch` (ou boîte contrôlée)
- `phone`: numéro de test interne documenté
- `message`: `PROBE bascule api-server IONOS <TS> — à supprimer`
- Host / site : `helvetique-terrassement.ch` (jeton présent)

Attendu : HTTP 201, `channels` contient `email` (et `crm` si push OK), log `Lead delivered`.

### Retrait après preuve

1. Noter `lead_id` (API) et `crm_lead_id` (log / réponse si présent).
2. CRM : supprimer la fiche lead `crm_lead_id` (UI opérateur ou endpoint admin — **pas** via régénération de jeton).
3. Sur l’hôte : retirer le marqueur idempotence  
   `rm -f /var/lib/helvetic-api/crm-sent/<lead_id>`  
   (fichier nommé par UUID lead ; lecture seule hors bascule).
4. E-mail Resend : déjà parti — conserver dans la boîte destinataire sous libellé PROBE ; ne pas laisser la fiche CRM.

---

## Hors périmètre rappel

`debarrass-tout.be` : aucun jeton, aucune fiche, aucun nginx. Token absent → warn + e-mail continue (identique extract / reconciled).
