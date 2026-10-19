#!/usr/bin/env bash
# Pose releases/placeholder + current pour un hôte neuf.
# Refuse d'écraser un current qui résout déjà (leçon rongeurs 2026-10-17).
#
# Usage (root ou deploy, sur l'hôte) :
#   DOMAIN=helvetique-exemple.ch bash poser-placeholder.sh
set -euo pipefail

DOMAIN="${DOMAIN:?DOMAIN manquant}"
BASE="/var/www/$DOMAIN"

mkdir -p "$BASE/releases"

if [ -L "$BASE/current" ] || [ -e "$BASE/current" ]; then
  PREV="$(readlink "$BASE/current" 2>/dev/null || true)"
  if [ -n "$PREV" ] && [ -d "$PREV" ]; then
    echo "REFUS provision: current résout déjà vers $PREV — pas d'écrasement par placeholder" >&2
    exit 1
  fi
  if [ -e "$BASE/current" ] && [ ! -L "$BASE/current" ]; then
    echo "REFUS provision: $BASE/current existe et n'est pas un lien — intervention manuelle" >&2
    exit 1
  fi
fi

mkdir -p "$BASE/releases/placeholder"
# Bascule atomique uniquement si current absent ou lien cassé (cible absente).
ln -sfn "$BASE/releases/placeholder" "$BASE/.current.tmp"
mv -Tf "$BASE/.current.tmp" "$BASE/current"
chown -R deploy:deploy "$BASE" 2>/dev/null || true
echo "OK placeholder: current → $BASE/releases/placeholder"
