# Sauvetage api-server — sources extraites des binaires de production

**Date :** 2026-09-27  
**Interdit jusqu’à nouvel ordre :** build / rebuild / déploiement d’api-server sur tout hôte.  
**Emplacement :** `ops/api-server-sauvetage/from-hosts/` — **distinct** de tout `artifacts/api-server/src` (stub).  
**Branche :** `sauvetage/api-server-from-binaries` — non poussée sans retour explicite.

## Étape 1 — Extraction (lecture seule)

Depuis chaque hôte : `scp` de `/opt/helvetic-api/app/artifacts/api-server/dist/index.mjs.map` uniquement.  
Sources projet extraites de `sourcesContent` (hors `node_modules`) vers un sous-dossier par hôte.

| Hôte | IP | mtime `index.mjs` | SHA-256 du `.map` (fichier `meta/<hôte>.map.sha256`) |
|---|---|---|---|
| hetzner | 178.105.216.42 | 2026-06-07 18:32 +0200 | voir meta |
| lws | 180.149.199.219 | 2026-06-07 04:58 +0200 | voir meta |
| infomaniak-fr | 179.237.70.246 | 2026-06-04 23:16 UTC | voir meta |
| infomaniak-de | 179.237.70.207 | 2026-06-04 23:13 UTC | voir meta |
| ionos | 212.227.76.165 | 2026-07-28 05:04 +0200 | voir meta |

Travail hors dépôt pendant l’extraction : `/tmp/api-server-sauvetage-20260927/`.

## Étape 2 — Comparaison des cinq (contenu source, pas empreinte bundle)

**5 arbres source réellement distincts** (empreinte concaténée fichier+contenu : 5/5).

### Fichiers identiques sur les cinq

- `api-zod/src/generated/api.ts`
- `lead-core/src/email.ts` (avant sanitization ; contenu métier identique)
- `lead-core/src/recipients.ts`
- `src/index.ts`
- `src/lib/logger.ts`
- `src/routes/health.ts`
- `src/routes/index.ts`

### Écarts fichier par fichier

| Fichier | Variantes | Qui porte quoi |
|---|---|---|
| `lead-core/src/normalize.ts` | **5** | Chaque hôte une version (alias champs / consent / langue) |
| `lead-core/src/template.ts` | **4** | hetzner ‖ lws ‖ infomaniak-fr=**ionos** ‖ infomaniak-de |
| `lead-core/src/subject.ts` | **2** | hetzner=lws=infomaniak-fr=ionos ‖ **infomaniak-de** |
| `src/app.ts` | **2** | 4 hôtes (cors ouvert) ‖ **infomaniak-de** (cors + securityHeaders) |
| `src/routes/leads.ts` | **4** | hetzner=lws ‖ infomaniak-fr ‖ **infomaniak-de** (archi différente) ‖ **ionos** (+`crm_lead_id`) |
| `src/services/deliver-lead.ts` | **2 + absence** | hetzner=lws=infomaniak-fr ‖ **ionos** (CRM track enrichi) ‖ **absent** sur infomaniak-de |
| `src/lib/cors.ts` | 1 | **infomaniak-de seulement** |
| `src/lib/securityHeaders.ts` | 1 | **infomaniak-de seulement** |
| `src/lib/webhook.ts` | 1 | **infomaniak-de seulement** (à la place de deliver-lead) |

### IONOS (plus récent, 28 juil.) — code nouveau ou rebuild tardif ?

**Les deux, mais surtout du code que les quatre autres n’ont pas.**

- Pas un simple rebuild du même source : `deliver-lead.ts` passe ~2,6 Ko → ~13 Ko avec canal CRM (`/api/leads/track`, tokens, idempotence, `crm_lead_id`).
- `leads.ts` expose `crm_lead_id` dans la réponse.
- `normalize` / `template` : pas alignés sur Hetzner/LWS ; `template` partagé avec infomaniak-fr seulement.

**infomaniak-de** est l’autre variante structurelle majeure (pas IONOS) : pas de `deliver-lead.ts`, livraison inline email+webhook, modules cors/securityHeaders/webhook.

## Étape 3 — Scan secrets (avant commit)

**Aucun secret critique** (pas de clé API littérale, pas de Bearer, pas de mot de passe, pas de bloc private key, pas de `re_…` Resend en dur).

Secrets / données opérationnelles **retirés avant versionnement** (valeurs jamais reportées ici) :

| Fichier (tous hôtes sauf note) | Nature | Action | Rotation |
|---|---|---|---|
| `lead-core/src/email.ts` | expéditeur e-mail en fallback littéral (`FROM_EMAIL ?? "…"`) | fallback littéral supprimé → `process.env.FROM_EMAIL` seul | **oui** — faire tourner l’ancienne adresse d’expédition si elle fuitait via le `.map` public sur les hôtes |
| `lead-core/src/template.ts` | e-mail de contact footer (destinataire / contact société) | → `LEAD_EMAIL_FOOTER_CONTACT` | **oui** |
| `lead-core/src/template.ts` | téléphone de contact footer | → `LEAD_EMAIL_FOOTER_PHONE` | **oui** |
| `ionos/.../deliver-lead.ts` | URL de service CRM en dur (défaut track) | littéral retiré → exiger `CRM_TRACK_URL` / `CRM_WEBHOOK_URL` | non (URL de service, pas credential) |

Non retirés (déjà via env ou endpoints publics) : URL logo (surcharge `LEAD_EMAIL_LOGO_URL`), URL API Resend, origines CORS listées (infomaniak-de), domaines défaut `SITE_DOMAIN`.

Les `.map` de production sur les cinq hôtes **contiennent encore** les littéraux d’origine dans `sourcesContent`. Entrée rotation : traiter expéditeur + contact footer (+ téléphone) comme exposés tant que ces `.map` restent lisibles par `deploy`.

## Étape 4 — Versionnement

- Branche : `sauvetage/api-server-from-binaries` depuis `origin/main`
- Chemin : `ops/api-server-sauvetage/from-hosts/{hetzner,lws,infomaniak-fr,infomaniak-de,ionos}/`
- **Ne remplace pas** un stub `artifacts/api-server/src` (ce dépôt n’en a pas ; les stubs vivent dans les dépôts sites)
- **Pas de push** sans retour

Décision d’architecture (source partagé vs copie ×9 DE) : **non prise**, volontairement.
