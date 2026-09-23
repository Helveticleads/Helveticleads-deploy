#!/usr/bin/env bash
# Détecteur d'écart : dernier commit main vs Last-Modified de la page servie.
#
# Trois états — jamais deux :
#   A_JOUR      page ≥ commit, ou retard < 2 h
#   EN_RETARD   page antérieure au commit de plus de 2 h
#   NON_MESURE  muet / sans Last-Modified / dépôt illisible / domaine inconnu
#
# NON_MESURE ne bascule JAMAIS en A_JOUR.
# Échec d'auth du jeton = TOUS les sites en NON_MESURE, issue OUVERTE, raison en tête.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="${DETECTEUR_OWNER:-Helveticleads}"
REPO_DEPLOY="${DETECTEUR_REPO:-Helveticleads/Helveticleads-deploy}"
TOLERANCE_SEC=$((2 * 3600))
ISSUE_TITLE="Écart fusionné ↔ servi"
ISSUE_LABEL="detecteur-ecart"

MODE="${DETECTEUR_MODE:-normal}"   # normal | preuve
GH_READ_TOKEN="${JETON_LECTURE_DEPOTS:?JETON_LECTURE_DEPOTS manquant}"
GH_ISSUE_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN manquant}"

RESULT_DIR="${DETECTEUR_RESULT_DIR:-$ROOT/.detecteur-out}"
mkdir -p "$RESULT_DIR"
: > "$RESULT_DIR/a-jour.tsv"
: > "$RESULT_DIR/en-retard.tsv"
: > "$RESULT_DIR/non-mesure.tsv"

n_a_jour=0; n_en_retard=0; n_non_mesure=0
AUTH_FAIL=""
AUTH_FAIL_DETAIL=""

log() { printf '%s\n' "$*" >&2; }

gh_read()  { GH_TOKEN="$GH_READ_TOKEN"  gh "$@"; }
gh_issue() { GH_TOKEN="$GH_ISSUE_TOKEN" gh "$@"; }

epoch_of() {
  local s="$1"
  date -u -d "$s" +%s 2>/dev/null && return
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$s" +%s 2>/dev/null && return
  date -u -j -f "%a, %d %b %Y %H:%M:%S GMT" "$s" +%s 2>/dev/null && return
  return 1
}

fmt_iso() {
  local e="$1"
  date -u -d "@$e" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$e" +"%Y-%m-%dT%H:%M:%SZ"
}

ecart_h() { awk -v s="$1" 'BEGIN{printf "%.1f", s/3600}'; }

# --- auth : échec bruyant ---------------------------------------------------
verifier_jeton() {
  local out rc
  set +e
  out=$(gh_read api repos/Helveticleads/FR-helvetique-toiture.ch/commits/main \
    --jq '.sha[0:12] + " " + .commit.committer.date' 2>&1)
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    AUTH_FAIL="auth"
    AUTH_FAIL_DETAIL="JETON_LECTURE_DEPOTS illisible (rc=$rc) : $out"
    log "AUTH_FAIL $AUTH_FAIL_DETAIL"
    return 1
  fi
  log "JETON_OK lu: $out"
  return 0
}

dernier_commit_main() {
  gh_read api "repos/$OWNER/$1/commits/main" --jq '.commit.committer.date' 2>/dev/null
}

last_modified() {
  local domain="$1" hdr code lm
  hdr=$(curl -sI -L --max-time 15 "https://${domain}/" 2>/dev/null | tr -d '\r') || { echo "INJOIGNABLE"; return 1; }
  code=$(printf '%s\n' "$hdr" | awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}')
  case "$code" in
    2??) ;;
    *) echo "HTTP_$code"; return 2 ;;
  esac
  lm=$(printf '%s\n' "$hdr" | awk -F': ' 'tolower($1)=="last-modified"{print $2; exit}')
  if [ -z "$lm" ]; then echo "SANS_LAST_MODIFIED"; return 3; fi
  printf '%s\n' "$lm"
}

