#!/usr/bin/env bash
# Prise du verrou par hôte — s'exécute SUR la machine cible (ou en local avec LOCK_DIR).
#
# Mécanisme : mkdir atomique. Sur un FS Linux, mkdir échoue si le répertoire
# existe déjà → une seule prise gagne. Pas de « test puis create ».
#
# Variables :
#   LOCK_DIR     chemin du verrou (défaut : $HOME/.helveticleads-deploy-lock)
#   LOCK_OWNER   identité du run (ex. Helveticleads/site@123456)
#   LOCK_RUN_URL URL Actions (optionnel)
#   STALE_SEC    âge max avant reprise (défaut 1500 = 25 min)
#   WAIT_MAX_SEC attente max (défaut 2700 = 45 min)
#   WAIT_POLL_SEC intervalle de poll (défaut 15)
#   VERROU_DISABLED=1  neutralise (preuve grade 2) — ne prend rien
set -euo pipefail

LOCK_DIR="${LOCK_DIR:-$HOME/.helveticleads-deploy-lock}"
LOCK_OWNER="${LOCK_OWNER:?LOCK_OWNER manquant}"
LOCK_RUN_URL="${LOCK_RUN_URL:-}"
STALE_SEC="${STALE_SEC:-1500}"
WAIT_MAX_SEC="${WAIT_MAX_SEC:-2700}"
WAIT_POLL_SEC="${WAIT_POLL_SEC:-15}"

log() { printf '%s\n' "$*" >&2; }

if [ "${VERROU_DISABLED:-0}" = "1" ]; then
  log "VERROU_DISABLED=1 — prise ignorée (mode preuve / neutralisation)"
  echo "LOCK_HELD=0"
  exit 0
fi

now_epoch() { date -u +%s; }
now_iso() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

read_owner() { cat "$LOCK_DIR/owner" 2>/dev/null || echo "?"; }
read_taken() { cat "$LOCK_DIR/taken_at" 2>/dev/null || echo "?"; }
read_taken_epoch() {
  local iso
  iso=$(read_taken)
  date -u -d "$iso" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null || echo 0
}

write_meta() {
  printf '%s\n' "$LOCK_OWNER" > "$LOCK_DIR/owner"
  printf '%s\n' "$(now_iso)" > "$LOCK_DIR/taken_at"
  if [ -n "$LOCK_RUN_URL" ]; then
    printf '%s\n' "$LOCK_RUN_URL" > "$LOCK_DIR/run_url"
  fi
}

try_acquire() {
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    write_meta
    log "LOCK_ACQUIRED owner=$LOCK_OWNER taken_at=$(read_taken) dir=$LOCK_DIR"
    echo "LOCK_HELD=1"
    return 0
  fi
  return 1
}

reclaim_if_stale() {
  local taken age owner
  taken=$(read_taken_epoch)
  if [ "$taken" = "0" ]; then
    return 1
  fi
  age=$(( $(now_epoch) - taken ))
  if [ "$age" -le "$STALE_SEC" ]; then
    return 1
  fi
  owner=$(read_owner)
  log "LOCK_STALE_RECLAIM owner=$owner taken_at=$(read_taken) age_sec=$age stale_sec=$STALE_SEC — reprise bruyante"
  rm -rf "$LOCK_DIR"
  return 0
}

deadline=$(( $(now_epoch) + WAIT_MAX_SEC ))
first=1
while true; do
  if try_acquire; then
    exit 0
  fi
  owner=$(read_owner)
  taken=$(read_taken)
  if reclaim_if_stale; then
    if try_acquire; then
      exit 0
    fi
  fi
  now=$(now_epoch)
  if [ "$now" -ge "$deadline" ]; then
    log "LOCK_TIMEOUT holder=$owner since=$taken wait_max_sec=$WAIT_MAX_SEC — pas de déploiement"
    echo "LOCK_HELD=0"
    exit 1
  fi
  if [ "$first" = "1" ]; then
    log "LOCK_WAIT holder=$owner since=$taken poll=${WAIT_POLL_SEC}s max=${WAIT_MAX_SEC}s"
    first=0
  else
    log "LOCK_WAIT_STILL holder=$owner since=$taken remaining_sec=$((deadline - now))"
  fi
  sleep "$WAIT_POLL_SEC"
done
