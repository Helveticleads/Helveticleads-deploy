#!/usr/bin/env bash
# Quatre cas pour ops/garde-sitemap/mesurer-effet.mjs
# 1 plomberie (socle) OK — 2 punaise (autre producteur) OK — 3 vide FAIL — 4 divergent FAIL
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT="$ROOT/ops/garde-sitemap/mesurer-effet.mjs"
OUT="${GARDE_PREUVES_OUT:-${TMPDIR:-/tmp}/garde-sitemap-preuves-$$}"
mkdir -p "$OUT"
RESULTS="$OUT/verdicts.tsv"
: >"$RESULTS"

ok=0
ko=0
report() {
  local cas="$1" attendu="$2" obtenu="$3"
  printf '%s\t%s\t%s\n' "$cas" "$attendu" "$obtenu" >>"$RESULTS"
  if [ "$attendu" = "$obtenu" ]; then
    echo "CAS $cas attendu=$attendu obtenu=$obtenu OK"
    ok=$((ok + 1))
  else
    echo "CAS $cas attendu=$attendu obtenu=$obtenu FAIL"
    ko=$((ko + 1))
  fi
}

run_cas() {
  local dir="$1"
  set +e
  node "$SCRIPT" "$dir" >"$OUT/last.out" 2>"$OUT/last.err"
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then echo OK; else echo FAIL; fi
}

# --- Cas 3 : sitemap vide ---
V="$OUT/cas-vide/dist/public"
mkdir -p "$V"
printf '%s\n' '<!doctype html><html><head><title>x</title></head><body>x</body></html>' >"$V/index.html"
printf '%s\n' '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"></urlset>' >"$V/sitemap.xml"
r3=$(run_cas "$V")
report "sitemap-vide" "FAIL" "$r3"

# --- Cas 4 : sitemap divergent du prérendu ---
D="$OUT/cas-divergent/dist/public"
mkdir -p "$D/a" "$D/b"
printf '%s\n' '<!doctype html><html><head><title>a</title></head><body>a</body></html>' >"$D/a/index.html"
printf '%s\n' '<!doctype html><html><head><title>b</title></head><body>b</body></html>' >"$D/b/index.html"
printf '%s\n' '<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://example.test/a/</loc></url>
  <url><loc>https://example.test/seulement-sitemap/</loc></url>
</urlset>' >"$D/sitemap.xml"
r4=$(run_cas "$D")
report "sitemap-divergent" "FAIL" "$r4"

# --- Cas 1 : plomberie (socle) — dist servi (build local peut échouer hors CI) ---
SRC1="${GARDE_PREUVE_PLOMBERIE_DIST:-}"
if [ -z "$SRC1" ]; then
  SRC1="$OUT/plomberie-dist"
  mkdir -p "$SRC1"
  if [ -n "${GARDE_PREUVE_PLOMBERIE_RSYNC:-}" ]; then
    rsync -a --delete "$GARDE_PREUVE_PLOMBERIE_RSYNC" "$SRC1/"
  elif [ -d /tmp/preuve-plomberie-dist ] && [ -f /tmp/preuve-plomberie-dist/sitemap.xml ]; then
    rsync -a --delete /tmp/preuve-plomberie-dist/ "$SRC1/"
  else
    echo "CAS plomberie-socle : dist manquant (GARDE_PREUVE_PLOMBERIE_DIST ou /tmp/preuve-plomberie-dist)" >&2
    report "plomberie-socle" "OK" "ABSENT"
    SRC1=""
  fi
fi
if [ -n "$SRC1" ]; then
  r1=$(run_cas "$SRC1")
  report "plomberie-socle" "OK" "$r1"
fi

# --- Cas 2 : punaise (autre producteur) — build réel ---
SRC2="${GARDE_PREUVE_PUNAISE_DIST:-}"
if [ -z "$SRC2" ]; then
  if [ -d /tmp/preuve-punaise/artifacts/helvetique-punaise-de-lit/dist/public ]; then
    SRC2=/tmp/preuve-punaise/artifacts/helvetique-punaise-de-lit/dist/public
  else
    P2="$OUT/punaise"
    gh repo clone Helveticleads/FR-helvetique-punaise-de-lit.ch "$P2" -- --branch main
    (
      cd "$P2"
      corepack enable >/dev/null 2>&1 || true
      pnpm config set dangerouslyAllowAllBuilds true >/dev/null 2>&1 || true
      pnpm install --frozen-lockfile
      PORT=10000 BASE_PATH=/ DOMAIN= pnpm --filter @workspace/helvetique-punaise-de-lit run build
    )
    SRC2="$P2/artifacts/helvetique-punaise-de-lit/dist/public"
  fi
fi
r2=$(run_cas "$SRC2")
report "punaise-autre-producteur" "OK" "$r2"

echo "----"
echo "verdicts:"
column -t -s$'\t' "$RESULTS" 2>/dev/null || cat "$RESULTS"
echo "total ok=$ok ko=$ko"
[ "$ko" -eq 0 ] && [ "$ok" -eq 4 ]