enregistrer() {
  local etat="$1" repo="$2" domain="$3" commit="$4" servi="$5" ecart="$6" raison="$7"
  local line
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$domain" "$repo" "$commit" "$servi" "$ecart" "$raison")
  case "$etat" in
    A_JOUR)     echo "$line" >> "$RESULT_DIR/a-jour.tsv";     n_a_jour=$((n_a_jour+1)); log "A_JOUR     ${domain:-—} ($repo)" ;;
    EN_RETARD)  echo "$line" >> "$RESULT_DIR/en-retard.tsv";  n_en_retard=$((n_en_retard+1)); log "EN_RETARD  ${domain:-—} écart=${ecart}h" ;;
    NON_MESURE) echo "$line" >> "$RESULT_DIR/non-mesure.tsv"; n_non_mesure=$((n_non_mesure+1)); log "NON_MESURE ${domain:-—} — $raison" ;;
  esac
}

classer() {
  local repo="$1" domain="$2" override="${3:-}"
  local commit_iso servi_raw commit_e servi_e

  if [ -n "$AUTH_FAIL" ]; then
    enregistrer NON_MESURE "$repo" "$domain" "" "" "" "auth: $AUTH_FAIL_DETAIL"
    return
  fi

  if [ -z "$domain" ]; then
    enregistrer NON_MESURE "$repo" "" "" "" "" "domaine inconnu"
    return
  fi

  if [ -n "$override" ]; then
    commit_iso="$override"
  elif [[ "$repo" == PREUVE-* ]]; then
    # Injections de preuve : pas un vrai dépôt — on fixe un commit synthétique
    # pour atteindre le contrôle HTTP (cœur de la preuve).
    commit_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    commit_iso=$(dernier_commit_main "$repo") || commit_iso=""
  fi
  if [ -z "$commit_iso" ]; then
    enregistrer NON_MESURE "$repo" "$domain" "" "" "" "dépôt illisible (commit main)"
    return
  fi
  commit_e=$(epoch_of "$commit_iso") || {
    enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "date commit illisible"
    return
  }

  set +e
  servi_raw=$(last_modified "$domain")
  local rc=$?
  set -e
  case "$rc" in
    0) ;;
    2) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "domaine ne répond pas ($servi_raw)"; return ;;
    3) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "pas de Last-Modified"; return ;;
    *) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "domaine injoignable"; return ;;
  esac

  servi_e=$(epoch_of "$servi_raw") || {
    enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "$servi_raw" "" "Last-Modified illisible"
    return
  }

  local delta=$((commit_e - servi_e))
  local servi_iso; servi_iso=$(fmt_iso "$servi_e")
  if [ "$delta" -le "$TOLERANCE_SEC" ]; then
    enregistrer A_JOUR "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" ""
  else
    enregistrer EN_RETARD "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" ""
  fi
}

# --- charger déclarations ---------------------------------------------------
declare -a SITES_REPO SITES_DOMAIN
declare -a EXCL_REPO EXCL_MOTIF

charger_ligne_site() {
  local repo="$1" domain="$2"
  SITES_REPO+=("$repo")
  SITES_DOMAIN+=("$domain")
}

while IFS='|' read -r repo domain _rest || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  charger_ligne_site "$repo" "$domain"
done < "$DIR/sites-auto.txt"

while IFS='|' read -r repo domain _rest || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  charger_ligne_site "$repo" "$domain"
done < "$DIR/sites-declares.txt"

while IFS=$'\t' read -r repo motif || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  EXCL_REPO+=("$repo")
  EXCL_MOTIF+=("$motif")
done < "$DIR/exclusions.txt"

