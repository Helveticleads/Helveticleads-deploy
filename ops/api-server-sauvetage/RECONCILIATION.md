# Réconciliation api-server — compte rendu

**Branche :** `sauvetage/api-server-from-binaries`  
**Date :** 2026-09-27  
**Interdit toujours :** build / déploiement / écriture serveur / toucher aux `.map` hôtes.

## Livrables

| Chemin | Rôle |
|---|---|
| `from-hosts/{5}/` | Extractions (inchangées métier ; imports relatifs + `types.ts` pour tests) |
| `reconciled/` | Arbre source unique, profilé par hôte |
| `characterization/` | Tests de caractérisation (photographient le comportement actuel) |
| `package.json` | `npm test` = extract puis reconciled |

## Étape 1 — Caractérisation

Suites (normalize / delivery / route) × 5 hôtes.

```
CHAR_TARGET=extract   → 112 passed
CHAR_TARGET=reconciled → 112 passed
```

Couverture minimale tenue : alias normalize, honeypot + formes de réponse + messages, canaux et ordre de livraison (y compris no-op webhook IK-DE vide).

## Étape 2 — Arbre réconcilié

- **Pipeline / normalize :** strate infomaniak-de (richesses + adaptateur schaedlinge), **paramétrée** par `HostProfile` pour reproduire les chaînes d’alias de chaque hôte.
- **Livraison :** `deliver-lead` IONOS (CRM track + legacy webhook + mail), gated par le profil (`supportsCrmPush` seulement sur ionos).
- **Route IK-DE :** toujours mail + webhook fire-and-forget (pas `deliverLead`), forme `{ success }` — photographie prod.
- **Universel (choix explicite) :** `cors` + `securityHeaders` dans `reconciled/src/app.ts` pour tous les hôtes (manquaient sur 4/5 en prod).
- **Hors périmètre :** `recipients.ts` reste convention `contact@`/`kontakt@` + domaine — non configurable.

Profils : `reconciled/src/config/profiles.ts`. Runtime tests : `setActiveHostProfile(host)`.

## Étape 3 — Preuve

Cinq configurations × même jeu de tests : **verts**.

## Écarts nommés (choix, pas accidents)

1. **Durcissement HTTP universel** — les quatre hôtes sans cors/securityHeaders en gagnent. Ce n’est pas de la config : c’est un manque de prod corrigé dans le tronc. Comportement antérieur « cors ouvert / pas de headers » **volontairement abandonné**.
2. **CRM track URL en webhook générique** — en extract, Hetzner/LWS/IK-FR POST’ent n’importe quel `CRM_WEBHOOK_URL` (y compris une URL track) comme webhook legacy. En reconciled, une URL track n’active le push CRM que si le profil `supportsCrmPush` (ionos) ; sinon elle est ignorée (pas de faux canal). Documenté dans le test delivery.
3. **`crm_lead_id` omis si undefined** — JSON n’émet pas la clé ; photographié tel quel (pas une régression).
4. **`types.ts` reconstruit** — absent des `.map` ; types déduits de l’usage pour compiler les tests. Pas de comportement runtime.
5. **Logger de test** — `pino` silencieux sans `pino-pretty` (évite une dépendance optionnelle) ; hors chemin métier leads.

## Rotation / secrets

Aucune des quatre valeurs littérales du sauvetage n’a été réintroduite. Toujours via env : `FROM_EMAIL`, `LEAD_EMAIL_FOOTER_*`, `CRM_TRACK_URL` / `CRM_WEBHOOK_URL`.

## Suite (pas maintenant)

Bascule IONOS : prérequis construits (`index.ts` + `npm run build` + workflow CI).  
Runbook corrigé : [BASCULE-IONOS.md](./BASCULE-IONOS.md). **STOP avant push / déploiement.**
