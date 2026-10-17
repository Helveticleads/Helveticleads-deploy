#!/usr/bin/env bash
# Sonde d'épinglage : quelle ref chaque appelant utilise, écart v1↔main, âge de v1.
# Toujours parle, même à écart 0.
# Env : GH_TOKEN, REPOS_FILE (owner/name une par ligne), DEPLOY_REPO (défaut Helveticleads/Helveticleads-deploy)
set -euo pipefail

DEPLOY_REPO="${DEPLOY_REPO:-Helveticleads/Helveticleads-deploy}"
REPOS_FILE="${REPOS_FILE:?REPOS_FILE manquant}"

main_sha=$(gh api "repos/$DEPLOY_REPO/commits/main" --jq .sha)
v1_ref=$(gh api "repos/$DEPLOY_REPO/git/ref/tags/v1" 2>/dev/null || echo "")
v1_sha=""
if [ -n "$v1_ref" ]; then
  obj_type=$(printf '%s' "$v1_ref" | jq -r .object.type)
  obj_sha=$(printf '%s' "$v1_ref" | jq -r .object.sha)
  if [ "$obj_type" = "tag" ]; then
    v1_sha=$(gh api "repos/$DEPLOY_REPO/git/tags/$obj_sha" --jq .object.sha)
  else
    v1_sha=$obj_sha
  fi
fi

v1_date=$(gh api "repos/$DEPLOY_REPO/commits/$v1_sha" --jq .commit.committer.date 2>/dev/null || echo "?")
# commits main not in v1
if [ -n "$v1_sha" ] && [ -n "$main_sha" ]; then
  n_ahead=$(gh api "repos/$DEPLOY_REPO/compare/$v1_sha...$main_sha" --jq .ahead_by 2>/dev/null || echo "?")
else
  n_ahead="?"
fi

n_v1=0
n_main=0
n_other=0
n_repos=0
declare -a other_list=()

while IFS= read -r repo || [ -n "$repo" ]; do
  [ -z "$repo" ] && continue
  [[ "$repo" =~ ^# ]] && continue
  # allow bare name
  case "$repo" in
    */*) full="$repo" ;;
    *) full="Helveticleads/$repo" ;;
  esac
  n_repos=$((n_repos + 1))
  # collect refs from all workflow files
  refs=$(gh api "repos/$full/contents/.github/workflows" --jq '.[].name' 2>/dev/null || true)
  found_ref=""
  for name in $refs; do
    case "$name" in
      *.yml|*.yaml) ;;
      *) continue ;;
    esac
    raw=$(gh api "repos/$full/contents/.github/workflows/$name" --jq .content 2>/dev/null || true)
    [ -z "$raw" ] && continue
    text=$(printf '%s' "$raw" | base64 -d 2>/dev/null || true)
    while IFS= read -r line; do
      ref=${line##*@}
      ref=${ref%%[[:space:]]*}
      found_ref="$ref"
      case "$ref" in
        v1) n_v1=$((n_v1 + 1));;
        main) n_main=$((n_main + 1));;
        *) n_other=$((n_other + 1)); other_list+=("$full:$name@$ref");;
      esac
    done < <(printf '%s\n' "$text" | grep -E 'Helveticleads-deploy/\.github/workflows/.*\.yml@' || true)
  done
  if [ -z "$found_ref" ]; then
    n_other=$((n_other + 1))
    other_list+=("$full:AUCUNE_REF")
  fi
done < "$REPOS_FILE"

# âge de v1 en jours
now_epoch=$(date -u +%s)
v1_epoch=$(date -u -d "$v1_date" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$v1_date" +%s 2>/dev/null || echo 0)
if [ "$v1_epoch" -gt 0 ]; then
  age_days=$(( (now_epoch - v1_epoch) / 86400 ))
else
  age_days="?"
fi

{
  echo "## Sonde épinglage v1"
  echo
  echo "| Indicateur | Valeur |"
  echo "|---|---|"
  echo "| SHA main | \`$main_sha\` |"
  echo "| SHA v1 | \`$v1_sha\` |"
  echo "| Commits main en avance sur v1 | **$n_ahead** |"
  echo "| Âge de v1 (jours depuis le commit pointé) | **$age_days** |"
  echo "| Refs @v1 vues (occurrences) | **$n_v1** |"
  echo "| Refs @main restantes | **$n_main** |"
  echo "| Autres / absentes | **$n_other** |"
  echo "| Dépôts sondés | $n_repos |"
  echo
  echo "Lecture : si **@main restantes > 0**, le parc n est pas encore freine. Si **commits en avance > 0** et **age_days** croit sans promotion, le reseau gele — ce n est pas un silence sain."
  echo
  echo '```'
  echo "n_epingle_v1=$n_v1"
  echo "n_encore_main=$n_main"
  echo "n_epingle_autre=$n_other"
  echo "n_commits_main_ahead_v1=$n_ahead"
  echo "v1_age_days=$age_days"
  echo "v1_sha=$v1_sha"
  echo "main_sha=$main_sha"
  echo '```'
  if [ "${#other_list[@]}" -gt 0 ] && [ "$n_other" -gt 0 ]; then
    echo
    echo "### Occurrences hors @v1 (extrait)"
    for x in "${other_list[@]:0:30}"; do echo "- $x"; done
  fi
}
