#!/usr/bin/env bash
# Détecteur d'écart : dernier commit main vs DATE (Last-Modified) du fichier servi.
# Empreinte (sha256) du corps servi : preuve d'observation réelle — jamais un
# marqueur DEPLOY_COMMIT écrit par le déploiement lui-même.
#
# Trois états — jamais deux :
#   A_JOUR      page ≥ commit, ou retard < 2 h
#   EN_RETARD   page antérieure au commit de plus de 2 h
#   NON_MESURE  muet / sans Last-Modified / dépôt illisible / domaine inconnu
#
# NON_MESURE ne bascule JAMAIS en A_JOUR.
# Échec d'auth du jeton (401/403/refus) = TOUS les sites en NON_MESURE,
# issue OUVERTE, raison en TÊTE. Interdiction de rendre « tout va bien ».
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="${DETECTEUR_OWNER:-Helveticleads}"
REPO_DEPLOY="${DETECTEUR_REPO:-Helveticleads/Helveticleads-deploy}"
TOLERANCE_SEC=$((2 * 3600))
ISSUE_TITLE="Écart fusionné ↔ servi"
ISSUE_LABEL="detecteur-ecart"
# Expiration connue du fine-grained token (portée Contents lecture seule).
JETON_EXPIRE_LE="${DETECTEUR_JETON_EXPIRE:-2027-09-23}"

MODE="${DETECTEUR_MODE:-normal}"   # normal | preuve
# Jeton vide = échec d'auth bruyant (pas un abort silencieux) — preuve sabotage.
GH_READ_TOKEN="${JETON_LECTURE_DEPOTS-}"
GH_ISSUE_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN manquant}"

RESULT_DIR="${DETECTEUR_RESULT_DIR:-$ROOT/.detecteur-out}"
mkdir -p "$RESULT_DIR"
: > "$RESULT_DIR/a-jour.tsv"
: > "$RESULT_DIR/en-retard.tsv"
: > "$RESULT_DIR/non-mesure.tsv"

n_a_jour=0; n_en_retard=0; n_non_mesure=0
AUTH_FAIL=""
AUTH_FAIL_DETAIL=""
M_precedent="${DETECTEUR_M_PRECEDENT:-}"

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
# Un 401/403 DOIT hurler. Un jeton vide aussi. Jamais de silence « tout va bien ».
verifier_jeton() {
  local out rc http
  if [ -z "$GH_READ_TOKEN" ]; then
    AUTH_FAIL="auth"
    AUTH_FAIL_DETAIL="JETON_LECTURE_DEPOTS absent ou vide — impossible de lire les dépôts. Sabotage ou secret manquant."
    log "AUTH_FAIL $AUTH_FAIL_DETAIL"
    return 1
  fi
  set +e
  out=$(gh_read api repos/Helveticleads/FR-helvetique-toiture.ch/commits/main \
    --jq '.sha[0:12] + " " + .commit.committer.date' 2>&1)
  rc=$?
  set -e
  http=$(printf '%s' "$out" | grep -oE '\(?HTTP[ /]?([0-9]{3})\)?' | grep -oE '[0-9]{3}' | tail -1 || true)
  if [ "$rc" -ne 0 ]; then
    AUTH_FAIL="auth"
    if [ "$http" = "401" ] || [ "$http" = "403" ]; then
      AUTH_FAIL_DETAIL="JETON_LECTURE_DEPOTS refusé (HTTP $http) — jeton expiré, révoqué ou sans droits. Détail : $out"
    else
      AUTH_FAIL_DETAIL="JETON_LECTURE_DEPOTS illisible (rc=$rc http=${http:-?}) : $out"
    fi
    log "AUTH_FAIL $AUTH_FAIL_DETAIL"
    return 1
  fi
  log "JETON_OK lu: $out (expire le $JETON_EXPIRE_LE)"
  return 0
}

dernier_commit_main() {
  gh_read api "repos/$OWNER/$1/commits/main" --jq '.commit.committer.date' 2>/dev/null
}

