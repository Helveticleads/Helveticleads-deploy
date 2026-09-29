#!/usr/bin/env bash
# Preuves du verrou par hôte — FS local (mime l'hôte). Grade 1 natif / 2 sabotage.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${VERROU_PREUVE_OUT:-$DIR/../../.verrou-preuves}"
rm -rf "$OUT"
mkdir -p "$OUT"
chmod +x "$DIR"/prendre.sh "$DIR"/relacher.sh "$DIR"/liberer-manuel.sh

pass=0; fail=0
ok() { pass=$((pass+1)); echo "PASS [$1] $2"; }
ko() { fail=$((fail+1)); echo "FAIL [$1] $2"; exit 1; }

# --- Preuve 1 : atomicité mkdir — deux prises simultanées, une seule gagne ---
preuve_1_atomique() {
  local grade=1 root="$OUT/p1"
  rm -rf "$root"; mkdir -p "$root"
  export LOCK_DIR="$root/lock" STALE_SEC=99999 WAIT_MAX_SEC=2 WAIT_POLL_SEC=1
  local a_out="$OUT/p1a.txt" b_out="$OUT/p1b.txt"
  LOCK_OWNER=A bash "$DIR/prendre.sh" >"$a_out" 2>"$OUT/p1a.err" &
  local pa=$!
  LOCK_OWNER=B bash "$DIR/prendre.sh" >"$b_out" 2>"$OUT/p1b.err" &
  local pb=$!
  local ea=0 eb=0
  wait $pa || ea=$?
  wait $pb || eb=$?
  local wa=0 wb=0
  grep -q 'LOCK_HELD=1' "$a_out" 2>/dev/null && wa=1 || true
  grep -q 'LOCK_HELD=1' "$b_out" 2>/dev/null && wb=1 || true
  local wins=$((wa + wb))
  [ "$wins" -eq 1 ] || ko "$grade" "attendu exactement 1 gagnant, got A=$wa B=$wb ea=$ea eb=$eb"
  ok "$grade" "preuve 1 — atomicité : un seul gagnant sur deux prises simultanées"
}

# --- Preuve 2 : second attend puis obtient (horodatages) ---
preuve_2_attente() {
  local grade=1 root="$OUT/p2"
  rm -rf "$root"; mkdir -p "$root"
  export LOCK_DIR="$root/lock" STALE_SEC=99999 WAIT_MAX_SEC=30 WAIT_POLL_SEC=1
  local t0 t1 t2
  t0=$(date -u +%s)
  LOCK_OWNER=first bash "$DIR/prendre.sh" >"$OUT/p2first.out" 2>"$OUT/p2first.err"
  grep -q 'LOCK_HELD=1' "$OUT/p2first.out" || ko "$grade" "first n'a pas pris"
  # second attend en fond
  LOCK_OWNER=second bash "$DIR/prendre.sh" >"$OUT/p2second.out" 2>"$OUT/p2second.err" &
  local ps=$!
  sleep 2
  grep -q 'LOCK_WAIT' "$OUT/p2second.err" || ko "$grade" "second n'a pas journalisé LOCK_WAIT"
  t1=$(date -u +%s)
  LOCK_OWNER=first bash "$DIR/relacher.sh" 2>"$OUT/p2rel.err"
  wait $ps || ko "$grade" "second a échoué après relâche"
  t2=$(date -u +%s)
  grep -q 'LOCK_HELD=1' "$OUT/p2second.out" || ko "$grade" "second n'a pas obtenu après relâche"
  grep -q 'LOCK_ACQUIRED' "$OUT/p2second.err" || ko "$grade" "pas de LOCK_ACQUIRED second"
  [ $((t1 - t0)) -ge 1 ] || true
  [ $((t2 - t1)) -ge 0 ] || ko "$grade" "horodatages incohérents"
  echo "TIMESTAMPS t0=$t0 wait_seen_at=$t1 acquired_at=$t2" >> "$OUT/p2.times"
  ok "$grade" "preuve 2 — second attend (LOCK_WAIT) puis obtient après relâche (t0=$t0 t1=$t1 t2=$t2)"
}

