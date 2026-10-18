#!/usr/bin/env bash
# Épreuve à blanc de la garde noindex racine — trois cas, aucun rsync.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GARDE="$DIR/garde-noindex-racine.sh"
FIX="$DIR/fixtures/noindex"
OUT="${NOINDEX_PREUVE_OUT:-$DIR/../../.noindex-preuves}"
rm -rf "$OUT"
mkdir -p "$OUT"
chmod +x "$GARDE"

pass=0
fail=0
ok() { pass=$((pass + 1)); echo "PASS [$1] $2"; }
ko() { fail=$((fail + 1)); echo "FAIL [$1] $2"; exit 1; }

# --- Cas 1 : racine porte noindex → REFUS + motif ---
cas_1_racine_noindex() {
  local src="$OUT/cas1" rc=0 msg
  rm -rf "$src"
  mkdir -p "$src"
  cp "$FIX/racine-noindex/index.html" "$src/index.html"
  set +e
  msg=$("$GARDE" "$src" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$msg" | tee "$OUT/cas1.out"
  [ "$rc" -ne 0 ] || ko 1 "attendu refus, exit 0"
  printf '%s' "$msg" | grep -q 'GATE_FAIL build:noindex_racine:' || ko 1 "pas de GATE_FAIL noindex_racine"
  printf '%s' "$msg" | grep -q 'meta_robots_noindex' || ko 1 "motif meta_robots_noindex absent"
  printf '%s' "$msg" | grep -q "fichier=${src}/index.html" || ko 1 "emplacement fichier absent"
  printf '%s' "$msg" | grep -q 'ligne=' || ko 1 "numéro de ligne absent"
  ok 1 "racine noindex → refus avec motif"
  echo "REFUS_AFFICHE<<EOF"
  printf '%s\n' "$msg"
  echo "EOF"
}

# --- Cas 2 : racine sans noindex → PASS ---
cas_2_racine_propre() {
  local src="$OUT/cas2" rc=0 msg
  rm -rf "$src"
  mkdir -p "$src"
  cp "$FIX/racine-propre/index.html" "$src/index.html"
  set +e
  msg=$("$GARDE" "$src" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$msg" | tee "$OUT/cas2.out"
  [ "$rc" -eq 0 ] || ko 2 "attendu pass, exit $rc msg=$msg"
  printf '%s' "$msg" | grep -q 'GATE_OK build:noindex_racine:' || ko 2 "pas de GATE_OK"
  ok 2 "racine propre → pass"
}

# --- Cas 3 : seule une page interne porte noindex → PASS (cas qui compte) ---
cas_3_interne_seulement() {
  local src="$OUT/cas3" rc=0 msg
  rm -rf "$src"
  mkdir -p "$src/merci"
  cp "$FIX/interne-noindex/index.html" "$src/index.html"
  cp "$FIX/interne-noindex/merci/index.html" "$src/merci/index.html"
  set +e
  msg=$("$GARDE" "$src" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "$msg" | tee "$OUT/cas3.out"
  [ "$rc" -eq 0 ] || ko 3 "page interne noindex a refusé à tort: $msg"
  printf '%s' "$msg" | grep -q 'GATE_OK build:noindex_racine:' || ko 3 "pas de GATE_OK"
  # La page interne porte bien noindex (contrôle de la fixture).
  grep -qi 'noindex' "$src/merci/index.html" || ko 3 "fixture interne sans noindex"
  ok 3 "interne noindex seule → pass (racine propre)"
}

cas_1_racine_noindex
cas_2_racine_propre
cas_3_interne_seulement

echo
echo "PREUVES_NOINDEX pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
