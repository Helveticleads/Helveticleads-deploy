#!/usr/bin/env bash
# Adaptateur local : lit BASE=, appelle decider.sh.
# Usage : BASE=/var/www/exemple.ch bash classer-etat.sh
set -euo pipefail

BASE="${BASE:?BASE manquant}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

PREV="$(readlink "$BASE/current" 2>/dev/null || true)"
echo "PREV=$PREV"

# Release complète = index.html non vide (pas un rsync avorté ni un placeholder nu).
COMPLETE_RELEASE="$(find "$BASE/releases" -mindepth 2 -maxdepth 2 -name index.html -size +0 2>/dev/null | head -n1 || true)"

PREV_AVEC_PAGES=0
if [ -n "$PREV" ] && [ "$PREV" != "$BASE/current" ] && [ -d "$PREV" ]; then
  if find "$PREV" -maxdepth 2 -name index.html -size +0 2>/dev/null | grep -q .; then
    PREV_AVEC_PAGES=1
  fi
fi

export PREV PREV_AVEC_PAGES COMPLETE_RELEASE
# Propager le code de decider (0/1/2) — ne pas laisser set -e tuer sur exit 2.
rc=0
bash "$ROOT/decider.sh" || rc=$?
exit "$rc"
