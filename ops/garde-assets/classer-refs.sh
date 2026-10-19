#!/usr/bin/env bash
# Filtre des références d'actifs dans index.html.
#
# Préfixe couvert : /assets/*.js|css (fichier non vide si --local).
# Préfixe /_astro/ : non couvert. Une référence /_astro/ sans aucune
# référence /assets/ n'est pas un GATE_OK — rien n'a été ouvert.
#   GATE_SKIP assets:arbre_non_couvert:/_astro/
#
# Usage:
#   classer-refs.sh --local <index.html> <racine>   # test -s sur /assets/
#   classer-refs.sh --prefixe <index.html>          # sans lecture des fichiers
# Exit 0 = OK ou SKIP, 1 = FAIL, 2 = usage.
set -euo pipefail

mode="${1:-}"
index="${2:-}"
root="${3:-}"
if [ "$mode" != "--local" ] && [ "$mode" != "--prefixe" ]; then
  echo "usage: classer-refs.sh --local <index.html> <racine> | --prefixe <index.html>" >&2
  exit 2
fi
if [ ! -f "$index" ]; then
  echo "GATE_FAIL assets:index_absent" >&2
  exit 1
fi
if [ "$mode" = "--local" ] && [ -z "$root" ]; then
  echo "usage: classer-refs.sh --local <index.html> <racine>" >&2
  exit 2
fi

pat_assets='/assets/[A-Za-z0-9._-]+\.(js|css)'
pat_astro='/_astro/[A-Za-z0-9._-]+\.(js|css)'

assets=$(grep -oE "$pat_assets" "$index" | sort -u || true)
astro=$(grep -oE "$pat_astro" "$index" | sort -u || true)

if [ -n "$assets" ]; then
  if [ "$mode" = "--local" ]; then
    while IFS= read -r r; do
      [ -n "$r" ] || continue
      if [ ! -s "$root$r" ]; then
        echo "GATE_FAIL build:asset_manquant_ou_vide:$r"
        exit 1
      fi
    done <<<"$assets"
  fi
  n=$(printf '%s\n' "$assets" | grep -c . || true)
  echo "GATE_OK assets:prefixe_assets n=$n"
  exit 0
fi

if [ -n "$astro" ]; then
  echo "GATE_SKIP assets:arbre_non_couvert:/_astro/"
  exit 0
fi

echo "GATE_OK assets:aucune_reference"
exit 0
