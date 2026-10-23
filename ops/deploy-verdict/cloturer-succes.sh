#!/usr/bin/env bash
# Sur Deploy réussi : publie un verdict succès dans l'issue Deploy — verdicts.
# Env : GH_TOKEN, REPO, RUN_URL
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

REPO="${REPO:-${GITHUB_REPOSITORY:?REPO manquant}}"
RUN_URL="${RUN_URL:-}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

body=$(cat <<EOF
## Verdict succes
- quand : ${NOW_UTC}
- verdict : GATE_OK deploy_complete
- run : ${RUN_URL:-∅}
- denominateurs KPI : echecs Deploy × verdicts notifies (ce commentaire compte pour le second)
EOF
)

ensure_labels "$REPO" || true

num="$(find_open_verdict_issue "$REPO" || true)"
if [ -z "$num" ]; then
  create_body="Fil persistant des verdicts Deploy.

---
${body}"
  if out=$(gh issue create -R "$REPO" --title "$ISSUE_TITLE" --body "$create_body" -l "$LABEL_BASE" 2>/tmp/dv-create.err); then
    num=$(printf '%s' "$out" | grep -oE '/issues/[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
  else
    non_notifie "gh issue create succes a echoue ($(tr '\n' ' ' </tmp/dv-create.err 2>/dev/null | head -c 200))"
    exit 0
  fi
else
  if ! gh issue comment "$num" -R "$REPO" --body "$body" 2>/tmp/dv-close-c.err; then
    non_notifie "succes : comment #$num a echoue ($(tr '\n' ' ' </tmp/dv-close-c.err 2>/dev/null | head -c 200))"
    exit 0
  fi
fi

if [ -n "${num:-}" ]; then
  if ! gh issue close "$num" -R "$REPO" --comment "Fermeture automatique — Deploy succes." 2>/tmp/dv-close.err; then
    non_notifie "succes : close #$num a echoue ($(tr '\n' ' ' </tmp/dv-close.err 2>/dev/null | head -c 200))"
    exit 0
  fi
  echo "VERDICT_CLOSED=$num"
fi
