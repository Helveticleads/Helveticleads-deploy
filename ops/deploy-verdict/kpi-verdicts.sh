#!/usr/bin/env bash
# KPI hebdo : croise runs Deploy en echec x verdicts notifies.
# Env :
#   GH_TOKEN
#   WINDOW_DAYS   (defaut 7)
#   REPOS_FILE    liste owner/name (une par ligne)
#   REPORT_REPO   (defaut Helveticleads/Helveticleads-deploy)
#   REPORT_TITLE  (defaut Deploy — KPI verdicts)
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
source "$DIR/common.sh"

WINDOW_DAYS="${WINDOW_DAYS:-7}"
REPORT_REPO="${REPORT_REPO:-Helveticleads/Helveticleads-deploy}"
REPORT_TITLE="${REPORT_TITLE:-Deploy — KPI verdicts}"
SINCE="$(date -u -d "-${WINDOW_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
  || date -u -v-"${WINDOW_DAYS}"d +%Y-%m-%dT%H:%M:%SZ)"
NOW="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

n_deploy_fail=0
n_verdicts_notifies=0
n_non_notifie_log=0
n_sans_suite_7j=0
n_sabotage_excl=0

repos=()
if [ -n "${REPOS_FILE:-}" ] && [ -f "$REPOS_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [ -z "$line" ] && continue
    [[ "$line" =~ ^# ]] && continue
    repos+=("$line")
  done < "$REPOS_FILE"
else
  echo "KPI_WARN REPOS_FILE absent — aucun depot a sonder" >&2
fi

iso_le() {
  # true if $1 <= $2 (ISO timestamps, lexicographic)
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort | head -1)" = "$1" ]
}

for repo in "${repos[@]}"; do
  fails=$(gh api "repos/$repo/actions/runs?per_page=50" --jq \
    "[.workflow_runs[] | select((.name|startswith(\"Deploy\")) and .conclusion==\"failure\" and .created_at >= \"$SINCE\")] | length" 2>/dev/null || echo 0)
  n_deploy_fail=$((n_deploy_fail + fails))

  issue_nums=$(gh issue list -R "$repo" --state all --label "$LABEL_BASE" --limit 20 \
    --json number,labels --jq '.[].number' 2>/dev/null || true)
  for num in $issue_nums; do
    labels=$(gh issue view "$num" -R "$repo" --json labels -q '[.labels[].name] | join(",")' 2>/dev/null || true)
    if printf '%s' "$labels" | grep -q "$LABEL_SABOTAGE"; then
      n_sabotage_excl=$((n_sabotage_excl + 1))
      continue
    fi
    n_c=$(gh api "repos/$repo/issues/$num/comments?per_page=100" --jq \
      "[.[] | select(.created_at >= \"$SINCE\" and (.body|startswith(\"## Verdict\")))] | length" 2>/dev/null || echo 0)
    n_verdicts_notifies=$((n_verdicts_notifies + n_c))

    created=$(gh issue view "$num" -R "$repo" --json createdAt,state -q '.createdAt + " " + .state' 2>/dev/null || true)
    created_at=${created%% *}
    state=${created##* }
    if [ "$state" = "OPEN" ] && [ -n "$created_at" ]; then
      recent=$(gh api "repos/$repo/issues/$num/comments?per_page=100" --jq \
        "[.[] | select(.created_at >= \"$SINCE\" and ((.body|startswith(\"## Verdict\")) or (.body|startswith(\"## Résolu\"))))] | length" 2>/dev/null || echo 0)
      if [ "${recent:-0}" -eq 0 ] && iso_le "$created_at" "$SINCE"; then
        # created_at <= SINCE means older than window start
        if [ "$created_at" != "$SINCE" ] && iso_le "$created_at" "$SINCE"; then
          n_sans_suite_7j=$((n_sans_suite_7j + 1))
        fi
      fi
    fi
  done

  run_ids=$(gh api "repos/$repo/actions/runs?per_page=20&status=completed" --jq \
    "[.workflow_runs[] | select((.name|startswith(\"Deploy\")) and .conclusion==\"failure\" and .created_at >= \"$SINCE\") | .id] | .[:10][]" 2>/dev/null || true)
  for rid in $run_ids; do
    if gh run view "$rid" -R "$repo" --log-failed 2>/dev/null | grep -q 'VERDICT NON NOTIFIÉ'; then
      n_non_notifie_log=$((n_non_notifie_log + 1))
    fi
  done
done

ecart=$((n_deploy_fail - n_verdicts_notifies))
if [ "$ecart" -lt 0 ]; then ecart=0; fi
# Reste sans explication = ecart - NON NOTIFIE. Toujours affiche, meme a 0.
n_reste_sans_explication=$((ecart - n_non_notifie_log))
if [ "$n_reste_sans_explication" -lt 0 ]; then n_reste_sans_explication=0; fi

{
  echo "# $REPORT_TITLE"
  echo
  echo "Mesure au $NOW — fenetre ${WINDOW_DAYS} j (depuis $SINCE)."
  echo
  echo "| Indicateur | Valeur |"
  echo "|---|---|"
  echo "| Runs Deploy en echec | **$n_deploy_fail** |"
  echo "| Verdicts notifies (commentaires ## Verdict, hors sabotage) | **$n_verdicts_notifies** |"
  echo "| Ecart (echecs - notifies) | **$ecart** |"
  echo "| VERDICT NON NOTIFIE vu dans les logs (sous-ensemble diagnostique) | **$n_non_notifie_log** |"
  echo "| Reste sans explication (ecart - NON NOTIFIE) | **$n_reste_sans_explication** |"
  echo "| Issues ouvertes sans suite >= ${WINDOW_DAYS} j | **$n_sans_suite_7j** |"
  echo "| Issues/threads sabotage exclus | $n_sabotage_excl |"
  echo
  echo "## Lecture"
  echo
  echo "- Lecart est le signal. Un run en echec sans commentaire ## Verdict gonfle lecart ;"
  echo "  un VERDICT NON NOTIFIE y est deja inclus (echec compte, notifie = 0)."
  echo "- Reste sans explication = ecart - NON NOTIFIE. Toujours affiche, meme a 0. Ce sont les"
  echo "  echecs dans lecart sans trace VERDICT NON NOTIFIE (job mort avant le pas de notif,"
  echo "  log absent, etc.) — pas benins par defaut."
  echo "- Ne pas additionner ecart + NON NOTIFIE : le second est un sous-ensemble diagnostique"
  echo "  de lecart, pas un second compteur."
  echo "- Si ecart > 0 : la notification est degradee ou absente — ce nest pas un parc sain."
  echo "- Si ecart = 0 et sans_suite bas : le branchement sert."
  echo "- Les issues deploy-sabotage sont exclues du denominateur notifie."
  echo
  echo '```'
  echo "n_deploy_fail=$n_deploy_fail"
  echo "n_verdicts_notifies=$n_verdicts_notifies"
  echo "n_ecart_notification=$ecart"
  echo "n_non_notifie=$n_non_notifie_log"
  echo "n_reste_sans_explication=$n_reste_sans_explication"
  echo "n_sans_suite_${WINDOW_DAYS}j=$n_sans_suite_7j"
  echo '```'
} > /tmp/dv-kpi-rapport.md

rapport=$(cat /tmp/dv-kpi-rapport.md)
printf '%s\n' "$rapport"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$rapport" >> "$GITHUB_STEP_SUMMARY"
fi

ensure_labels "$REPORT_REPO" 2>/dev/null || true
gh label create "$LABEL_BASE" -R "$REPORT_REPO" --color "B60205" --description "KPI / fil verdicts" 2>/dev/null || true
kpi_num=$(gh issue list -R "$REPORT_REPO" --state open --label "$LABEL_BASE" --json number,title \
  --jq ".[] | select(.title == \"$REPORT_TITLE\") | .number" | head -1 || true)
if [ -z "$kpi_num" ]; then
  gh issue create -R "$REPORT_REPO" --title "$REPORT_TITLE" --body "$rapport" -l "$LABEL_BASE" || true
else
  gh issue edit "$kpi_num" -R "$REPORT_REPO" --body "$rapport" || true
fi
