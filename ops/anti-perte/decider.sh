#!/usr/bin/env bash
# Décision anti-perte avant comparaison servi↔bâti.
# Aucun SSH ici : le workflow (ou classer-etat) lui passe ce qu'il a lu.
#
# Entrées (env) :
#   PREV                — readlink current (vide si current absent)
#   PREV_AVEC_PAGES=0|1 — 1 si PREV est un répertoire qui contient au moins
#                         un index.html non vide (site déjà servi via ce lien)
#   COMPLETE_RELEASE    — chemin d'un index.html non vide sous releases/ (vide sinon)
#
# Échelle (3 branches) — la question est « a-t-on déjà servi des pages ? »,
# pas l'état du lien current :
#   1. aucune release avec page → laisser passer
#        · current absent     → GATE_SKIP anti_perte:premiere_release
#        · current présent    → GATE_SKIP anti_perte:hote_provisionne
#   2. au moins une release avec page, mais PREV n'en pointe aucune
#        → GATE_FAIL anti_perte:current_casse_sur_site_servi
#   3. PREV pointe une release avec pages → exit 2 (comparaison normale)
#
# Exit : 0 = skip (laisser passer), 1 = refuser, 2 = comparer.
# Sous set -e : capturer rc — voir APPEL-WORKFLOW.md.
#
# Ne jamais réintroduire « SSH_ou_current_absent » ni réutiliser une chaîne
# retirée pour un autre sens (témoin d'ancienneté).
set -euo pipefail

PREV="${PREV-}"
PREV_AVEC_PAGES="${PREV_AVEC_PAGES:-0}"
COMPLETE_RELEASE="${COMPLETE_RELEASE-}"

# 1 — jamais servi (aucune release avec page)
if [ -z "$COMPLETE_RELEASE" ]; then
  if [ -z "$PREV" ]; then
    echo "GATE_SKIP anti_perte:premiere_release"
  else
    echo "GATE_SKIP anti_perte:hote_provisionne PREV=${PREV}"
  fi
  exit 0
fi

# 3 — PREV sert déjà des pages
if [ "$PREV_AVEC_PAGES" = "1" ]; then
  echo "ANTI_PERTE_ETAT=prev_valide"
  exit 2
fi

# 2 — des pages existent en releases/, mais current ne les sert pas
if [ -z "$PREV" ]; then
  echo "GATE_FAIL anti_perte:current_casse_sur_site_servi (release complete sans current: $COMPLETE_RELEASE)"
else
  echo "GATE_FAIL anti_perte:current_casse_sur_site_servi PREV=$PREV (pas de page servie; release complete: $COMPLETE_RELEASE)"
fi
exit 1
