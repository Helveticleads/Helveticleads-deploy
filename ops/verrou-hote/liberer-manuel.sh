#!/usr/bin/env bash
# Libération MANUELLE du verrou par hôte.
# À utiliser quand plus rien ne se déploie sur un hôte et qu'un verrou orphelin
# bloque encore (reprise auto échouée ou STALE pas encore atteint).
#
# Usage :
#   ssh deploy@<HOST> 'bash -s' < ops/verrou-hote/liberer-manuel.sh
#   # ou, une fois connecté sur l'hôte :
#   LOCK_DIR=$HOME/.helveticleads-deploy-lock bash liberer-manuel.sh
#
# Commande one-liner (compte rendu) :
#   ssh deploy@HOST 'rm -rf $HOME/.helveticleads-deploy-lock && echo LOCK_FORCE_CLEARED'
set -euo pipefail

LOCK_DIR="${LOCK_DIR:-$HOME/.helveticleads-deploy-lock}"

if [ ! -d "$LOCK_DIR" ]; then
  echo "LOCK_FORCE_SKIP absent ($LOCK_DIR)"
  exit 0
fi

echo "LOCK_FORCE_CLEAR was_owner=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo '?') taken_at=$(cat "$LOCK_DIR/taken_at" 2>/dev/null || echo '?')"
rm -rf "$LOCK_DIR"
echo "LOCK_FORCE_CLEARED dir=$LOCK_DIR"