# Lit DATE (Last-Modified) + empreinte sha256 du corps servi.
# Sortie OK (rc 0) : "<epoch_iso_ou_raw>|<sha256_12>"
# Échecs : INJOIGNABLE / HTTP_xxx / SANS_LAST_MODIFIED
observer_servi() {
  local domain="$1" tmp hdr body code lm hash
  tmp=$(mktemp -d)
  hdr="$tmp/hdr"; body="$tmp/body"
  if ! curl -sS -L --max-time 20 -D "$hdr" -o "$body" "https://${domain}/" 2>/dev/null; then
    echo "INJOIGNABLE"; rm -rf "$tmp"; return 1
  fi
  # Normaliser CRLF
  tr -d '\r' < "$hdr" > "$hdr.n" && mv "$hdr.n" "$hdr"
  code=$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$hdr")
  case "$code" in
    2??) ;;
    *) echo "HTTP_${code:-0}"; rm -rf "$tmp"; return 2 ;;
  esac
  lm=$(awk -F': ' 'tolower($1)=="last-modified"{print $2; exit}' "$hdr")
  if [ -z "$lm" ]; then
    echo "SANS_LAST_MODIFIED"; rm -rf "$tmp"; return 3
  fi
  hash=$(sha256sum "$body" 2>/dev/null | awk '{print substr($1,1,12)}' \
    || shasum -a 256 "$body" | awk '{print substr($1,1,12)}')
  printf '%s|%s\n' "$lm" "$hash"
  rm -rf "$tmp"
  return 0
}

enregistrer() {
  local etat="$1" repo="$2" domain="$3" commit="$4" servi="$5" ecart="$6" raison="$7" empreinte="$8" pub="$9"
  [ -n "$domain" ] || domain="—"
  [ -n "$repo" ] || repo="—"
  [ -n "$commit" ] || commit="—"
  [ -n "$servi" ] || servi="—"
  [ -n "$ecart" ] || ecart="—"
  [ -n "$raison" ] || raison="—"
  [ -n "$empreinte" ] || empreinte="—"
  [ -n "$pub" ] || pub="—"
  local line
  line=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "$domain" "$repo" "$commit" "$servi" "$ecart" "$empreinte" "$pub" "$raison")
  case "$etat" in
    A_JOUR)     echo "$line" >> "$RESULT_DIR/a-jour.tsv";     n_a_jour=$((n_a_jour+1)); log "A_JOUR     $domain ($repo) emp=$empreinte" ;;
    EN_RETARD)  echo "$line" >> "$RESULT_DIR/en-retard.tsv";  n_en_retard=$((n_en_retard+1)); log "EN_RETARD  $domain écart=${ecart}h emp=$empreinte" ;;
    NON_MESURE) echo "$line" >> "$RESULT_DIR/non-mesure.tsv"; n_non_mesure=$((n_non_mesure+1)); log "NON_MESURE $domain — $raison" ;;
  esac
}

classer() {
  local repo="$1" domain="$2" override="${3:-}" pub="${4:-auto}"
  local commit_iso servi_raw commit_e servi_e lm hash

  if [ -n "$AUTH_FAIL" ]; then
    enregistrer NON_MESURE "$repo" "$domain" "" "" "" "auth: $AUTH_FAIL_DETAIL" "" "$pub"
    return
  fi

  if [ -z "$domain" ]; then
    enregistrer NON_MESURE "$repo" "" "" "" "" "domaine inconnu" "" "$pub"
    return
  fi

  if [ -n "$override" ]; then
    commit_iso="$override"
  elif [[ "$repo" == PREUVE-* ]]; then
    commit_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    commit_iso=$(dernier_commit_main "$repo") || commit_iso=""
  fi
  if [ -z "$commit_iso" ]; then
    enregistrer NON_MESURE "$repo" "$domain" "" "" "" "dépôt illisible (commit main)" "" "$pub"
    return
  fi
  commit_e=$(epoch_of "$commit_iso") || {
    enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "date commit illisible" "" "$pub"
    return
  }

  set +e
  servi_raw=$(observer_servi "$domain")
  local rc=$?
  set -e
  case "$rc" in
    0)
      lm="${servi_raw%%|*}"
      hash="${servi_raw#*|}"
      ;;
    2) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "domaine ne répond pas ($servi_raw)" "" "$pub"; return ;;
    3) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "pas de Last-Modified" "" "$pub"; return ;;
    *) enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "" "" "domaine injoignable" "" "$pub"; return ;;
  esac

  servi_e=$(epoch_of "$lm") || {
    enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "$lm" "" "Last-Modified illisible" "$hash" "$pub"
    return
  }

  local delta=$((commit_e - servi_e))
  local servi_iso; servi_iso=$(fmt_iso "$servi_e")
  if [ "$delta" -le "$TOLERANCE_SEC" ]; then
    enregistrer A_JOUR "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" "" "$hash" "$pub"
  else
    enregistrer EN_RETARD "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" "" "$hash" "$pub"
  fi
}

