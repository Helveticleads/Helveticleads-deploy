#!/usr/bin/env bash
# Détecteur d'écart : dernier commit main vs DATE (Last-Modified) du fichier servi.
# Empreinte (sha256) du corps servi : preuve d'observation réelle — jamais un
# marqueur DEPLOY_COMMIT écrit par le déploiement lui-même.
#
# Marqueur de publication (dépôt du site, interne, jamais servi) :
#   .helveticleads/publication = brouillon | en_ligne
#   ABSENT = en_ligne = surveillé (dépôt neuf fait du bruit jusqu'au premier fichier).
#
# États — exclusifs :
#   A_JOUR              page ≥ commit, ou retard < 2 h (mesure par DATE)
#   EN_RETARD           page antérieure au commit de plus de 2 h (mesure par DATE)
#   SUIVI_PAR_EMPREINTE sans Last-Modified : compare l'empreinte à l'observation
#                       précédente (ne compare PAS à main)
#   INJOIGNABLE         en_ligne + domaine muet, après DEUX passages consécutifs
#                       en échec (sévérité > EN_RETARD, bloquant)
#   AVERT_INJOIGNABLE   premier échec d'atteinte seul — avertissement non bloquant
#   BROUILLON           marqueur brouillon, âge < 60 j — hors population
#   BROUILLON_DORMANT   marqueur brouillon, âge ≥ 60 j — bloquant
#   NON_MESURE          dépôt illisible / domaine inconnu / date illisible
#                       (plus : injoignable ni brouillon — scindés ci-dessus)
#
# NON_MESURE et SUIVI_PAR_EMPREINTE ne basculent JAMAIS en A_JOUR.
# Échec d'auth du jeton (401/403/refus) = TOUS les sites en NON_MESURE,
# issue OUVERTE, raison en TÊTE. Interdiction de rendre « tout va bien ».
#
# peut_fermer si : aucun EN_RETARD, aucun INJOIGNABLE, aucun BROUILLON_DORMANT,
# pas d'échec d'authentification, et couverture complète (N == population).
#
# Persistance empreintes + injoignables : blocs HTML commentés dans le corps
# de l'issue (pas de commit par passage). Survit à un passage raté.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OWNER="${DETECTEUR_OWNER:-Helveticleads}"
REPO_DEPLOY="${DETECTEUR_REPO:-Helveticleads/Helveticleads-deploy}"
TOLERANCE_SEC=$((2 * 3600))
BROUILLON_DORMANT_SEC=$((60 * 24 * 3600))
ISSUE_TITLE="Écart fusionné ↔ servi"
ISSUE_LABEL="detecteur-ecart"
JETON_EXPIRE_LE="${DETECTEUR_JETON_EXPIRE:-2027-09-23}"
EMP_MARKER_BEGIN="<!-- DETECTEUR_EMPREINTES_V1"
EMP_MARKER_END="-->"
INJ_MARKER_BEGIN="<!-- DETECTEUR_INJOIGNABLE_V1"
INJ_MARKER_END="-->"
PUB_PATH=".helveticleads/publication"

MODE="${DETECTEUR_MODE:-normal}"
GH_READ_TOKEN="${JETON_LECTURE_DEPOTS-}"
GH_ISSUE_TOKEN="${GITHUB_TOKEN:?GITHUB_TOKEN manquant}"

RESULT_DIR="${DETECTEUR_RESULT_DIR:-$ROOT/.detecteur-out}"
mkdir -p "$RESULT_DIR"
: > "$RESULT_DIR/a-jour.tsv"
: > "$RESULT_DIR/en-retard.tsv"
: > "$RESULT_DIR/non-mesure.tsv"
: > "$RESULT_DIR/suivi-empreinte.tsv"
: > "$RESULT_DIR/injoignable.tsv"
: > "$RESULT_DIR/avertissement-injoignable.tsv"
: > "$RESULT_DIR/brouillon.tsv"
: > "$RESULT_DIR/brouillon-dormant.tsv"
: > "$RESULT_DIR/empreintes-nouvelles.txt"
: > "$RESULT_DIR/injoignable-nouvelles.txt"
PREV_EMP_FILE="$RESULT_DIR/empreintes-precedentes.txt"
PREV_INJ_FILE="$RESULT_DIR/injoignable-precedents.txt"
: > "$PREV_EMP_FILE"
: > "$PREV_INJ_FILE"

n_a_jour=0; n_en_retard=0; n_non_mesure=0; n_suivi=0
n_injoignable=0; n_avert_inj=0; n_brouillon=0; n_brouillon_dormant=0
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
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }
jours_depuis() {
  local e="$1" now
  now=$(date -u +%s)
  awk -v a="$now" -v b="$e" 'BEGIN{printf "%.0f", (a-b)/86400}'
}

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