n_mesurables=${#SITES_REPO[@]}
n_exclus=${#EXCL_REPO[@]}
M_declares=$((n_mesurables + n_exclus))

log "=== Détecteur d'écart — mode=$MODE ==="
log "Déclarés M=$M_declares (mesurables=$n_mesurables + exclus=$n_exclus)"

# --- auth ------------------------------------------------------------------
if ! verifier_jeton; then
  log "Auth en échec : tous les sites → NON_MESURE, issue restera OUVERTE."
fi

# --- mesurer ---------------------------------------------------------------
for i in "${!SITES_REPO[@]}"; do
  classer "${SITES_REPO[$i]}" "${SITES_DOMAIN[$i]}"
done

# --- preuves injectées (jamais en schedule) --------------------------------
if [ "$MODE" = "preuve" ] && [ -z "$AUTH_FAIL" ]; then
  log "=== Injection preuves ==="
  classer "PREUVE-domaine-inexistant" "domaine-qui-nexiste-pas-hl-detecteur.test"
  # Domaine qui répond sans Last-Modified (mesuré aussi dans la flotte réelle)
  classer "PREUVE-sans-last-modified" "domisane-suisse.ch"
  fake_commit=$(date -u -d '+2 days' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v+2d +"%Y-%m-%dT%H:%M:%SZ")
  classer "PREUVE-ecart-fabrique" "helvetique-toiture.ch" "$fake_commit"
fi

N_mesures=$((n_a_jour + n_en_retard + n_non_mesure))
# En mode preuve, N_mesures > n_mesurables (injections). Le dénominateur
# métier reste M/X/mesurables ; on signale l'écart de preuve à part.
if [ "$MODE" != "preuve" ]; then
  if [ "$N_mesures" -ne "$n_mesurables" ]; then
    log "ERREUR dénominateur : mesurés($N_mesures) ≠ mesurables($n_mesurables)"
    exit 2
  fi
  if [ "$((N_mesures + n_exclus))" -ne "$M_declares" ]; then
    log "ERREUR dénominateur : N+X ≠ M"
    exit 2
  fi
fi

{
  echo "M_declares=$M_declares"
  echo "N_mesures=$N_mesures"
  echo "n_mesurables=$n_mesurables"
  echo "n_exclus=$n_exclus"
  echo "n_a_jour=$n_a_jour"
  echo "n_en_retard=$n_en_retard"
  echo "n_non_mesure=$n_non_mesure"
  echo "mode=$MODE"
  echo "auth_fail=${AUTH_FAIL:-non}"
  echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} | tee "$RESULT_DIR/meta.txt" >&2

# --- corps issue -----------------------------------------------------------
markdown_table() {
  local file="$1" title="$2"
  echo "### $title"
  echo
  if [ ! -s "$file" ]; then
    echo "_Aucun._"
    echo
    return
  fi
  echo "| Domaine | Dépôt | Dernier commit | Page servie | Écart (h) | Raison |"
  echo "|---|---|---|---|---|---|"
  while IFS=$'\t' read -r domain repo commit servi ecart raison; do
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "${domain:-—}" "${repo:-—}" "${commit:-—}" "${servi:-—}" "${ecart:-—}" "${raison:-—}"
  done < "$file"
  echo
}

BODY_FILE="$RESULT_DIR/issue-body.md"
{
  if [ -n "$AUTH_FAIL" ]; then
    echo "> [!WARNING]"
    echo "> **ÉCHEC D'AUTHENTIFICATION — détecteur muet évité.**"
    echo "> $AUTH_FAIL_DETAIL"
    echo "> Tous les sites sont classés **NON MESURÉ**. Cette issue reste **ouverte**."
    echo
  fi
  echo "## Rapport du détecteur d'écart"
  echo
  echo "Généré : \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\` · mode : \`$MODE\` · tolérance : 2 h"
  echo
  echo "**Dénominateur** : **$n_mesurables** mesurés sur **$M_declares** déclarés, dont **$n_exclus** exclus"
  echo "(contrôle : $n_mesurables + $n_exclus = $M_declares)."
  if [ "$MODE" = "preuve" ]; then
    echo
    echo "_Mode preuve : $N_mesures lignes classées au total (flotte + injections)._"
  fi
  echo
  echo "Répartition (toutes lignes classées) : **$n_en_retard** en retard · **$n_non_mesure** non mesurés · **$n_a_jour** à jour"
  echo
  echo "<details><summary>Exclusions ($n_exclus)</summary>"
  echo
  echo "| Dépôt | Motif |"
  echo "|---|---|"
  for i in "${!EXCL_REPO[@]}"; do
    printf '| %s | %s |\n' "${EXCL_REPO[$i]}" "${EXCL_MOTIF[$i]}"
  done
  echo
  echo "</details>"
  echo
  markdown_table "$RESULT_DIR/en-retard.tsv" "En retard"
  markdown_table "$RESULT_DIR/non-mesure.tsv" "Non mesuré"
  markdown_table "$RESULT_DIR/a-jour.tsv" "À jour"
  echo "---"
  echo
  echo "_Un site non mesuré n'est jamais classé à jour. Absence de signal ≠ absence de problème._"
} > "$BODY_FILE"

# --- upsert issue unique ---------------------------------------------------
assurer_label() {
  gh_issue label create "$ISSUE_LABEL" -R "$REPO_DEPLOY" --description "Rapport du détecteur d'écart" --color "B60205" 2>/dev/null || true
}
assurer_label

EXISTING=$(gh_issue issue list -R "$REPO_DEPLOY" --state all --limit 50 \
  --json number,title,state,url \
  --jq "[.[] | select(.title == \"$ISSUE_TITLE\")] | .[0] // empty")

# Sain = rien en retard, rien de non mesuré, ET pas d'échec auth
sain=0
if [ -z "$AUTH_FAIL" ] && [ "$n_en_retard" -eq 0 ] && [ "$n_non_mesure" -eq 0 ]; then
  sain=1
fi

upsert_body() {
  local num="$1"
  gh_issue issue edit "$num" -R "$REPO_DEPLOY" --body-file "$BODY_FILE"
}

if [ -z "$EXISTING" ]; then
  URL=$(gh_issue issue create -R "$REPO_DEPLOY" \
    --title "$ISSUE_TITLE" \
    --label "$ISSUE_LABEL" \
    --body-file "$BODY_FILE")
  NUM=$(printf '%s' "$URL" | grep -oE '[0-9]+$')
  if [ "$sain" -eq 1 ]; then
    gh_issue issue close "$NUM" -R "$REPO_DEPLOY" \
      --comment "Tout à jour, rien de non mesuré — détecteur opérationnel."
    log "Issue créée puis fermée : $URL"
  else
    log "Issue créée (ouverte) : $URL"
  fi
else
  NUM=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["number"])')
  STATE=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["state"])')
  URL=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
  upsert_body "$NUM"
  if [ "$sain" -eq 1 ]; then
    if [ "$STATE" = "OPEN" ]; then
      gh_issue issue close "$NUM" -R "$REPO_DEPLOY" \
        --comment "Tout à jour, rien de non mesuré — détecteur opérationnel."
      log "Issue mise à jour et fermée : $URL"
    else
      log "Issue déjà fermée, corps mis à jour : $URL"
    fi
  else
    # Auth fail ou écart : DOIT rester / être ouverte
    if [ "$STATE" = "CLOSED" ]; then
      gh_issue issue reopen "$NUM" -R "$REPO_DEPLOY"
      log "Issue rouverte : $URL"
    else
      log "Issue mise à jour (ouverte) : $URL"
    fi
  fi
fi

echo "$URL" > "$RESULT_DIR/issue-url.txt"
log "DONE issue=$URL M=$M_declares N=$N_mesures X=$n_exclus a_jour=$n_a_jour en_retard=$n_en_retard non_mesure=$n_non_mesure auth=${AUTH_FAIL:-ok}"
