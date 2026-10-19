#!/usr/bin/env bash
# Preuves : setext OK, conflit FAIL, ignore OK, trois absents OK
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/ops/garde-marqueurs-conflit/guard-marqueurs-conflit.mjs"
OUT="${GARDE_PREUVES_OUT:-${TMPDIR:-/tmp}/garde-marqueurs-preuves-$$}"
mkdir -p "$OUT"
ok=0; ko=0
report() {
  local cas="$1" attendu="$2" obtenu="$3"
  if [ "$attendu" = "$obtenu" ]; then echo "CAS $cas attendu=$attendu obtenu=$obtenu OK"; ok=$((ok+1))
  else echo "CAS $cas attendu=$attendu obtenu=$obtenu FAIL"; ko=$((ko+1)); fi
}
run() {
  local dir="$1"
  set +e
  node "$SCRIPT" "$dir" >/dev/null 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then echo OK; else echo FAIL; fi
}

S="$OUT/setext"; mkdir -p "$S"
printf '%s\n' 'Titre' '=======' 'Corps.' >"$S/a.md"
report setext-titre OK "$(run "$S")"

C="$OUT/conflit"; mkdir -p "$C"
printf '%s\n' 'x' '<<<<<<< HEAD' 'a' '=======' 'b' '>>>>>>> branch' >"$C/a.md"
report conflit-reel FAIL "$(run "$C")"

I="$OUT/ignore"; mkdir -p "$I"
printf '%s\n' '<!-- garde-marqueurs-ignore -->' '<<<<<<< HEAD' 'a' '=======' 'b' '>>>>>>> branch' >"$I/doc.md"
report doc-ignore OK "$(run "$I")"

P="$OUT/propre"; mkdir -p "$P"
printf '%s\n' 'pas de marqueurs' >"$P/a.md"
report propre OK "$(run "$P")"

echo "RESUME ok=$ok ko=$ko"
test "$ko" -eq 0