# Lit .helveticleads/publication sur main.
# stdout : valeur|depuis_iso  (valeur = brouillon|en_ligne)
# ABSENT ou contenu invalide → en_ligne (fail-closed : reste dans le filet).
# Override tests : DETECTEUR_MARQUEUR_OVERRIDE="repo|valeur|depuis_iso" (répétable, une ligne = un dépôt).
lire_marqueur_publication() {
  local repo="$1" override val depuis raw b64 http out
  if [ -n "${DETECTEUR_MARQUEUR_OVERRIDE:-}" ]; then
    override=$(printf '%s\n' "$DETECTEUR_MARQUEUR_OVERRIDE" | awk -F'|' -v r="$repo" '$1==r {print; exit}')
    if [ -n "$override" ]; then
      val=$(printf '%s' "$override" | cut -d'|' -f2)
      depuis=$(printf '%s' "$override" | cut -d'|' -f3)
      printf '%s|%s\n' "$val" "${depuis:-$(now_iso)}"
      return 0
    fi
  fi
  if [[ "$repo" == PREUVE-* ]]; then
    printf 'en_ligne|%s\n' "$(now_iso)"
    return 0
  fi
  set +e
  out=$(gh_read api "repos/$OWNER/$repo/contents/$PUB_PATH?ref=main" 2>&1)
  http=$?
  set -e
  if [ "$http" -ne 0 ]; then
    if printf '%s' "$out" | grep -qE '404|Not Found'; then
      printf 'en_ligne|%s\n' "$(now_iso)"
      return 0
    fi
    # Autre erreur de lecture → en_ligne (ne pas sortir du filet par omission)
    log "WARN marqueur illisible $repo — traité en_ligne : $out"
    printf 'en_ligne|%s\n' "$(now_iso)"
    return 0
  fi
  b64=$(printf '%s' "$out" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("content",""))' 2>/dev/null || true)
  raw=$(printf '%s' "$b64" | tr -d '\n' | base64 -d 2>/dev/null | tr -d '\r' | head -1 | tr -d '[:space:]' || true)
  case "$raw" in
    brouillon|en_ligne) val="$raw" ;;
    *)
      log "WARN marqueur invalide '$raw' dans $repo — traité en_ligne"
      printf 'en_ligne|%s\n' "$(now_iso)"
      return 0
      ;;
  esac
  depuis=$(gh_read api "repos/$OWNER/$repo/commits?path=$PUB_PATH&sha=main&per_page=1" \
    --jq '.[0].commit.committer.date' 2>/dev/null || true)
  [ -n "$depuis" ] || depuis=$(now_iso)
  printf '%s|%s\n' "$val" "$depuis"
}

# Cause lisible si les commits depuis la page servie portent [skip ci] / [ci skip].
diagnostic_skip_ci() {
  local repo="$1" servi_iso="$2" out n_total=0 n_skip=0 tip_skip=0 first
  [[ "$repo" == PREUVE-* ]] && return 0
  [ -n "$servi_iso" ] && [ "$servi_iso" != "—" ] || return 0
  set +e
  out=$(gh_read api "repos/$OWNER/$repo/commits?sha=main&since=$servi_iso&per_page=30" \
    --jq '.[].commit.message | split("\n")[0]' 2>/dev/null)
  set -e
  [ -n "$out" ] || return 0
  while IFS= read -r first || [ -n "${first:-}" ]; do
    [ -n "$first" ] || continue
    n_total=$((n_total + 1))
    if printf '%s' "$first" | grep -qiE '\[skip ci\]|\[ci skip\]|\[skip actions\]|\[actions skip\]'; then
      n_skip=$((n_skip + 1))
      [ "$n_total" -eq 1 ] && tip_skip=1
    fi
  done <<< "$out"
  if [ "$n_total" -gt 0 ] && [ "$n_skip" -eq "$n_total" ]; then
    printf 'cause probable : les %s commit(s) depuis la page servie portent [skip ci] (déploiement Actions sauté)' "$n_total"
  elif [ "$tip_skip" -eq 1 ]; then
    printf 'cause probable : tip main porte [skip ci] (%s/%s commit(s) skip depuis la page servie)' "$n_skip" "$n_total"
  elif [ "$n_skip" -gt 0 ]; then
    printf 'cause possible : %s/%s commit(s) depuis la page servie portent [skip ci]' "$n_skip" "$n_total"
  fi
}

indice_cache() {
  local hdr="$1" smax next
  smax=$(awk -F': ' 'tolower($1)=="cache-control"{print tolower($2)}' "$hdr" \
    | sed -nE 's/.*s-maxage=([0-9]+).*/\1/p' | head -1)
  next=$(awk -F': ' 'tolower($1)=="x-nextjs-cache"{print $2; exit}' "$hdr")
  if [ -n "$smax" ] && [ "$smax" -ge 86400 ] 2>/dev/null; then
    printf 'empreinte observée derrière un cache de 24 h (s-maxage=%s%s)' \
      "$smax" "${next:+, nextjs=$next}"
  elif [ -n "$smax" ] && [ "$smax" -gt 0 ] 2>/dev/null; then
    printf 'empreinte observée derrière un cache (s-maxage=%ss%s)' \
      "$smax" "${next:+, nextjs=$next}"
  elif [ -n "$next" ]; then
    printf 'empreinte observée derrière cache Next.js (%s)' "$next"
  else
    printf '—'
  fi
}

# rc 0 : lm|hash|cache · rc 4 : |hash|cache (suivi empreinte) · rc 1/2 erreur
observer_servi() {
  local domain="$1" tmp hdr body code lm hash cache
  tmp=$(mktemp -d)
  hdr="$tmp/hdr"; body="$tmp/body"
  if ! curl -sS -L --max-time 20 -D "$hdr" -o "$body" "https://${domain}/" 2>/dev/null; then
    echo "INJOIGNABLE"; rm -rf "$tmp"; return 1
  fi
  tr -d '\r' < "$hdr" > "$hdr.n" && mv "$hdr.n" "$hdr"
  code=$(awk 'BEGIN{c=""} /^HTTP\//{c=$2} END{print c}' "$hdr")
  case "$code" in
    2??) ;;
    *) echo "HTTP_${code:-0}"; rm -rf "$tmp"; return 2 ;;
  esac
  hash=$(sha256sum "$body" 2>/dev/null | awk '{print substr($1,1,12)}' \
    || shasum -a 256 "$body" | awk '{print substr($1,1,12)}')
  cache=$(indice_cache "$hdr")
  lm=$(awk -F': ' 'tolower($1)=="last-modified"{print $2; exit}' "$hdr")
  if [ -z "$lm" ]; then
    printf '|%s|%s\n' "$hash" "$cache"
    rm -rf "$tmp"
    return 4
  fi
  printf '%s|%s|%s\n' "$lm" "$hash" "$cache"
  rm -rf "$tmp"
  return 0
}

