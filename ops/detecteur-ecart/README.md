# Détecteur d'écart — convention de publication

Mesure : Last-Modified du HTML servi vs date du dernier commit `main`, plus empreinte sha256. Pas de marqueur circulaire écrit par le déploiement.

## Marqueur `.helveticleads/publication`

| | |
|---|---|
| **Où** | À la racine du dépôt du site : `.helveticleads/publication` |
| **Valeurs** | Une seule ligne, sans espace : `brouillon` ou `en_ligne` |
| **Absence** | = `en_ligne` = **surveillé**. Un dépôt neuf sans fichier fait du bruit jusqu'au premier commit du marqueur. L'omission ne sort jamais un site du filet. |
| **Qui bascule** | L'opérateur Helveticleads (passation / go-live). |
| **Quand → `en_ligne`** | Au **go-live prouvé**, au moment de la passation du dépôt à **MODIFS RÉSEAUX**. Pas avant. |
| **Quand → `brouillon`** | Tant que le site n'est pas publié / pas encore confié au filet de production. |

### Jamais servi

Le marqueur est **interne au dépôt**. Il ne doit apparaître ni sous `public/`, ni dans `dist/`, ni dans l'artefact rsync (`dist/public` → `releases/` → `current/`). Le workflow Infomaniak ne copie que `dist/public` ; `.helveticleads/` à la racine n'y entre pas. Ne pas le copier dans le build.

### Effets sur le classement

| Marqueur | Effet |
|---|---|
| absent / `en_ligne` | Dans la population surveillée (mesure écart / empreinte / atteinte). |
| `brouillon` (< 60 j) | **Hors population.** Ni `EN_RETARD` ni bloquant. Listé sous « pas encore publiés » avec l’**âge** (depuis le commit qui a posé / mis à jour le fichier). |
| `brouillon` (≥ 60 j) | **`BROUILLON_DORMANT`**, bloquant — le marqueur ne peut pas devenir un silence définitif. |

## Seaux (scission de l’ancien `NON_MESURE`)

| État | Sévérité | Bloquant ? |
|---|---|---|
| `EN_RETARD` | Retard daté > 2 h | Oui |
| `INJOIGNABLE` | Site `en_ligne` injoignable **deux passages consécutifs** | Oui (au-dessus de `EN_RETARD`) |
| Avertissement injoignable | Premier échec d’atteinte seul | Non (hoquet DNS se rattrape au passage suivant) |
| `BROUILLON_DORMANT` | Brouillon ≥ 60 j | Oui |
| `BROUILLON` | Brouillon < 60 j | Non (hors population) |
| `NON_MESURE` | Dépôt illisible, date illisible, domaine inconnu | Signalé (voir clôture) |
| `SUIVI_PAR_EMPREINTE` | Pas de Last-Modified | Ne compare pas à `main` |

Persistance `INJOIGNABLE` : bloc `DETECTEUR_INJOIGNABLE_V1` dans le corps de l’issue #2 (comme les empreintes). Un succès d’atteinte efface le compteur du domaine.

## Clôture (`peut_fermer`)

Oui seulement si **aucun** `EN_RETARD`, **aucun** `INJOIGNABLE`, **aucun** `BROUILLON_DORMANT`, **pas** d’échec d’authentification, et couverture complète (N = population = flotte − brouillons).

## Diagnostic `[skip ci]`

Si un site est `EN_RETARD` et que les messages de commit depuis la page servie portent `[skip ci]` / `[ci skip]`, la raison du rapport le nomme (cause probable : Actions n’a pas déployé).

## Fichiers

- `detecteur.sh` — passage schedule / dry-run
- `preuves.sh` — harness local (ne ferme jamais l’issue)
- `sites-auto.txt` / `sites-declares.txt` / `exclusions.txt` — inventaire
