#!/usr/bin/env bash
# Exécute une garde et exige une ligne GATE_OK|GATE_FAIL|GATE_SKIP.
# Absence de ligne → GATE_PANNE <nom>:pas_de_verdict (ni refus ni accord).
#
# Usage:
#   GARDE_NOM=garde-livraison bash exiger-verdict.sh -- node scripts/foo.mjs --deploiement
# Exit: 0 si GATE_OK/GATE_SKIP, 1 si GATE_FAIL, 2 si GATE_PANNE ou crash sans verdict.
set -euo pipefail

GARDE_NOM="${GARDE_NOM:?GARDE_NOM manquant}"

if [ "${1:-}" != "--" ]; then
  echo "usage: GARDE_NOM=… $0 -- <commande…>" >&2
  exit 2
fi
shift

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT

set +e
"$@" >"$OUT" 2>&1
rc=$?
set -e
cat "$OUT"

if grep -qE '^GATE_PANNE ' "$OUT"; then
  exit 2
fi
if grep -qE '^GATE_FAIL ' "$OUT"; then
  exit 1
fi
if grep -qE '^GATE_OK |^GATE_SKIP ' "$OUT"; then
  exit 0
fi

echo "GATE_PANNE ${GARDE_NOM}:pas_de_verdict rc=$rc"
exit 2