# --- charger déclarations ---------------------------------------------------
declare -a SITES_REPO SITES_DOMAIN SITES_PUB
declare -a EXCL_REPO EXCL_MOTIF

charger_ligne_site() {
  local repo="$1" domain="$2" pub="${3:-auto}"
  SITES_REPO+=("$repo")
  SITES_DOMAIN+=("$domain")
  SITES_PUB+=("$pub")
}

while IFS='|' read -r repo domain _rest || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  charger_ligne_site "$repo" "$domain" "auto"
done < "$DIR/sites-auto.txt"

while IFS='|' read -r repo domain _source pub _rest || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  [ -n "${pub:-}" ] || pub="manuelle"
  charger_ligne_site "$repo" "$domain" "$pub"
done < "$DIR/sites-declares.txt"

while IFS=$'\t' read -r repo motif || [ -n "${repo:-}" ]; do
  [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
  EXCL_REPO+=("$repo")
  EXCL_MOTIF+=("$motif")
done < "$DIR/exclusions.txt"

n_mesurables=${#SITES_REPO[@]}
n_exclus=${#EXCL_REPO[@]}
M_declares=$((n_mesurables + n_exclus))
n_manuels=0
for p in "${SITES_PUB[@]}"; do
  [ "$p" = "manuelle" ] && n_manuels=$((n_manuels+1))
done
# Flotte figée AVANT tout ciblage — sert de M pour la couverture et le verdict.
n_flotte=$n_mesurables
n_manuels_flotte=$n_manuels
passage_cible=0
cible_label=""

# Ajout temporaire pour preuve dénominateur (M change) — avant UNIQUEMENT
# pour que le dénominateur reflète la flotte + 1.
if [ -n "${DETECTEUR_AJOUT_PREUVE:-}" ]; then
  charger_ligne_site "PREUVE-ajout-denom" "domaine-qui-nexiste-pas-hl-detecteur.test" "auto"
  n_mesurables=${#SITES_REPO[@]}
  n_flotte=$n_mesurables
  M_declares=$((n_mesurables + n_exclus))
  log "AJOUT_PREUVE → M=$M_declares (mesurables=$n_mesurables)"
fi

# Passage ciblé (mise au point uniquement). Interdit sur schedule.
# Un ciblage ne modifie PAS n_flotte / n_manuels_flotte / M_declares.
if [ -n "${DETECTEUR_UNIQUEMENT:-}" ]; then
  event_name="${DETECTEUR_EVENT_NAME:-${GITHUB_EVENT_NAME:-}}"
  if [ "$event_name" = "schedule" ]; then
    log "ERREUR : DETECTEUR_UNIQUEMENT interdit sur un passage planifié (schedule)."
    exit 3
  fi
  passage_cible=1
  cible_label="$DETECTEUR_UNIQUEMENT"
  SITES_REPO=("${DETECTEUR_UNIQUEMENT%%|*}")
  SITES_DOMAIN=("${DETECTEUR_UNIQUEMENT#*|}")
  SITES_PUB=("auto")
  n_mesurables=1
  # n_manuels_flotte et n_flotte INTENTIONNELLEMENT inchangés
  log "UNIQUEMENT=$DETECTEUR_UNIQUEMENT (ciblé ; flotte M=$M_declares n_flotte=$n_flotte manuels_flotte=$n_manuels_flotte)"
fi

log "=== Détecteur d'écart — mode=$MODE cible=$passage_cible ==="
log "Déclarés M=$M_declares (flotte mesurable=$n_flotte + exclus=$n_exclus, manuels_flotte=$n_manuels_flotte)"
if [ -n "$M_precedent" ] && [ "$M_precedent" != "$M_declares" ]; then
  log "M a changé : précédent=$M_precedent → actuel=$M_declares"
fi

# --- auth ------------------------------------------------------------------
if ! verifier_jeton; then
  log "Auth en échec : tous les sites → NON_MESURE, issue restera OUVERTE."
fi

# --- mesurer ---------------------------------------------------------------
for i in "${!SITES_REPO[@]}"; do
  classer "${SITES_REPO[$i]}" "${SITES_DOMAIN[$i]}" "" "${SITES_PUB[$i]}"
done

# --- preuves injectées (jamais en schedule) --------------------------------
if [ "$MODE" = "preuve" ] && [ -z "$AUTH_FAIL" ]; then
  log "=== Injection preuves ==="
  classer "PREUVE-domaine-inexistant" "domaine-qui-nexiste-pas-hl-detecteur.test" "" "auto"
  classer "PREUVE-sans-last-modified" "domisane-suisse.ch" "" "manuelle"
  fake_commit=$(date -u -d '+2 days' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v+2d +"%Y-%m-%dT%H:%M:%SZ")
  classer "PREUVE-ecart-fabrique" "helvetique-toiture.ch" "$fake_commit" "auto"
fi

N_mesures=$((n_a_jour + n_en_retard + n_non_mesure))
# En mode preuve / uniquement / ajout, N_mesures peut différer de la flotte fixe.
if [ "$MODE" != "preuve" ] && [ "$passage_cible" -eq 0 ] && [ -z "${DETECTEUR_AJOUT_PREUVE:-}" ]; then
  if [ "$N_mesures" -ne "$n_flotte" ]; then
    log "ERREUR dénominateur : mesurés($N_mesures) ≠ flotte($n_flotte)"
    exit 2
  fi
  if [ "$((N_mesures + n_exclus))" -ne "$M_declares" ]; then
    log "ERREUR dénominateur : N+X ≠ M"
    exit 2
  fi
fi

# Garde de verdict :
#   M_couverture = n_flotte (sites à mesurer). N == M_couverture ⇔ balayage complet.
#   « Tout à jour » seulement si N == M_couverture ET Y == 0 ET retard == 0
#   ET pas ciblé ET pas d'échec auth. Sinon aucune phrase rassurante, issue ouverte.
couverture_complete=0
if [ "$passage_cible" -eq 0 ] && [ "$N_mesures" -eq "$n_flotte" ]; then
  couverture_complete=1
fi
peut_fermer=0
verdict="incomplet"
if [ "$passage_cible" -eq 1 ]; then
  verdict="cible"
elif [ -n "$AUTH_FAIL" ]; then
  verdict="auth"
elif [ "$couverture_complete" -ne 1 ]; then
  verdict="incomplet"
elif [ "$n_non_mesure" -gt 0 ]; then
  verdict="non_mesure"
elif [ "$n_en_retard" -gt 0 ]; then
  verdict="retard"
elif [ "$n_a_jour" -eq "$N_mesures" ]; then
  verdict="a_jour"
  peut_fermer=1
else
  verdict="incomplet"
fi

{
  echo "M_declares=$M_declares"
  echo "N_mesures=$N_mesures"
  echo "n_flotte=$n_flotte"
  echo "n_mesurables=$n_mesurables"
  echo "n_exclus=$n_exclus"
  echo "n_manuels=$n_manuels_flotte"
  echo "n_a_jour=$n_a_jour"
  echo "n_en_retard=$n_en_retard"
  echo "n_non_mesure=$n_non_mesure"
  echo "mode=$MODE"
  echo "passage_cible=$passage_cible"
  echo "couverture_complete=$couverture_complete"
  echo "peut_fermer=$peut_fermer"
  echo "verdict=$verdict"
  echo "auth_fail=${AUTH_FAIL:-non}"
  echo "jeton_expire=$JETON_EXPIRE_LE"
  echo "generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [ -n "$M_precedent" ]; then
    echo "M_precedent=$M_precedent"
    if [ "$M_precedent" != "$M_declares" ]; then
      echo "M_changed=oui"
    else
      echo "M_changed=non"
    fi
  fi
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
  echo "| Domaine | Dépôt | Dernier commit | Page servie | Écart (h) | Empreinte | Publication | Raison |"
  echo "|---|---|---|---|---|---|---|---|"
  while IFS=$'\t' read -r domain repo commit servi ecart empreinte pub raison; do
    printf '| %s | %s | %s | %s | %s | `%s` | %s | %s |\n' \
      "${domain:-—}" "${repo:-—}" "${commit:-—}" "${servi:-—}" \
      "${ecart:-—}" "${empreinte:-—}" "${pub:-—}" "${raison:-—}"
  done < "$file"
  echo
}

BODY_FILE="$RESULT_DIR/issue-body.md"
{
  # PREMIÈRE ligne du rapport : le ratio N/M — avant tout le reste.
  echo "**N/M** : **$N_mesures**/**$n_flotte**"
  echo

  if [ -n "$AUTH_FAIL" ]; then
    echo "> [!CAUTION]"
    echo "> **ÉCHEC D'AUTHENTIFICATION — le détecteur ne voit plus rien.**"
    echo "> $AUTH_FAIL_DETAIL"
    echo "> Tous les sites sont classés **NON MESURÉ**. Cette issue reste **ouverte**."
    echo "> Un zéro « à jour » sans vision serait exactement le défaut que ce détecteur doit supprimer."
    echo
  fi

  if [ "$passage_cible" -eq 1 ]; then
    echo "## PASSAGE CIBLÉ — pas un balayage complet"
    echo
    echo "**Cible** : \`$cible_label\`"
    echo
    echo "> Ce rapport ne porte **aucune conclusion** de flotte et **ne ferme pas** l'issue."
    echo
  else
    echo "## Rapport du détecteur d'écart"
    echo
  fi

  echo "Déclarés totaux : **$M_declares** (= $n_flotte mesurables + $n_exclus exclus). Dont **$n_non_mesure** non mesurés (Y). Publication manuelle : **$n_manuels_flotte**."
  echo
  echo "Généré : \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\` · mode : \`$MODE\` · tolérance : 2 h · jeton expire le **$JETON_EXPIRE_LE**"
  echo
  case "$verdict" in
    a_jour)
      echo "**Verdict** : tout à jour — N/M complet ($N_mesures/$n_flotte), Y = 0, aucun retard."
      ;;
    cible)
      echo "**Verdict** : passage ciblé — aucune conclusion flotte."
      ;;
    auth)
      echo "**Verdict** : authentification en échec — issue ouverte, aucun « tout à jour »."
      ;;
    incomplet)
      echo "**Verdict** : passage incomplet (N < M : $N_mesures < $n_flotte) — aucune conclusion rassurante, issue ouverte."
      ;;
    non_mesure)
      echo "**Verdict** : Y = $n_non_mesure non mesuré(s) — issue ouverte."
      ;;
    retard)
      echo "**Verdict** : $n_en_retard site(s) en retard — issue ouverte."
      ;;
    *)
      echo "**Verdict** : état non rassurant (verdict=$verdict) — issue ouverte."
      ;;
  esac
  echo
  if [ -n "$M_precedent" ] && [ "$M_precedent" != "$M_declares" ]; then
    echo "> **M a changé** entre deux passages : $M_precedent → $M_declares."
    echo
  fi
  if [ "$MODE" = "preuve" ]; then
    echo "_Mode preuve : injections domaine inexistant / sans Last-Modified / écart fabriqué incluses._"
    echo
  fi
  echo "Répartition ce passage : **$n_en_retard** en retard · **$n_non_mesure** non mesurés · **$n_a_jour** à jour"
  echo
  echo "<details><summary>Publication manuelle ($n_manuels_flotte) — aucun automatisme de rattrapage</summary>"
  echo
  echo "| Dépôt | Domaine |"
  echo "|---|---|"
  while IFS='|' read -r repo domain _source pub _rest || [ -n "${repo:-}" ]; do
    [[ -z "${repo:-}" || "$repo" =~ ^# ]] && continue
    [ "${pub:-}" = "manuelle" ] || continue
    printf '| %s | %s |\n' "$repo" "$domain"
  done < "$DIR/sites-declares.txt"
  echo
  echo "</details>"
  echo
  echo "<details><summary>Exclusions ($n_exclus) — jamais classées EN RETARD</summary>"
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
  echo "_Mesure = date Last-Modified du HTML servi + empreinte sha256[0:12] du corps. Pas de marqueur circulaire DEPLOY_COMMIT._"
  echo
  echo "_Un site non mesuré n'est jamais classé à jour. N < M ou Y > 0 ⇒ pas de clôture._"
} > "$BODY_FILE"

# Mode dry-run : pas d'upsert issue (preuves locales / sabotage auth hors Actions issues).
if [ "${DETECTEUR_DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN" > "$RESULT_DIR/issue-url.txt"
  log "DONE dry-run N/M=$N_mesures/$n_flotte M=$M_declares Y=$n_non_mesure verdict=$verdict peut_fermer=$peut_fermer cible=$passage_cible auth=${AUTH_FAIL:-ok}"
  exit 0
fi

# --- upsert issue unique ---------------------------------------------------
assurer_label() {
  gh_issue label create "$ISSUE_LABEL" -R "$REPO_DEPLOY" --description "Rapport du détecteur d'écart" --color "B60205" 2>/dev/null || true
}
assurer_label

EXISTING=$(gh_issue issue list -R "$REPO_DEPLOY" --state all --limit 50 \
  --json number,title,state,url \
  --jq "[.[] | select(.title == \"$ISSUE_TITLE\")] | .[0] // empty")

upsert_body() {
  local num="$1"
  gh_issue issue edit "$num" -R "$REPO_DEPLOY" --body-file "$BODY_FILE"
}

# Passage ciblé : met à jour le corps, ne conclut pas, ne ferme jamais.
if [ "$passage_cible" -eq 1 ]; then
  if [ -z "$EXISTING" ]; then
    URL=$(gh_issue issue create -R "$REPO_DEPLOY" \
      --title "$ISSUE_TITLE" \
      --label "$ISSUE_LABEL" \
      --body-file "$BODY_FILE")
    log "Issue créée (ouverte, passage ciblé sans conclusion) : $URL"
  else
    NUM=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["number"])')
    STATE=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["state"])')
    URL=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
    upsert_body "$NUM"
    if [ "$STATE" = "CLOSED" ]; then
      gh_issue issue reopen "$NUM" -R "$REPO_DEPLOY" \
        --comment "Passage ciblé (\`$cible_label\`) — rouverture, aucune conclusion flotte."
      log "Issue rouverte (passage ciblé) : $URL"
    else
      log "Issue mise à jour (ouverte, passage ciblé, pas de conclusion) : $URL"
    fi
  fi
  echo "$URL" > "$RESULT_DIR/issue-url.txt"
  echo "$M_declares" > "$RESULT_DIR/M_declares.txt"
  log "DONE issue=$URL N/M=$N_mesures/$n_flotte verdict=cible peut_fermer=0"
  exit 0