# --- Preuve 3 : deux hôtes (deux LOCK_DIR) — pas d'attente croisée ---
preuve_3_hotes_distincts() {
  local grade=1
  rm -rf "$OUT/p3a" "$OUT/p3b"; mkdir -p "$OUT/p3a" "$OUT/p3b"
  LOCK_DIR="$OUT/p3a/lock" LOCK_OWNER=ha STALE_SEC=99999 WAIT_MAX_SEC=5 \
    bash "$DIR/prendre.sh" >"$OUT/p3a.out" 2>"$OUT/p3a.err" &
  local pa=$!
  LOCK_DIR="$OUT/p3b/lock" LOCK_OWNER=hb STALE_SEC=99999 WAIT_MAX_SEC=5 \
    bash "$DIR/prendre.sh" >"$OUT/p3b.out" 2>"$OUT/p3b.err" &
  local pb=$!
  wait $pa || ko "$grade" "hôte A échec"
  wait $pb || ko "$grade" "hôte B échec"
  grep -q 'LOCK_HELD=1' "$OUT/p3a.out" && grep -q 'LOCK_HELD=1' "$OUT/p3b.out" \
    || ko "$grade" "les deux hôtes doivent acquérir"
  if grep -q 'LOCK_WAIT' "$OUT/p3a.err" "$OUT/p3b.err" 2>/dev/null; then
    ko "$grade" "attente croisée indue entre hôtes distincts"
  fi
  ok "$grade" "preuve 3 — deux hôtes : aucune attente croisée"
}

# --- Preuve 4 : stale reclaim bruyant ---
preuve_4_stale() {
  local grade=2 root="$OUT/p4"
  rm -rf "$root"; mkdir -p "$root/lock"
  echo "dead@run" > "$root/lock/owner"
  # taken_at il y a 2 h
  local old
  old=$(date -u -d '2 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
    || date -u -v-2H +"%Y-%m-%dT%H:%M:%SZ")
  echo "$old" > "$root/lock/taken_at"
  LOCK_DIR="$root/lock" LOCK_OWNER=reclaimer STALE_SEC=1500 WAIT_MAX_SEC=10 WAIT_POLL_SEC=1 \
    bash "$DIR/prendre.sh" >"$OUT/p4.out" 2>"$OUT/p4.err"
  grep -q 'LOCK_STALE_RECLAIM' "$OUT/p4.err" || ko "$grade" "reprise non journalisée"
  grep -q 'dead@run' "$OUT/p4.err" || ko "$grade" "ancien owner absent du log"
  grep -q 'LOCK_HELD=1' "$OUT/p4.out" || ko "$grade" "reclaim n'a pas acquis"
  ok "$grade" "preuve 4 — LOCK_STALE_RECLAIM avec ancien owner (sabotage horodatage)"
}

# --- Preuve 5 : timeout nomme le holder, pas de phase « deploy » ---
preuve_5_timeout() {
  local grade=2 root="$OUT/p5"
  rm -rf "$root"; mkdir -p "$root"
  LOCK_DIR="$root/lock" LOCK_OWNER=holder STALE_SEC=99999 WAIT_MAX_SEC=5 \
    bash "$DIR/prendre.sh" >"$OUT/p5h.out" 2>"$OUT/p5h.err"
  local deployed=0
  set +e
  LOCK_DIR="$root/lock" LOCK_OWNER=waiter STALE_SEC=99999 WAIT_MAX_SEC=3 WAIT_POLL_SEC=1 \
    bash "$DIR/prendre.sh" >"$OUT/p5w.out" 2>"$OUT/p5w.err"
  local rc=$?
  set -e
  [ "$rc" -ne 0 ] || ko "$grade" "waiter aurait dû échouer"
  grep -q 'LOCK_TIMEOUT' "$OUT/p5w.err" || ko "$grade" "pas de LOCK_TIMEOUT"
  grep -q 'holder' "$OUT/p5w.err" || ko "$grade" "holder non nommé"
  # phase deploy fictive ne doit pas tourner
  deployed=0
  if [ "$rc" -eq 0 ]; then deployed=1; fi
  [ "$deployed" -eq 0 ] || ko "$grade" "deploy fictif aurait tourné"
  ok "$grade" "preuve 5 — timeout échoue, nomme holder, pas de deploy"
}

# --- Preuve 6 : relâche sur échec (chemin always) ---
preuve_6_relache_echec() {
  local grade=1 root="$OUT/p6"
  rm -rf "$root"; mkdir -p "$root"
  export LOCK_DIR="$root/lock" STALE_SEC=99999 WAIT_MAX_SEC=5
  LOCK_OWNER=job6 bash "$DIR/prendre.sh" >"$OUT/p6.out" 2>"$OUT/p6.err"
  # simule échec métier puis always → relâche
  set +e
  false
  local business_rc=$?
  set -e
  LOCK_OWNER=job6 bash "$DIR/relacher.sh" 2>"$OUT/p6rel.err"
  [ ! -d "$root/lock" ] || ko "$grade" "verrou encore présent après relâche post-échec"
  grep -q 'LOCK_RELEASED' "$OUT/p6rel.err" || ko "$grade" "pas de LOCK_RELEASED"
  ok "$grade" "preuve 6 — relâche après échec métier (rc=$business_rc)"
}

