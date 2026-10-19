#!/usr/bin/env bash
# Restaure PREV si valide ; sinon retire current (ROLLBACK_VERS_NEANT).
# Usage : BASE=/var/www/x PREV=/var/www/x/releases/TS bash rollback.sh
# PREV peut être vide.
set -euo pipefail

BASE="${BASE:?BASE manquant}"
PREV="${PREV-}"

if [ -n "$PREV" ] && [ "$PREV" != "$BASE/current" ] && [ -d "$PREV" ]; then
  ln -sfn "$PREV" "$BASE/.current.tmp"
  mv -Tf "$BASE/.current.tmp" "$BASE/current"
  echo "ROLLBACK→$PREV"
  exit 0
fi

if [ -e "$BASE/current" ] || [ -L "$BASE/current" ]; then
  rm -f "$BASE/current"
  echo "ROLLBACK_VERS_NEANT: current retiré, site revenu à son état d'avant déploiement"
  exit 0
fi

echo "ROLLBACK_SKIP: rien à retirer (current absent, PREV=${PREV:-∅})"
exit 0