charger_empreintes_precedentes() {
  if [ -n "${DETECTEUR_EMPREINTES_PREV:-}" ] && [ -f "$DETECTEUR_EMPREINTES_PREV" ]; then
    cp "$DETECTEUR_EMPREINTES_PREV" "$PREV_EMP_FILE"
    log "Empreintes précédentes depuis fichier ($DETECTEUR_EMPREINTES_PREV)"
    return
  fi
  if [ "${DETECTEUR_DRY_RUN:-0}" = "1" ]; then
    log "Dry-run sans PREV injecté — première observation pour suivi empreinte"
    return
  fi
  local body
  body=$(gh_issue issue view 2 -R "$REPO_DEPLOY" --json body -q .body 2>/dev/null || true)
  if [ -z "$body" ]; then
    log "Pas de corps d'issue — pas d'empreintes précédentes"
    return
  fi
  printf '%s\n' "$body" | awk '
    /<!-- DETECTEUR_EMPREINTES_V1/ {grab=1; next}
    grab && /-->/ {exit}
    grab && NF>=3 {print}
  ' > "$PREV_EMP_FILE" || true
  log "Empreintes précédentes depuis issue : $(wc -l < "$PREV_EMP_FILE" | tr -d " ") ligne(s)"
}

charger_injoignables_precedents() {
  if [ -n "${DETECTEUR_INJOIGNABLE_PREV:-}" ] && [ -f "$DETECTEUR_INJOIGNABLE_PREV" ]; then
    cp "$DETECTEUR_INJOIGNABLE_PREV" "$PREV_INJ_FILE"
    log "Injoignables précédents depuis fichier ($DETECTEUR_INJOIGNABLE_PREV)"
    return
  fi
  if [ "${DETECTEUR_DRY_RUN:-0}" = "1" ]; then
    log "Dry-run sans PREV injoignable injecté — premier échec = avertissement"
    return
  fi
  local body
  body=$(gh_issue issue view 2 -R "$REPO_DEPLOY" --json body -q .body 2>/dev/null || true)
  if [ -z "$body" ]; then
    return
  fi
  printf '%s\n' "$body" | awk '
    /<!-- DETECTEUR_INJOIGNABLE_V1/ {grab=1; next}
    grab && /-->/ {exit}
    grab && NF>=2 {print}
  ' > "$PREV_INJ_FILE" || true
  log "Injoignables précédents depuis issue : $(wc -l < "$PREV_INJ_FILE" | tr -d " ") ligne(s)"
}

prev_hash_for() { awk -v d="$1" '$1==d {print $2; exit}' "$PREV_EMP_FILE"; }
prev_when_for() { awk -v d="$1" '$1==d {print $3; exit}' "$PREV_EMP_FILE"; }
prev_inj_count_for() { awk -v d="$1" '$1==d {print $2; exit}' "$PREV_INJ_FILE"; }

memoriser_empreinte() {
  local domain="$1" hash="$2" when="$3" cache="$4"
  printf '%s %s %s %s\n' "$domain" "$hash" "$when" "$(printf '%s' "$cache" | tr ' ' '_')" \
    >> "$RESULT_DIR/empreintes-nouvelles.txt"
}

memoriser_injoignable() {
  local domain="$1" count="$2" when="$3"
  printf '%s %s %s\n' "$domain" "$count" "$when" >> "$RESULT_DIR/injoignable-nouvelles.txt"
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
    A_JOUR)
      echo "$line" >> "$RESULT_DIR/a-jour.tsv"; n_a_jour=$((n_a_jour+1))
      log "A_JOUR     $domain ($repo) emp=$empreinte" ;;
    EN_RETARD)
      echo "$line" >> "$RESULT_DIR/en-retard.tsv"; n_en_retard=$((n_en_retard+1))
      log "EN_RETARD  $domain écart=${ecart}h emp=$empreinte" ;;
    SUIVI_PAR_EMPREINTE)
      echo "$line" >> "$RESULT_DIR/suivi-empreinte.tsv"; n_suivi=$((n_suivi+1))
      log "SUIVI_EMP  $domain — $ecart emp=$empreinte" ;;
    INJOIGNABLE)
      echo "$line" >> "$RESULT_DIR/injoignable.tsv"; n_injoignable=$((n_injoignable+1))
      log "INJOIGNABLE $domain — $raison" ;;
    AVERT_INJOIGNABLE)
      echo "$line" >> "$RESULT_DIR/avertissement-injoignable.tsv"; n_avert_inj=$((n_avert_inj+1))
      log "AVERT_INJ  $domain — $raison" ;;
    BROUILLON)
      echo "$line" >> "$RESULT_DIR/brouillon.tsv"; n_brouillon=$((n_brouillon+1))
      log "BROUILLON  $domain — $raison" ;;
    BROUILLON_DORMANT)
      echo "$line" >> "$RESULT_DIR/brouillon-dormant.tsv"; n_brouillon_dormant=$((n_brouillon_dormant+1))
      log "BROUILLON_DORMANT $domain — $raison" ;;
    NON_MESURE)
      echo "$line" >> "$RESULT_DIR/non-mesure.tsv"; n_non_mesure=$((n_non_mesure+1))
      log "NON_MESURE $domain — $raison" ;;
  esac
}

