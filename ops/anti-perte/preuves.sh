#!/usr/bin/env bash
# Suite permanente — arbres locaux, pas d'hôte.
# Échelle à 3 branches (voir decider.sh) + rollback.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLASSER="$ROOT/ops/anti-perte/classer-etat.sh"
ROLLBACK="$ROOT/ops/anti-perte/rollback.sh"
OUT="${ANTI_PERTE_PREUVES_OUT:-${TMPDIR:-/tmp}/anti-perte-preuves-$$}"
mkdir -p "$OUT"
RESULTS="$OUT/verdicts.tsv"
: >"$RESULTS"

ok=0
ko=0

report() {
  local cas="$1" attendu="$2" obtenu="$3" detail="${4:-}"
  printf '%s\t%s\t%s\t%s\n' "$cas" "$attendu" "$obtenu" "$detail" >>"$RESULTS"
  if [ "$attendu" = "$obtenu" ]; then
    echo "CAS $cas attendu=$attendu obtenu=$obtenu OK${detail:+ — $detail}"
    ok=$((ok + 1))
  else
    echo "CAS $cas attendu=$attendu obtenu=$obtenu FAIL${detail:+ — $detail}"
    ko=$((ko + 1))
  fi
}

run_classer() {
  local base="$1"
  set +e
  out=$(BASE="$base" bash "$CLASSER" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$out" >"$OUT/last.out"
  echo "$rc"
}

token_from_out() {
  if grep -q 'GATE_SKIP anti_perte:hote_provisionne' "$OUT/last.out"; then
    echo "GATE_SKIP anti_perte:hote_provisionne"
  elif grep -q 'GATE_SKIP anti_perte:premiere_release' "$OUT/last.out"; then
    echo "GATE_SKIP anti_perte:premiere_release"
  elif grep -q 'GATE_FAIL anti_perte:current_casse_sur_site_servi' "$OUT/last.out"; then
    echo "GATE_FAIL anti_perte:current_casse_sur_site_servi"
  elif grep -q 'ANTI_PERTE_ETAT=prev_valide' "$OUT/last.out"; then
    echo "PREV_VALIDE"
  else
    echo "INCONNU"
  fi
}

# --- Cas 1 : current absent, releases/ vide → premiere_release ---
B1="$OUT/cas1"
rm -rf "$B1"
mkdir -p "$B1/releases"
rc=$(run_classer "$B1")
tok=$(token_from_out)
report "current_absent_releases_vide" "GATE_SKIP anti_perte:premiere_release" "$tok" "rc=$rc"

# --- Cas 2 : current absent, release avec index.html → FAIL ---
B2="$OUT/cas2"
rm -rf "$B2"
mkdir -p "$B2/releases/20260101-120000"
printf '%s\n' '<html><body>ok</body></html>' >"$B2/releases/20260101-120000/index.html"
rc=$(run_classer "$B2")
tok=$(token_from_out)
report "current_absent_release_complete" "GATE_FAIL anti_perte:current_casse_sur_site_servi" "$tok" "rc=$rc"

# --- Cas 3 : current absent, release sans index.html → premiere_release ---
B3="$OUT/cas3"
rm -rf "$B3"
mkdir -p "$B3/releases/20260101-130000/assets"
printf '%s\n' 'partial' >"$B3/releases/20260101-130000/assets/x.js"
rc=$(run_classer "$B3")
tok=$(token_from_out)
report "current_absent_release_partielle" "GATE_SKIP anti_perte:premiere_release" "$tok" "rc=$rc"

# --- Cas 4 : current → vide, releases vides → hote_provisionne (plus un refus) ---
B4="$OUT/cas4"
rm -rf "$B4"
mkdir -p "$B4/releases"
ln -sfn "$B4/releases/disparue" "$B4/current"
rc=$(run_classer "$B4")
tok=$(token_from_out)
report "current_lien_casse_sans_pages" "GATE_SKIP anti_perte:hote_provisionne" "$tok" "rc=$rc"

# --- Cas 5 : rollback PREV vide → ROLLBACK_VERS_NEANT ---
B5="$OUT/cas5"
rm -rf "$B5"
mkdir -p "$B5/releases/20260101-140000"
printf '%s\n' '<html>new</html>' >"$B5/releases/20260101-140000/index.html"
ln -sfn "$B5/releases/20260101-140000" "$B5/current"
test -L "$B5/current"
set +e
bout=$(BASE="$B5" PREV= bash "$ROLLBACK" 2>&1)
brc=$?
set -e
printf '%s\n' "$bout" >"$OUT/rollback.out"
if echo "$bout" | grep -q 'ROLLBACK_VERS_NEANT' \
  && [ ! -e "$B5/current" ] && [ ! -L "$B5/current" ] \
  && [ "$brc" = "0" ]; then
  report "rollback_vers_neant" "ROLLBACK_VERS_NEANT current_retire" "ROLLBACK_VERS_NEANT current_retire" "lu: current absent"
else
  still="present"
  [ -e "$B5/current" ] || [ -L "$B5/current" ] || still="absent"
  report "rollback_vers_neant" "ROLLBACK_VERS_NEANT current_retire" "FAIL" "out=$(echo "$bout" | tr '\n' ' ') current=$still rc=$brc"
fi

# --- Cas 6 : placeholder seul (état des 3 hôtes neufs) → hote_provisionne ---
B6="$OUT/cas6"
rm -rf "$B6"
mkdir -p "$B6/releases/placeholder"
ln -sfn "$B6/releases/placeholder" "$B6/current"
rc=$(run_classer "$B6")
tok=$(token_from_out)
report "placeholder_seul" "GATE_SKIP anti_perte:hote_provisionne" "$tok" "rc=$rc"

# --- Cas 7 : placeholder + release pleine ailleurs → FAIL (anti-échappatoire) ---
B7="$OUT/cas7"
rm -rf "$B7"
mkdir -p "$B7/releases/placeholder" "$B7/releases/20260101-150000"
printf '%s\n' '<html><body>plein</body></html>' >"$B7/releases/20260101-150000/index.html"
ln -sfn "$B7/releases/placeholder" "$B7/current"
rc=$(run_classer "$B7")
tok=$(token_from_out)
report "placeholder_plus_release_pleine" "GATE_FAIL anti_perte:current_casse_sur_site_servi" "$tok" "rc=$rc"

# --- Cas 8 : PREV → release avec pages → prev_valide ---
B8="$OUT/cas8"
rm -rf "$B8"
mkdir -p "$B8/releases/20260101-160000"
printf '%s\n' '<html><body>servi</body></html>' >"$B8/releases/20260101-160000/index.html"
ln -sfn "$B8/releases/20260101-160000" "$B8/current"
rc=$(run_classer "$B8")
tok=$(token_from_out)
report "prev_avec_pages" "PREV_VALIDE" "$tok" "rc=$rc"

echo "----"
echo "verdicts:"
column -t -s$'\t' "$RESULTS" 2>/dev/null || cat "$RESULTS"
echo "total ok=$ok ko=$ko"
[ "$ko" -eq 0 ] && [ "$ok" -eq 8 ]
