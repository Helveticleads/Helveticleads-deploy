#!/usr/bin/env bash
# Cas pour mesurer-rendu.mjs — seuil textLen≥200 ET elements≥20.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/ops/mesure-rendu/mesurer-rendu.mjs"
OUT="${MESURE_RENDU_PREUVES_OUT:-${TMPDIR:-/tmp}/mesure-rendu-preuves-$$}"
mkdir -p "$OUT"
ok=0; ko=0
report() {
  local cas="$1" attendu="$2" obtenu="$3"
  if [ "$attendu" = "$obtenu" ]; then echo "CAS $cas attendu=$attendu obtenu=$obtenu OK"; ok=$((ok+1))
  else echo "CAS $cas attendu=$attendu obtenu=$obtenu FAIL"; ko=$((ko+1)); fi
}
run() {
  set +e; node "$SCRIPT" "$1" >"$OUT/last.out" 2>"$OUT/last.err"; local rc=$?; set -e
  if [ "$rc" -eq 0 ]; then echo OK; else echo FAIL; fi
}

# casse : #root vide (passerait l'ancien témoin)
C="$OUT/casse.html"
printf '%s\n' '<!doctype html><html><head><title>x</title></head><body><div id="root"></div></body></html>' >"$C"
report "root-vide" "FAIL" "$(run "$C")"

# squelette sans contenu (ET attrape)
S="$OUT/squelette.html"
printf '%s\n' '<!doctype html><html><head><title>x</title></head><body>
<header><nav><a>a</a><a>b</a><a>c</a></nav></header>
<main></main>
<footer><p>f</p><p>g</p></footer>
</body></html>' >"$S"
report "squelette-sans-corps" "FAIL" "$(run "$S")"

# page saine minimale (au-dessus du seuil)
G="$OUT/saine.html"
{
  printf '%s\n' '<!doctype html><html><head><title>ok</title></head><body><main>'
  for i in $(seq 1 30); do printf '<p>Paragraphe de contenu rédigé numéro %s pour dépasser le seuil de deux cents caractères de texte visible.</p>\n' "$i"; done
  printf '%s\n' '</main></body></html>'
} >"$G"
report "page-saine-construite" "OK" "$(run "$G")"

# page réelle du parc si dispo
if curl -fsS --max-time 20 -o "$OUT/plomberie.html" "https://helvetique-plomberie.ch/" 2>/dev/null; then
  report "vite-plomberie-servi" "OK" "$(run "$OUT/plomberie.html")"
else
  report "vite-plomberie-servi" "OK" "ABSENT"
fi

echo "total ok=$ok ko=$ko"
[ "$ko" -eq 0 ]