classer_par_empreinte() {
  local repo="$1" domain="$2" commit_iso="$3" hash="$4" cache="$5" pub="$6"
  local prev when now obs raison
  now=$(now_iso)
  prev=$(prev_hash_for "$domain")
  when=$(prev_when_for "$domain")
  if [ -z "$prev" ]; then
    obs="première observation le $now"
  elif [ "$prev" = "$hash" ]; then
    obs="inchangé depuis le ${when:-?}"
  else
    obs="a changé le $now"
  fi
  raison="SUIVI PAR EMPREINTE — ne compare pas à main, seulement au passage précédent"
  if [ -n "$cache" ] && [ "$cache" != "—" ]; then
    raison="$raison · $cache"
  fi
  memoriser_empreinte "$domain" "$hash" "$now" "$cache"
  enregistrer SUIVI_PAR_EMPREINTE "$repo" "$domain" "$commit_iso" "$cache" "$obs" "$raison" "$hash" "$pub"
}

# Deux passages consécutifs en échec → INJOIGNABLE bloquant ; un seul → avertissement.
traiter_injoignable() {
  local repo="$1" domain="$2" commit_iso="$3" detail="$4" pub="$5"
  local prev_n now
  now=$(now_iso)
  prev_n=$(prev_inj_count_for "$domain")
  [ -n "$prev_n" ] || prev_n=0
  if [ "$prev_n" -ge 1 ] 2>/dev/null; then
    memoriser_injoignable "$domain" "$((prev_n + 1))" "$now"
    enregistrer INJOIGNABLE "$repo" "$domain" "$commit_iso" "" "" \
      "site en_ligne injoignable sur 2 passages consécutifs ($detail)" "" "$pub"
  else
    memoriser_injoignable "$domain" "1" "$now"
    enregistrer AVERT_INJOIGNABLE "$repo" "$domain" "$commit_iso" "" "" \
      "premier échec d'atteinte ($detail) — non bloquant ; un 2e passage confirme INJOIGNABLE" "" "$pub"
  fi
}

classer() {
  local repo="$1" domain="$2" override="${3:-}" pub="${4:-auto}"
  local commit_iso servi_raw commit_e servi_e lm hash cache rest
  local marqueur_raw marqueur depuis_iso depuis_e age_j skip_diag

  if [ -n "$AUTH_FAIL" ]; then
    enregistrer NON_MESURE "$repo" "$domain" "" "" "" "auth: $AUTH_FAIL_DETAIL" "" "$pub"
    return
  fi
  if [ -z "$domain" ]; then
    enregistrer NON_MESURE "$repo" "" "" "" "" "domaine inconnu" "" "$pub"
    return
  fi

  # Marqueur de publication — ABSENT = en_ligne.
  marqueur_raw=$(lire_marqueur_publication "$repo") || marqueur_raw="en_ligne|$(now_iso)"
  marqueur="${marqueur_raw%%|*}"
  depuis_iso="${marqueur_raw#*|}"
  if [ "$marqueur" = "brouillon" ]; then
    depuis_e=$(epoch_of "$depuis_iso") || depuis_e=$(date -u +%s)
    age_j=$(jours_depuis "$depuis_e")
    local age_sec=$(( $(date -u +%s) - depuis_e ))
    if [ "$age_sec" -ge "$BROUILLON_DORMANT_SEC" ]; then
      enregistrer BROUILLON_DORMANT "$repo" "$domain" "" "$depuis_iso" "${age_j}j" \
        "marqueur brouillon depuis $depuis_iso (${age_j} j ≥ 60) — silence prolongé, bloquant" "" "$pub"
    else
      enregistrer BROUILLON "$repo" "$domain" "" "$depuis_iso" "${age_j}j" \
        "pas encore publié — marqueur brouillon depuis $depuis_iso (âge ${age_j} j)" "" "$pub"
    fi
    return
  fi

  if [ -n "$override" ]; then
    commit_iso="$override"
  elif [[ "$repo" == PREUVE-* ]]; then
    commit_iso=$(now_iso)
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
      rest="${servi_raw#*|}"
      hash="${rest%%|*}"
      cache="${rest#*|}"
      ;;
    4)
      rest="${servi_raw#|}"
      hash="${rest%%|*}"
      cache="${rest#*|}"
      classer_par_empreinte "$repo" "$domain" "$commit_iso" "$hash" "$cache" "$pub"
      return
      ;;
    2) traiter_injoignable "$repo" "$domain" "$commit_iso" "$servi_raw" "$pub"; return ;;
    *) traiter_injoignable "$repo" "$domain" "$commit_iso" "domaine injoignable" "$pub"; return ;;
  esac

  servi_e=$(epoch_of "$lm") || {
    enregistrer NON_MESURE "$repo" "$domain" "$commit_iso" "$lm" "" "Last-Modified illisible" "$hash" "$pub"
    return
  }

  local delta=$((commit_e - servi_e))
  local servi_iso; servi_iso=$(fmt_iso "$servi_e")
  memoriser_empreinte "$domain" "$hash" "$(now_iso)" "${cache:-—}"
  if [ "$delta" -le "$TOLERANCE_SEC" ]; then
    enregistrer A_JOUR "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" "" "$hash" "$pub"
  else
    skip_diag=$(diagnostic_skip_ci "$repo" "$servi_iso" || true)
    enregistrer EN_RETARD "$repo" "$domain" "$commit_iso" "$servi_iso" "$(ecart_h "$delta")" \
      "${skip_diag:-}" "$hash" "$pub"
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

