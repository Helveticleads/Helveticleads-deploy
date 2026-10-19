#!/usr/bin/env bash
# Couples du filtre d'actifs. Le cas /_astro/ est l'angle mort de la
# regex /assets/ : zéro correspondance, donc l'ancien appelant écrivait
# GATE_OK sans ouvrir le fichier. Le filtre nommé refuse ce OK.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$ROOT/classer-refs.sh"
OUT="${GARDE_ASSETS_PREUVES_OUT:-${TMPDIR:-/tmp}/garde-assets-preuves-$$}"
mkdir -p "$OUT"
ok=0; ko=0
report() {
  local cas="$1" attendu="$2" obtenu="$3"
  if [ "$attendu" = "$obtenu" ]; then echo "CAS $cas attendu=$attendu obtenu=$obtenu OK"; ok=$((ok+1))
  else echo "CAS $cas attendu=$attendu obtenu=$obtenu FAIL"; ko=$((ko+1)); fi
}
run() {
  set +e
  local tok
  tok=$("$SCRIPT" "$@")
  local rc=$?
  set -e
  printf '%s\n' "$tok"
  echo "$rc" >"$OUT/last.rc"
}

# Couple qui bascule : même préfixe /assets/, fichier absent vs présent.
D1="$OUT/manquant"
rm -rf "$D1"; mkdir -p "$D1"
printf '%s\n' '<script src="/assets/missing.js"></script>' >"$D1/index.html"
tok=$(run --local "$D1/index.html" "$D1")
report "assets-fichier-absent" "GATE_FAIL build:asset_manquant_ou_vide:/assets/missing.js" "$tok"

D2="$OUT/present"
rm -rf "$D2"; mkdir -p "$D2/assets"
printf 'x' >"$D2/assets/app.js"
printf '%s\n' '<script src="/assets/app.js"></script>' >"$D2/index.html"
tok=$(run --local "$D2/index.html" "$D2")
report "assets-fichier-present" "GATE_OK assets:prefixe_assets n=1" "$tok"

# Angle mort : /_astro/y.js référencé, fichier absent.
# La regex livrée /assets/ ne voit rien (0). L'appelant historique
# tombait alors sur GATE_OK. Le filtre écrit GATE_SKIP.
D3="$OUT/astro-absent"
rm -rf "$D3"; mkdir -p "$D3"
printf '%s\n' '<script src="/_astro/y.js"></script>' >"$D3/index.html"
n=$(grep -oE '/assets/[A-Za-z0-9._-]+\.(js|css)' "$D3/index.html" | wc -l | tr -d ' ' || true)
[ -n "$n" ] || n=0
report "astro-regex-assets-voit" "0" "$n"
tok=$(run --local "$D3/index.html" "$D3")
report "astro-fichier-absent" "GATE_SKIP assets:arbre_non_couvert:/_astro/" "$tok"

# Jumeau : le fichier /_astro/ existe. Le SKIP ne bascule pas — la garde
# déclare qu'elle ne s'applique pas, elle n'a pas ouvert le fichier.
D4="$OUT/astro-present"
rm -rf "$D4"; mkdir -p "$D4/_astro"
printf 'x' >"$D4/_astro/y.js"
printf '%s\n' '<script src="/_astro/y.js"></script>' >"$D4/index.html"
tok=$(run --local "$D4/index.html" "$D4")
report "astro-fichier-present" "GATE_SKIP assets:arbre_non_couvert:/_astro/" "$tok"

# Ensemble vide mesuré (aucune référence) reste un OK : on a regardé.
D5="$OUT/vide"
rm -rf "$D5"; mkdir -p "$D5"
printf '%s\n' '<html><body>texte</body></html>' >"$D5/index.html"
tok=$(run --local "$D5/index.html" "$D5")
report "aucune-reference" "GATE_OK assets:aucune_reference" "$tok"

echo "total ok=$ok ko=$ko"
[ "$ko" -eq 0 ]
