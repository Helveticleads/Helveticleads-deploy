#!/usr/bin/env bash
# Rafraîchit taken_at tant que ce run tient le verrou.
# Lancé par ssh sans nohup : si le runner meurt, la session tombe,
# SIGHUP tue la boucle, taken_at s'arrête, STALE (60 min) reprend le verrou.
set -u
LOCK_DIR="${LOCK_DIR:-$HOME/.helveticleads-deploy-lock}"
LOCK_OWNER="${LOCK_OWNER:?LOCK_OWNER manquant}"
trap 'exit 0' HUP INT TERM
while [ -d "$LOCK_DIR" ] && [ "$(cat "$LOCK_DIR/owner" 2>/dev/null || true)" = "$LOCK_OWNER" ]; do
  date -u +"%Y-%m-%dT%H:%M:%SZ" > "$LOCK_DIR/taken_at" || exit 0
  sleep "${HEARTBEAT_SEC:-15}"
done