# Empreintes + injoignables du passage précédent (corps d'issue ou fichier injecté).
charger_empreintes_precedentes
charger_injoignables_precedents

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
  # domisane : sans Last-Modified → SUIVI_PAR_EMPREINTE (plus NON_MESURE)
  classer "PREUVE-sans-last-modified" "domisane-suisse.ch" "" "manuelle"
  fake_commit=$(date -u -d '+2 days' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v+2d +"%Y-%m-%dT%H:%M:%SZ")
  classer "PREUVE-ecart-fabrique" "helvetique-toiture.ch" "$fake_commit" "auto"
fi

# Fusion empreintes : précédent + nouvelles (ciblage ne doit pas effacer le reste).
EMP_FUSION="$RESULT_DIR/empreintes-fusion.txt"
{
  if [ -s "$PREV_EMP_FILE" ]; then cat "$PREV_EMP_FILE"; fi
  if [ -s "$RESULT_DIR/empreintes-nouvelles.txt" ]; then cat "$RESULT_DIR/empreintes-nouvelles.txt"; fi
} | awk '{h[$1]=$0} END{for (d in h) print h[d]}' | sort > "$EMP_FUSION"

# Fusion injoignables : domaines atteints avec succès disparaissent (pas dans nouvelles).
# Domaines encore en échec : dernières nouvelles écrasent. Précédents non re-touchés
# ce passage (ciblage) sont conservés.
INJ_FUSION="$RESULT_DIR/injoignable-fusion.txt"
{
  if [ -s "$PREV_INJ_FILE" ]; then cat "$PREV_INJ_FILE"; fi
  if [ -s "$RESULT_DIR/injoignable-nouvelles.txt" ]; then cat "$RESULT_DIR/injoignable-nouvelles.txt"; fi
} | awk '{h[$1]=$0} END{for (d in h) print h[d]}' | sort > "$INJ_FUSION"
# Purge : un domaine A_JOUR / EN_RETARD / SUIVI ce passage n'est plus injoignable.
if [ -s "$RESULT_DIR/empreintes-nouvelles.txt" ] || [ -s "$RESULT_DIR/a-jour.tsv" ] \
   || [ -s "$RESULT_DIR/en-retard.tsv" ] || [ -s "$RESULT_DIR/suivi-empreinte.tsv" ]; then
  awk '
    FNR==NR { ok[$1]=1; next }
    !($1 in ok) { print }
  ' <(awk '{print $1}' "$RESULT_DIR/empreintes-nouvelles.txt" 2>/dev/null; \
       awk -F'\t' '{print $1}' "$RESULT_DIR/a-jour.tsv" "$RESULT_DIR/en-retard.tsv" \
         "$RESULT_DIR/suivi-empreinte.tsv" 2>/dev/null) \
    "$INJ_FUSION" > "$INJ_FUSION.tmp" 2>/dev/null || cp "$INJ_FUSION" "$INJ_FUSION.tmp"
  # Aussi : garder ceux encore en échec (nouvelles injoignable)
  {
    cat "$INJ_FUSION.tmp"
    if [ -s "$RESULT_DIR/injoignable-nouvelles.txt" ]; then cat "$RESULT_DIR/injoignable-nouvelles.txt"; fi
  } | awk '{h[$1]=$0} END{for (d in h) print h[d]}' | sort > "$INJ_FUSION"
  rm -f "$INJ_FUSION.tmp"
fi

# Population = flotte − brouillons (dormants inclus hors mesure mais listés à part).
n_hors_pop=$((n_brouillon + n_brouillon_dormant))
n_population=$((n_flotte - n_hors_pop))
# Mesurés = tout ce qui n'est pas hors population (y compris avertissements).
N_mesures=$((n_a_jour + n_en_retard + n_non_mesure + n_suivi + n_injoignable + n_avert_inj))
# En mode preuve / uniquement / ajout, N_mesures peut différer de la population.
if [ "$MODE" != "preuve" ] && [ "$passage_cible" -eq 0 ] && [ -z "${DETECTEUR_AJOUT_PREUVE:-}" ]; then
  if [ "$((N_mesures + n_hors_pop))" -ne "$n_flotte" ]; then
    log "ERREUR dénominateur : mesurés($N_mesures)+hors_pop($n_hors_pop) ≠ flotte($n_flotte)"
    exit 2
  fi
  if [ "$((n_flotte + n_exclus))" -ne "$M_declares" ]; then
    log "ERREUR dénominateur : flotte+X ≠ M"
    exit 2
  fi
fi

# Garde de verdict / clôture (règle finale) :
#   peut_fermer si couverture complète, pas d'auth, aucun EN_RETARD,
#   aucun INJOIGNABLE, aucun BROUILLON_DORMANT.
couverture_complete=0
if [ "$passage_cible" -eq 0 ] && [ "$N_mesures" -eq "$n_population" ]; then
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
elif [ "$n_injoignable" -gt 0 ]; then
  verdict="injoignable"
