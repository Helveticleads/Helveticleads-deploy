#!/usr/bin/env bash
# Sur Deploy réussi : commente et ferme l'issue Deploy — verdicts si ouverte.
# Env : GH_TOKEN, REPO, RUN_URL
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

REPO="${REPO:-${GITHUB_REPOSITORY:?REPO manquant}}"
RUN_URL="${RUN_URL:-}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

num="$(find_open_verdict_issue "$REPO" || true)"
if [ -z "$num" ]; then
  echo "VERDICT_CLOSE_SKIP aucune issue ouverte"
  exit 0
fi

body=$(cat <<EOF
## Résolu

- quand : ${NOW_UTC}
- événement : Deploy en succès
- run : ${RUN_URL:-∅}
EOF
)

if ! gh issue comment "$num" -R "$REPO" --body "$body" 2>/tmp/dv-close-c.err; then
  non_notifie "clôture : comment #$num a échoué ($(tr '\n' ' ' </tmp/dv-close-c.err 2>/dev/null | head -c 200))"
  exit 0
fi
if ! gh issue close "$num" -R "$REPO" --comment "Fermeture automatique — Deploy succès." 2>/tmp/dv-close.err; then
  non_notifie "clôture : close #$num a échoué ($(tr '\n' ' ' </tmp/dv-close.err 2>/dev/null | head -c 200))"
  exit 0
fi
echo "VERDICT_CLOSED=$num"
