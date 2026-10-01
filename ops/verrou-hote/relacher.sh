#!/usr/bin/env bash
# Relâche du verrou par hôte — uniquement si nous en sommes le propriétaire.
# S'exécute SUR la machine cible (ou en local avec LOCK_DIR).
#
# Variables :
#   LOCK_DIR    (défaut $HOME/.helveticleads-deploy-lock)
#   LOCK_OWNER  identité qui avait pris le verrou
#   VERROU_DISABLED=1  no-op
set -euo pipefail

LOCK_DIR="${LOCK_DIR:-$HOME/.helveticleads-deploy-lock}"
LOCK_OWNER="${LOCK_OWNER:?LOCK_OWNER manquant}"

log() { printf '%s\n' "$*" >&2; }

if [ "${VERROU_DISABLED:-0}" = "1" ]; then
  log "VERROU_DISABLED=1 — relâche ignorée"
  exit 0
fi

if [ ! -d "$LOCK_DIR" ]; then
  log "LOCK_RELEASE_SKIP absent dir=$LOCK_DIR"
  exit 0
fi

current=$(cat "$LOCK_DIR/owner" 2>/dev/null || echo "")
if [ "$current" != "$LOCK_OWNER" ]; then
  log "LOCK_SKIP_RELEASE foreign_owner=${current:-?} self=$LOCK_OWNER — on ne touche pas"
  exit 0
fi

rm -rf "$LOCK_DIR"
log "LOCK_RELEASED owner=$LOCK_OWNER dir=$LOCK_DIR"