elif [ "$n_brouillon_dormant" -gt 0 ]; then
  verdict="brouillon_dormant"
elif [ "$n_en_retard" -gt 0 ]; then
  verdict="retard"
elif [ "$n_non_mesure" -gt 0 ]; then
  # Dépôt illisible etc. — reste visible ; ne bloque plus la clôture seule
  # si la règle finale ne le liste pas. On garde un verdict dédié mais
  # peut_fermer suit la règle explicite (pas de blocage Y).
  verdict="non_mesure"
  if [ "$n_en_retard" -eq 0 ] && [ "$n_injoignable" -eq 0 ] \
     && [ "$n_brouillon_dormant" -eq 0 ] && [ -z "$AUTH_FAIL" ]; then
    peut_fermer=1
  fi
elif [ "$n_a_jour" -eq "$N_mesures" ] || [ "$n_en_retard" -eq 0 ]; then
  # A_JOUR + éventuels SUIVI / AVERT_INJ : clôture OK si pas de seaux bloquants.
  if [ "$n_en_retard" -eq 0 ] && [ "$n_injoignable" -eq 0 ] \
     && [ "$n_brouillon_dormant" -eq 0 ] && [ -z "$AUTH_FAIL" ]; then
    verdict="a_jour"
    peut_fermer=1
  else
    verdict="incomplet"
  fi
else
  verdict="incomplet"
fi

# Force peut_fermer selon règle finale (source de vérité unique).
if [ "$passage_cible" -eq 0 ] && [ -z "$AUTH_FAIL" ] \
   && [ "$couverture_complete" -eq 1 ] \
   && [ "$n_en_retard" -eq 0 ] && [ "$n_injoignable" -eq 0 ] \
   && [ "$n_brouillon_dormant" -eq 0 ]; then
  peut_fermer=1
  [ "$verdict" = "non_mesure" ] || [ "$verdict" = "a_jour" ] || verdict="a_jour"
else
  if [ "$passage_cible" -eq 0 ]; then
    peut_fermer=0
  fi
fi

