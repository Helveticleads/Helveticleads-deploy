#!/usr/bin/env bash
# KPI hebdo : croise runs Deploy en échec × verdicts notifiés.
# Env :
#   GH_TOKEN
#   WINDOW_DAYS   (défaut 7)
#   REPOS_FILE    liste owner/name (une par ligne) — sinon découverte limitée
#   REPORT_REPO   où publier le tableau de bord (défaut Helveticleads/Helveticleads-deploy)
#   REPORT_TITLE  (défaut « Deploy — KPI verdicts »)
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
  echo "KPI_WARN REPOS_FILE absent — aucun dépôt à sonder" >&2
fi

for repo in "${repos[@]}"; do
  # Runs Deploy en échec sur la fenêtre
  fails=$(gh api "repos/$repo/actions/runs?per_page=50" --jq \
    "[.workflow_runs[] | select((.name|startswith(\"Deploy\")) and .conclusion==\"failure\" and .created_at >= \"$SINCE\")] | length" 2>/dev/null || echo 0)
  n_deploy_fail=$((n_deploy_fail + fails))

  # Commentaires / issues de verdict (hors sabotage) créés dans la fenêtre
  # Issues avec label deploy-verdict : compter commentaires « ## Verdict » récents
  issue_nums=$(gh issue list -R "$repo" --state all --label "$LABEL_BASE" --limit 20 \
    --json number,labels --jq '.[].number' 2>/dev/null || true)
  for num in $issue_nums; do
    labels=$(gh issue view "$num" -R "$repo" --json labels -q '[.labels[].name] | join(",")' 2>/dev/null || true)
    if printf '%s' "$labels" | grep -q "$LABEL_SABOTAGE"; then
      n_sabotage_excl=$((n_sabotage_excl + 1))
      continue
    fi
    # commentaires Verdict dans la fenêtre
    n_c=$(gh api "repos/$repo/issues/$num/comments?per_page=100" --jq \
      "[.[] | select(.created_at >= \"$SINCE\" and (.body|startswith(\"## Verdict\")))] | length" 2>/dev/null || echo 0)
    n_verdicts_notifies=$((n_verdicts_notifies + n_c))
    # aussi créations d'issue (corps initial contient Verdict) dans la fenêtre
    created=$(gh issue view "$num" -R "$repo" --json createdAt,state -q '.createdAt + " " + .state' 2>/dev/null || true)
    created_at=${created%% *}
    state=${created##* }
    if [ -n "$created_at" ] && [[ "$created_at" >= "$SINCE" ]]; then
      # le corps initial compte comme 1 verdict si pas déjà dans comments
      :
    fi
    if [ "$state" = "OPEN" ]; then
      # sans suite : ouverte et créée ou dernier verdict il y a ≥ WINDOW_DAYS
      age_ok=$(gh api "repos/$repo/issues/$num/comments?per_page=100" --jq \
        --arg since "$SINCE" \
        'if length==0 then true else (map(select(.body|startswith("## Verdict"))) | if length==0 then true else (max_by(.created_at).created_at < $since) end) end' 2>/dev/null || echo false)
      # Simplification : ouverte depuis avant SINCE
      if [[ "$created_at" < "$SINCE" ]] || [ "$age_ok" = "true" ]; then
        # ouverte et pas de verdict récent → sans suite
        recent=$(gh api "repos/$repo/issues/$num/comments?per_page=100" --jq \
          "[.[] | select(.created_at >= \"$SINCE\" and (.body|startswith(\"## Verdict\") or .body|startswith(\"## Résolu\")))] | length" 2>/dev/null || echo 0)
        if [ "${recent:-0}" -eq 0 ] && [[ "$created_at" < "$SINCE" ]]; then
          n_sans_suite_7j=$((n_sans_suite_7j + 1))
        fi
      fi
    fi
  done

  # Runs en échec dont le log/summary porte VERDICT NON NOTIFIÉ (échantillon)
  # Limité : on scanne les 20 derniers runs failure pour la chaîne
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

rapport=$(cat <<EOF
# $REPORT_TITLE

Mesure au $NOW — fenêtre ${WINDOW_DAYS} j (depuis $SINCE).

| Indicateur | Valeur |
|---|---|
| Runs Deploy en échec | **$n_deploy_fail** |
| Verdicts notifiés (commentaires \`## Verdict\`, hors sabotage) | **$n_verdicts_notifies** |
| Écart (échecs − notifiés) | **$ecart** |
| \`VERDICT NON NOTIFIÉ\` vu dans les logs (sous-ensemble diagnostique) | **$n_non_notifie_log** |
| Issues ouvertes sans suite ≥ ${WINDOW_DAYS} j | **$n_sans_suite_7j** |
| Issues/threads sabotage exclus | $n_sabotage_excl |

## Lecture

- **L'écart est le signal.** Un run en échec sans commentaire \`## Verdict\` gonfle l'écart ;
  un \`VERDICT NON NOTIFIÉ\` y est déjà inclus (échec compté, notifié = 0).
- **Ne pas additionner** écart + NON NOTIFIÉ : le second est un *sous-ensemble diagnostique*
  de l'écart (panne d'écriture d'issue visible dans le résumé), pas un second compteur.
- Si **écart > 0** : la notification est dégradée ou absente — ce n'est **pas** « parc sain ».
- Si écart = 0 et sans_suite bas : le branchement sert.
- Les issues \`deploy-sabotage\` sont exclues du dénominateur notifié.

\`\`\`
n_deploy_fail=$n_deploy_fail
n_verdicts_notifies=$n_verdicts_notifies
n_ecart_notification=$ecart
n_non_notifie=$n_non_notifie_log
n_sans_suite_${WINDOW_DAYS}j=$n_sans_suite_7j
\`\`\`
EOF
)

printf '%s\n' "$rapport"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  printf '%s\n' "$rapport" >> "$GITHUB_STEP_SUMMARY"
fi

# Upsert issue tableau de bord (corps remplacé — OK pour KPI)
ensure_labels "$REPORT_REPO" 2>/dev/null || true
gh label create "$LABEL_BASE" -R "$REPORT_REPO" --color "B60205" --description "KPI / fil verdicts" 2>/dev/null || true
kpi_num=$(gh issue list -R "$REPORT_REPO" --state open --label "$LABEL_BASE" --json number,title \
  --jq ".[] | select(.title == \"$REPORT_TITLE\") | .number" | head -1 || true)
if [ -z "$kpi_num" ]; then
  gh issue create -R "$REPORT_REPO" --title "$REPORT_TITLE" --body "$rapport" -l "$LABEL_BASE" || true
else
  gh issue edit "$kpi_num" -R "$REPORT_REPO" --body "$rapport" || true
fi
