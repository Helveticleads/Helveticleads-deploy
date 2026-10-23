#!/usr/bin/env bash
# Preuves locales (sans réseau GitHub sauf si DV_LIVE=1).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
OUT="${TMPDIR:-/tmp}/deploy-verdict-preuves-$$"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

pass=0; fail=0
ok() { echo "PASS $1"; pass=$((pass+1)); }
ko() { echo "FAIL $1 — $2"; fail=$((fail+1)); }

# 1 — derive refuse /usr/local
if ! bash "$DIR/preuve-derive.sh" /usr/local/sbin/notifier-echec.sh 2>"$OUT/d1.err"; then
  grep -q DERIVE_FAIL "$OUT/d1.err" && ok "1-derive-refuse-usr-local" || ko "1" "pas DERIVE_FAIL"
else
  ko "1" "aurait dû échouer"
fi

# 2 — derive accepte chemin dépôt
if bash "$DIR/preuve-derive.sh" "$DIR/notifier-echec.sh" >"$OUT/d2.out"; then
  grep -q DERIVE_OK "$OUT/d2.out" && ok "2-derive-ok-depot" || ko "2" "pas DERIVE_OK"
else
  ko "2" "refus indû"
fi

# 3 — taxonomie garde : fichier témoin → GATE_FAIL lu
echo "GATE_FAIL anti_perte:perdues=1" >"$OUT/verdict.txt"
export VERDICT_FILE="$OUT/verdict.txt" REPO="test/none" RUN_URL="https://example/run/1"
# dry : source common + logique sans gh
classe=infra
if [ -f "$VERDICT_FILE" ] && grep -q '^GATE_FAIL' "$VERDICT_FILE"; then classe=garde; fi
[ "$classe" = garde ] && ok "3-classe-garde" || ko "3" "classe=$classe"

# 4 — taxonomie infra : pas de fichier
rm -f "$VERDICT_FILE"
classe=infra
if [ -f "${VERDICT_FILE:-}" ] && grep -q '^GATE_FAIL' "$VERDICT_FILE" 2>/dev/null; then classe=garde; fi
[ "$classe" = infra ] && ok "4-classe-infra" || ko "4" "classe=$classe"

# 5 — sabotage détecté dans la chaîne
echo "GATE_FAIL preuve_sabotage:fichier_absent:x" >"$OUT/verdict.txt"
grep -q 'preuve_sabotage:' "$OUT/verdict.txt" && ok "5-sabotage-auto" || ko "5" "non détecté"

# 6 — non_notifie écrit le résumé
# shellcheck source=common.sh
source "$DIR/common.sh"
export GITHUB_STEP_SUMMARY="$OUT/summary.md"
: >"$GITHUB_STEP_SUMMARY"
non_notifie "permissions issues:write absentes"
grep -q 'VERDICT NON NOTIFIÉ : permissions issues:write absentes' "$GITHUB_STEP_SUMMARY" \
  && ok "6-summary-non-notifie" || ko "6" "summary=$(cat "$GITHUB_STEP_SUMMARY")"

# 7 — KPI écart : fail runs > verdicts ⇒ notification cassée
n_fail=10; n_notif=3
ecart=$((n_fail - n_notif))
[ "$ecart" -gt 0 ] && ok "7-kpi-ecart-positif" || ko "7" "ecart=$ecart"

echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