{
  echo "M_declares=$M_declares"
  echo "N_mesures=$N_mesures"
  echo "n_flotte=$n_flotte"
  echo "n_population=$n_population"
  echo "n_hors_pop=$n_hors_pop"
  echo "n_mesurables=$n_mesurables"
  echo "n_exclus=$n_exclus"
  echo "n_manuels=$n_manuels_flotte"
  echo "n_a_jour=$n_a_jour"
  echo "n_en_retard=$n_en_retard"
  echo "n_non_mesure=$n_non_mesure"
  echo "n_suivi=$n_suivi"
  echo "n_injoignable=$n_injoignable"
  echo "n_avert_inj=$n_avert_inj"
  echo "n_brouillon=$n_brouillon"
  echo "n_brouillon_dormant=$n_brouillon_dormant"
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

markdown_table_suivi() {
  local file="$1"
  echo "### Suivi par empreinte"
  echo
  echo "> **Cet état ne compare rien à \`main\`.** Il constate seulement un changement (ou non) entre deux observations. Un site peut servir un contenu entièrement faux et rester « inchangé » indéfiniment."
  echo
  if [ ! -s "$file" ]; then
    echo "_Aucun._"
    echo
    return
  fi
  echo "| Domaine | Dépôt | Empreinte | Observation | Cache / note | Publication |"
  echo "|---|---|---|---|---|---|"
  while IFS=$'\t' read -r domain repo commit servi ecart empreinte pub raison; do
    printf '| %s | %s | `%s` | %s | %s | %s |\n' \
      "${domain:-—}" "${repo:-—}" "${empreinte:-—}" "${ecart:-—}" "${servi:-—}" "${pub:-—}"
  done < "$file"
  echo
}

markdown_table_brouillon() {
  local file="$1" title="$2"
  echo "### $title"
  echo
  if [ ! -s "$file" ]; then
    echo "_Aucun._"
    echo
    return
  fi
  echo "| Domaine | Dépôt | Marqueur depuis | Âge | Publication | Raison |"
  echo "|---|---|---|---|---|---|"
  while IFS=$'\t' read -r domain repo commit servi ecart empreinte pub raison; do
    printf '| %s | %s | %s | %s | %s | %s |\n' \
      "${domain:-—}" "${repo:-—}" "${servi:-—}" "${ecart:-—}" "${pub:-—}" "${raison:-—}"
  done < "$file"
  echo
}

BODY_FILE="$RESULT_DIR/issue-body.md"
{
  echo "**N/M** : **$N_mesures**/**$n_population** (flotte déclarée $n_flotte, hors population brouillon $n_hors_pop)"
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

  echo "Déclarés totaux : **$M_declares** (= $n_flotte mesurables + $n_exclus exclus). Population surveillée : **$n_population** (flotte − $n_hors_pop brouillon). Dont **$n_non_mesure** non mesurés (Y) · **$n_suivi** suivi par empreinte · **$n_injoignable** injoignable · **$n_avert_inj** avert. injoignable · **$n_brouillon_dormant** brouillon dormant. Publication manuelle : **$n_manuels_flotte**."
  echo
  echo "Généré : \`$(date -u +"%Y-%m-%dT%H:%M:%SZ")\` · mode : \`$MODE\` · tolérance : 2 h · brouillon dormant : 60 j · jeton expire le **$JETON_EXPIRE_LE**"
  echo
  case "$verdict" in
    a_jour)
      echo "**Verdict** : peut fermer — aucun EN_RETARD, aucun INJOIGNABLE, aucun BROUILLON_DORMANT, auth OK, N/population complet ($N_mesures/$n_population)."
      ;;
    cible)
      echo "**Verdict** : passage ciblé — aucune conclusion flotte."
      ;;
    auth)
      echo "**Verdict** : authentification en échec — issue ouverte, aucun « tout à jour »."
      ;;
    incomplet)
      echo "**Verdict** : passage incomplet (N < population : $N_mesures < $n_population) — aucune conclusion rassurante, issue ouverte."
      ;;
    non_mesure)
      echo "**Verdict** : Y = $n_non_mesure non mesuré(s) — signalé ; clôture selon règle finale (pas EN_RETARD / INJOIGNABLE / BROUILLON_DORMANT / auth)."
      ;;
    retard)
      echo "**Verdict** : $n_en_retard site(s) en retard — issue ouverte."
      ;;
    injoignable)
      echo "**Verdict** : $n_injoignable site(s) INJOIGNABLE (2 passages) — incident, issue ouverte."
      ;;
    brouillon_dormant)
      echo "**Verdict** : $n_brouillon_dormant brouillon(s) dormant(s) (≥ 60 j) — issue ouverte."
      ;;
    suivi_empreinte)
      echo "**Verdict** : $n_suivi site(s) en SUIVI PAR EMPREINTE (pas de date comparable à main)."
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
  echo "Répartition ce passage : **$n_en_retard** en retard · **$n_injoignable** injoignable · **$n_avert_inj** avert. injoignable · **$n_brouillon_dormant** brouillon dormant · **$n_brouillon** pas encore publiés · **$n_non_mesure** non mesurés · **$n_suivi** suivi par empreinte · **$n_a_jour** à jour"
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
  markdown_table "$RESULT_DIR/injoignable.tsv" "Injoignable (2 passages — bloquant)"
  markdown_table "$RESULT_DIR/en-retard.tsv" "En retard"
  markdown_table_brouillon "$RESULT_DIR/brouillon-dormant.tsv" "Brouillon dormant (≥ 60 j — bloquant)"
  markdown_table_brouillon "$RESULT_DIR/brouillon.tsv" "Pas encore publiés (brouillon)"
  markdown_table "$RESULT_DIR/avertissement-injoignable.tsv" "Avertissement injoignable (1er échec — non bloquant)"
  markdown_table_suivi "$RESULT_DIR/suivi-empreinte.tsv"
  markdown_table "$RESULT_DIR/non-mesure.tsv" "Non mesuré"
  markdown_table "$RESULT_DIR/a-jour.tsv" "À jour"
  echo "---"
  echo
  echo "_Mesure datée = Last-Modified du HTML servi + empreinte sha256[0:12]. Pas de marqueur circulaire DEPLOY_COMMIT._"
  echo
  echo "_Marqueur \`.helveticleads/publication\` : absent = en_ligne. brouillon = hors population (âge affiché). ≥ 60 j → BROUILLON_DORMANT. INJOIGNABLE après 2 passages. Clôture : pas EN_RETARD / INJOIGNABLE / BROUILLON_DORMANT / auth._"
  echo
  echo "_Un site non mesuré n'est jamais classé à jour. Absence de signal ≠ absence de problème._"
  echo
  echo "_Limite (sites datés) : « À jour » signifie seulement que la page servie n'est pas plus vieille que le dernier commit de main. L'empreinte HTML est relevée mais, pour ces sites, pas encore le critère de classement._"
  echo
  echo "_Persistance des empreintes et des compteurs injoignable : blocs machine ci-dessous dans le corps de l'issue (aucun commit par passage). Survit à un run raté = dernière écriture réussie._"
  echo
  # Bloc machine — ne pas éditer à la main.
  echo "$EMP_MARKER_BEGIN"
  if [ -s "$EMP_FUSION" ]; then cat "$EMP_FUSION"; fi
  echo "$EMP_MARKER_END"
  echo
  echo "$INJ_MARKER_BEGIN"
  if [ -s "$INJ_FUSION" ]; then cat "$INJ_FUSION"; fi
  echo "$INJ_MARKER_END"
} > "$BODY_FILE"

# Mode dry-run : pas d'upsert issue (preuves locales / sabotage auth hors Actions issues).
if [ "${DETECTEUR_DRY_RUN:-0}" = "1" ]; then
  echo "DRY_RUN" > "$RESULT_DIR/issue-url.txt"
  log "DONE dry-run N/pop=$N_mesures/$n_population flotte=$n_flotte M=$M_declares Y=$n_non_mesure inj=$n_injoignable dorm=$n_brouillon_dormant verdict=$verdict peut_fermer=$peut_fermer cible=$passage_cible auth=${AUTH_FAIL:-ok}"
  exit 0
fi

# --- upsert issue unique ---------------------------------------------------
assurer_label() {
  gh_issue label create "$ISSUE_LABEL" -R "$REPO_DEPLOY" --description "Rapport du détecteur d'écart" --color "B60205" 2>/dev/null || true
}
assurer_label

