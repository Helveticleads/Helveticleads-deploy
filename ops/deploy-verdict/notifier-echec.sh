#!/usr/bin/env bash
# Ouvre ou commente l'issue persistante Deploy — verdicts (dépôt appelant).
# Env :
#   GH_TOKEN          (obligatoire)
#   REPO              owner/name (défaut : github.repository)
#   RUN_URL           URL du run
#   VERDICT_FILE      chemin du témoin GATE_FAIL (optionnel)
#   FAILED_STEP       nom du step en échec (optionnel, classe infra)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

REPO="${REPO:-${GITHUB_REPOSITORY:?REPO manquant}}"
RUN_URL="${RUN_URL:-}"
VERDICT_FILE="${VERDICT_FILE:-${RUNNER_TEMP:-/tmp}/deploy-verdict.txt}"
FAILED_STEP="${FAILED_STEP:-}"
NOW_UTC="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

classe="infra"
verdict="infra:step_failed${FAILED_STEP:+ ($FAILED_STEP)}"
extra_labels=("$LABEL_INFRA")

if [ -f "$VERDICT_FILE" ] && grep -q '^GATE_FAIL' "$VERDICT_FILE" 2>/dev/null; then
  classe="garde"
  verdict="$(grep '^GATE_FAIL' "$VERDICT_FILE" | tail -1)"
  extra_labels=("$LABEL_GARDE")
  if printf '%s' "$verdict" | grep -q 'preuve_sabotage:'; then
    extra_labels+=("$LABEL_SABOTAGE")
  fi
fi

body=$(cat <<EOF
## Verdict ${classe}

- quand : ${NOW_UTC}
- verdict : ${verdict}
- run : ${RUN_URL:-∅}
- denominateurs KPI : echecs Deploy × verdicts notifies (ce commentaire compte pour le second)
EOF
)

if ! ensure_labels "$REPO"; then
  non_notifie "impossible de poser les labels sur $REPO"
  exit 0
fi

num="$(find_open_verdict_issue "$REPO" || true)"
if [ -z "$num" ]; then
  label_args=(-l "$LABEL_BASE")
  for l in "${extra_labels[@]}"; do label_args+=(-l "$l"); done
  create_body="Fil persistant des verdicts Deploy. Chaque échec ajoute un commentaire ; un succès ferme l'issue.

---
${body}"
  if out=$(gh issue create -R "$REPO" --title "$ISSUE_TITLE" --body "$create_body" "${label_args[@]}" 2>/tmp/dv-create.err); then
    num=$(printf '%s' "$out" | grep -oE '/issues/[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
  else
    num=""
  fi
  if [ -z "${num:-}" ]; then
    non_notifie "gh issue create a échoué ($(tr '\n' ' ' </tmp/dv-create.err 2>/dev/null | head -c 200))"
    exit 0
  fi
  echo "VERDICT_ISSUE_CREATED=$num classe=$classe"
else
  # s'assurer des labels de classe sur l'issue existante
  for l in "${extra_labels[@]}"; do
    gh issue edit "$num" -R "$REPO" --add-label "$l" 2>/dev/null || true
  done
  if ! gh issue comment "$num" -R "$REPO" --body "$body" 2>/tmp/dv-comment.err; then
    non_notifie "gh issue comment #$num a échoué ($(tr '\n' ' ' </tmp/dv-comment.err 2>/dev/null | head -c 200))"
    exit 0
  fi
  echo "VERDICT_ISSUE_COMMENTED=$num classe=$classe"
fi
