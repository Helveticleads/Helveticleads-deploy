#!/usr/bin/env bash
# Lancement MANUEL de la bascule IONOS (pas un job `at`).
#
# Sur ce Mac, atrun est Disabled par défaut (com.apple.atrun.plist) : aucune
# file `at` ne s'exécute. Ce script ne prétend plus le contraire.
#
# Usage (depuis une session attentive, hors heures critiques) :
#   ./scripts/bascule-ionos-at.sh
#
# Enchaîne bascule-ionos-run.sh avec SKIP_WAIT=1 (pas d'attente jusqu'à 22:00).
# Refuse de repartir si bascule-ionos-done.marker existe déjà.
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
ROOT="/Users/fred/Helveticleads/Helveticleads-deploy/ops/api-server-sauvetage"
LOG="$ROOT/bascule-ionos-run.log"
MARKER="$ROOT/bascule-ionos-done.marker"

if [ -f "$MARKER" ]; then
  echo "already done: $(cat "$MARKER")" | tee -a "$LOG"
  exit 0
fi

echo "MANUAL bascule start $(TZ=Europe/Zurich date -Iseconds)" | tee -a "$LOG"
export SKIP_WAIT=1
"$ROOT/scripts/bascule-ionos-run.sh" >>"$LOG" 2>&1
ec=$?
echo "finished rc=$ec at $(TZ=Europe/Zurich date -Iseconds)" >"$MARKER"
exit $ec