# Commentaires conclusifs antérieurs (« Tout à jour… ») : les invalider
# (minimize OUTDATED) pour qu'une notification ne les fasse plus lire en premier.
invalider_commentaires_conclusifs() {
  local num="$1"
  local nodes nid body
  nodes=$(gh_issue api graphql -f query="
    query {
      repository(owner:\"Helveticleads\", name:\"Helveticleads-deploy\") {
        issue(number: $num) {
          comments(first: 50) {
            nodes { id body isMinimized }
          }
        }
      }
    }" --jq '.data.repository.issue.comments.nodes[] | select(.isMinimized==false) | select(.body|test("Tout à jour"; "i")) | .id' 2>/dev/null || true)
  for nid in $nodes; do
    [ -n "$nid" ] || continue
    gh_issue api graphql -f query="
      mutation {
        minimizeComment(input: {subjectId: \"$nid\", classifier: OUTDATED}) {
          minimizedComment { isMinimized }
        }
      }" >/dev/null 2>&1 || log "WARN minimizeComment échoué pour $nid"
    log "Commentaire conclusif invalidé (OUTDATED): $nid"
  done
}

# Quand on ne peut pas conclure : invalider les vieux « Tout à jour » et
# poster un commentaire de vérité pour qu'il soit le plus récent.
annoncer_non_conclusif() {
  local num="$1"
  local msg
  invalider_commentaires_conclusifs "$num"
  case "$verdict" in
    cible)
      msg="**Passage non conclusif** (ciblé : \`$cible_label\`). N/pop=$N_mesures/$n_population. Aucune conclusion flotte — lire le corps de l'issue."
      ;;
    auth)
      msg="**Passage non conclusif** — échec d'authentification. N/pop=$N_mesures/$n_population, Y=$n_non_mesure. Issue ouverte. Lire le corps."
      ;;
    incomplet)
      msg="**Passage non conclusif** — N < population ($N_mesures/$n_population). Aucun « tout à jour ». Issue ouverte. Lire le corps."
      ;;
    non_mesure)
      msg="**Passage non conclusif** — Y=$n_non_mesure non mesuré(s), N/pop=$N_mesures/$n_population. Issue ouverte. Lire le corps."
      ;;
    retard)
      msg="**Passage non conclusif** — $n_en_retard en retard, N/pop=$N_mesures/$n_population. Issue ouverte. Lire le corps."
      ;;
    injoignable)
      msg="**Passage non conclusif** — $n_injoignable INJOIGNABLE (2 passages), N/pop=$N_mesures/$n_population. Issue ouverte. Lire le corps."
      ;;
    brouillon_dormant)
      msg="**Passage non conclusif** — $n_brouillon_dormant brouillon(s) dormant(s), N/pop=$N_mesures/$n_population. Issue ouverte. Lire le corps."
      ;;
    suivi_empreinte)
      msg="**Passage non conclusif** — $n_suivi site(s) en SUIVI PAR EMPREINTE (pas de date vs main), N/pop=$N_mesures/$n_population. Issue ouverte. Lire le corps."
      ;;
    *)
      msg="**Passage non conclusif** — verdict=$verdict, N/pop=$N_mesures/$n_population, Y=$n_non_mesure. Issue ouverte. Lire le corps."
      ;;
  esac
  gh_issue issue comment "$num" -R "$REPO_DEPLOY" --body "$msg" >/dev/null
  log "Commentaire non conclusif posté sur #$num"
}

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
    NUM=$(printf '%s' "$URL" | grep -oE '[0-9]+$')
    annoncer_non_conclusif "$NUM"
    log "Issue créée (ouverte, passage ciblé sans conclusion) : $URL"
  else
    NUM=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["number"])')
    STATE=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["state"])')
    URL=$(printf '%s' "$EXISTING" | python3 -c 'import sys,json; print(json.load(sys.stdin)["url"])')
    upsert_body "$NUM"
    if [ "$STATE" = "CLOSED" ]; then
      gh_issue issue reopen "$NUM" -R "$REPO_DEPLOY"
      log "Issue rouverte (passage ciblé) : $URL"
    fi
    annoncer_non_conclusif "$NUM"
    log "Issue mise à jour (ouverte, passage ciblé, pas de conclusion) : $URL"
  fi
  echo "$URL" > "$RESULT_DIR/issue-url.txt"
  echo "$M_declares" > "$RESULT_DIR/M_declares.txt"
  log "DONE issue=$URL N/pop=$N_mesures/$n_population verdict=cible peut_fermer=0"
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
      --comment "Tout à jour — N/pop=$N_mesures/$n_population, aucun EN_RETARD / INJOIGNABLE / BROUILLON_DORMANT."
    log "Issue créée puis fermée : $URL"
  else
    annoncer_non_conclusif "$NUM"
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
        --comment "Tout à jour — N/pop=$N_mesures/$n_population, aucun EN_RETARD / INJOIGNABLE / BROUILLON_DORMANT."
      log "Issue mise à jour et fermée : $URL"
    else
      log "Issue déjà fermée, corps mis à jour : $URL"
    fi
  else
    # Retard, injoignable, dormant, ou auth : DOIT rester / être ouverte.
    if [ "$STATE" = "CLOSED" ]; then
      gh_issue issue reopen "$NUM" -R "$REPO_DEPLOY"
      log "Issue rouverte : $URL"
    fi
    annoncer_non_conclusif "$NUM"
    log "Issue mise à jour (ouverte, verdict=$verdict) : $URL"
  fi
fi

echo "$URL" > "$RESULT_DIR/issue-url.txt"
echo "$M_declares" > "$RESULT_DIR/M_declares.txt"
log "DONE issue=$URL N/pop=$N_mesures/$n_population M=$M_declares Y=$n_non_mesure inj=$n_injoignable dorm=$n_brouillon_dormant verdict=$verdict peut_fermer=$peut_fermer auth=${AUTH_FAIL:-ok}"