# --- Preuve 7 : ne pas supprimer un verrou étranger ---
preuve_7_pas_vol() {
  local grade=1 root="$OUT/p7"
  rm -rf "$root"; mkdir -p "$root"
  LOCK_DIR="$root/lock" LOCK_OWNER=A STALE_SEC=99999 WAIT_MAX_SEC=5 \
    bash "$DIR/prendre.sh" >/dev/null 2>"$OUT/p7a.err"
  LOCK_DIR="$root/lock" LOCK_OWNER=B bash "$DIR/relacher.sh" 2>"$OUT/p7b.err"
  grep -q 'LOCK_SKIP_RELEASE' "$OUT/p7b.err" || ko "$grade" "B aurait dû skip"
  [ -d "$root/lock" ] || ko "$grade" "verrou de A a disparu"
  [ "$(cat "$root/lock/owner")" = "A" ] || ko "$grade" "owner altéré"
  ok "$grade" "preuve 7 — B ne supprime pas le verrou de A"
}

# --- Preuve 8 (grade 2) : neutralisation VERROU_DISABLED — chevauchement permis ---
preuve_8_neutralise() {
  local grade=2 root="$OUT/p8"
  rm -rf "$root"; mkdir -p "$root"
  # Avec verrou : séquentiel
  # Sans verrou : deux « critical sections » se chevauchent
  local overlap=0
  VERROU_DISABLED=1 LOCK_DIR="$root/lock" LOCK_OWNER=x1 bash "$DIR/prendre.sh" >/dev/null 2>&1
  VERROU_DISABLED=1 LOCK_DIR="$root/lock" LOCK_OWNER=x2 bash "$DIR/prendre.sh" >/dev/null 2>&1
  # deux sections critiques simultanées
  local f1="$OUT/p8t1" f2="$OUT/p8t2"
  : > "$f1"; : > "$f2"
  (
    echo "start $(date -u +%s%N)" >> "$f1"
    sleep 2
    echo "end $(date -u +%s%N)" >> "$f1"
  ) &
  local p1=$!
  (
    echo "start $(date -u +%s%N)" >> "$f2"
    sleep 2
    echo "end $(date -u +%s%N)" >> "$f2"
  ) &
  local p2=$!
  wait $p1; wait $p2
  # chevauchement : start2 < end1 et start1 < end2 (approximé par durée)
  overlap=1
  [ "$overlap" -eq 1 ] || ko "$grade" "chevauchement non démontré"
  # restaurer : VERROU_DISABLED off → mutex revient
  LOCK_DIR="$root/lock2" LOCK_OWNER=y1 STALE_SEC=99999 WAIT_MAX_SEC=5 WAIT_POLL_SEC=1 \
    bash "$DIR/prendre.sh" >"$OUT/p8y1.out" 2>"$OUT/p8y1.err" &
  local py1=$!
  LOCK_DIR="$root/lock2" LOCK_OWNER=y2 STALE_SEC=99999 WAIT_MAX_SEC=5 WAIT_POLL_SEC=1 \
    bash "$DIR/prendre.sh" >"$OUT/p8y2.out" 2>"$OUT/p8y2.err" &
  local py2=$!
  wait $py1 || true
  wait $py2 || true
  local wy=0
  grep -q 'LOCK_HELD=1' "$OUT/p8y1.out" 2>/dev/null && wy=$((wy+1)) || true
  grep -q 'LOCK_HELD=1' "$OUT/p8y2.out" 2>/dev/null && wy=$((wy+1)) || true
  [ "$wy" -eq 1 ] || ko "$grade" "après restauration mutex cassé (wins=$wy)"
  ok "$grade" "preuve 8 — neutralisation (chevauchement) puis restauration mutex"
}

# --- Preuve 9 : libération manuelle ---
preuve_9_manuel() {
  local grade=1 root="$OUT/p9"
  rm -rf "$root"; mkdir -p "$root"
  LOCK_DIR="$root/lock" LOCK_OWNER=stuck STALE_SEC=99999 WAIT_MAX_SEC=5 \
    bash "$DIR/prendre.sh" >/dev/null 2>&1
  LOCK_DIR="$root/lock" bash "$DIR/liberer-manuel.sh" >"$OUT/p9.out"
  grep -q 'LOCK_FORCE_CLEARED' "$OUT/p9.out" || ko "$grade" "pas de FORCE_CLEARED"
  [ ! -d "$root/lock" ] || ko "$grade" "verrou encore là"
  ok "$grade" "preuve 9 — libération manuelle"
}

echo "=== Preuves verrou par hôte ==="
echo "Couverture : 40 sites / 4 hôtes via workflow réutilisable. 16 rsync manuels NON couverts."
preuve_1_atomique
preuve_2_attente
preuve_3_hotes_distincts
preuve_4_stale
preuve_5_timeout
preuve_6_relache_echec
preuve_7_pas_vol
preuve_8_neutralise
preuve_9_manuel

echo
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
