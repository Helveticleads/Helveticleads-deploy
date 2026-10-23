# Commun — sourcé par notifier / cloturer / kpi (pas exécuté seul).
# shellcheck shell=bash
set -euo pipefail

ISSUE_TITLE="Deploy — verdicts"
LABEL_BASE="deploy-verdict"
LABEL_GARDE="deploy-garde"
LABEL_INFRA="deploy-infra"
LABEL_SABOTAGE="deploy-sabotage"

ensure_labels() {
  local repo="$1"
  gh label create "$LABEL_BASE" -R "$repo" --color "B60205" --description "Fil persistant des verdicts Deploy" 2>/dev/null || true
  gh label create "$LABEL_GARDE" -R "$repo" --color "D93F0B" --description "GATE_FAIL (garde)" 2>/dev/null || true
  gh label create "$LABEL_INFRA" -R "$repo" --color "FBCA04" --description "Echec infra Deploy" 2>/dev/null || true
  gh label create "$LABEL_SABOTAGE" -R "$repo" --color "5319E7" --description "preuve_sabotage — exclu KPI" 2>/dev/null || true
}

find_open_verdict_issue() {
  local repo="$1"
  gh issue list -R "$repo" --state open --label "$LABEL_BASE" --json number,title \
    --jq ".[] | select(.title == \"$ISSUE_TITLE\") | .number" | head -1
}

non_notifie() {
  local raison="$1"
  local line="VERDICT NON NOTIFIÉ : $raison"
  printf '%s\n' "$line" >&2
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '%s\n' "$line" >> "$GITHUB_STEP_SUMMARY"
  fi
}
