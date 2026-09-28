#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"
ROOT="/Users/fred/Helveticleads/Helveticleads-deploy/ops/api-server-sauvetage"
LOG="$ROOT/bascule-ionos-run.log"
MARKER="$ROOT/bascule-ionos-done.marker"
if [ -f "$MARKER" ]; then
  echo "already done: $(cat "$MARKER")" >>"$LOG"
  exit 0
fi
# Skip the internal wait — at/cron fires at 22:00
export SKIP_WAIT=1
"$ROOT/scripts/bascule-ionos-run.sh" >>"$LOG" 2>&1
ec=$?
echo "finished rc=$ec at $(TZ=Europe/Zurich date -Iseconds)" >"$MARKER"
exit $ec