fi

if [ -z "$EXISTING" ]; then
  URL=$(gh_issue issue create -R "$REPO_DEPLOY" \
    --title "$ISSUE_TITLE" \
    --label "$ISSUE_LABEL" \
    --body-file "$BODY_FILE")
  NUM=$(printf '%s' "$URL" | grep -oE '[0-9]+$')
  if [ "$peut_fermer" -eq 1 ]; then
    gh_issue issue close "$NUM" -R "$REPO_DEPLOY" \
      --comment "Tout à jour — N/M=$N_mesures/$n_flotte, Y=0."
    log "Issue créée puis fermée : $URL"
  else
    log "Issue créée (ouverte, verdict=$verdict) : $URL"
  fi
else
  NUM=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["number"])')
  STATE=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["state"])')
  URL=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
  upsert_body "$NUM"
  if [ "$peut_fermer" -eq 1 ]; then
    if [ "$STATE" = "OPEN" ]; then
      gh_issue issue close "$NUM" -R "$REPO_DEPLOY" \
        --comment "Tout à jour — N/M=$N_mesures/$n_flotte, Y=0."
      log "Issue mise à jour et fermée : $URL"
    else
      log "Issue déjà fermée, corps mis à jour : $URL"
    fi
  else
    # N < M, Y > 0, retard, ou auth : DOIT rester / être ouverte. Jamais de phrase rassurante.
    if [ "$STATE" = "CLOSED" ]; then
      gh_issue issue reopen "$NUM" -R "$REPO_DEPLOY" \
        --comment "Rouverture — verdict=$verdict (N/M=$N_mesures/$n_flotte, Y=$n_non_mesure)."
      log "Issue rouverte : $URL"
    else
      log "Issue mise à jour (ouverte, verdict=$verdict) : $URL"
    fi
  fi
fi

echo "$URL" > "$RESULT_DIR/issue-url.txt"
echo "$M_declares" > "$RESULT_DIR/M_declares.txt"
log "DONE issue=$URL N/M=$N_mesures/$n_flotte M=$M_declares Y=$n_non_mesure verdict=$verdict peut_fermer=$peut_fermer auth=${AUTH_FAIL:-ok}"
