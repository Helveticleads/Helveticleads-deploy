#!/usr/bin/env bash
# Orchestration bascule IONOS — exécutée depuis le Mac à 22:00 Europe/Zurich.
# À la première anomalie : rollback + exit ≠ 0. Pas de diagnostic prolongé.
set -euo pipefail

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$HOME/.local/bin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${IONOS_SSH_KEY:-$HOME/.ssh/id_ed25519_ionos}"
HOST="deploy@212.227.76.165"
API="/opt/helvetic-api/app/artifacts/api-server"
UNIT="helvetic-api.service"
SYSTEMCTL="/usr/bin/systemctl"
REPORT="${ROOT}/BASCULE-IONOS-REPORT-$(date +%Y%m%d).txt"
LOCAL_DIST="$ROOT/dist"

TZ_ZONE="Europe/Zurich"
TARGET_H=22
TARGET_M=0

log() { echo "[$(TZ=$TZ_ZONE date +%H:%M:%S)] $*"; }
fail() { log "FAIL: $*"; echo "FAIL: $*" >>"$REPORT"; exit 1; }

ssh_r() {
  ssh -i "$KEY" -o BatchMode=yes -o ConnectTimeout=20 -o IdentitiesOnly=yes "$HOST" "$@"
}

# --- wait until 22:00 Europe/Zurich ---
wait_window() {
  python3 - <<'PY'
import time
from datetime import datetime
from zoneinfo import ZoneInfo
tz = ZoneInfo("Europe/Zurich")
while True:
    now = datetime.now(tz)
    target = now.replace(hour=22, minute=0, second=0, microsecond=0)
    if now >= target:
        print(now.isoformat())
        break
    left = (target - now).total_seconds()
    print(f"waiting {int(left)}s until {target.isoformat()}", flush=True)
    time.sleep(min(left, 120))
PY
}

{
  echo "BASCULE IONOS REPORT"
  echo "===================="
} >"$REPORT"

if [ "${SKIP_WAIT:-0}" = "1" ]; then
  log "SKIP_WAIT=1 — starting immediately (scheduled job)"
else
  log "Waiting for 22:00 Europe/Zurich..."
  wait_window | tee -a "$REPORT"
fi
BEGIN="$(TZ=$TZ_ZONE date -Iseconds)"
log "BEGIN=$BEGIN"
echo "BEGIN=$BEGIN" >>"$REPORT"

# Rebuild fresh
log "Local build"
(cd "$ROOT" && npm run build) >>"$REPORT" 2>&1
test -s "$LOCAL_DIST/index.mjs" || fail "local dist missing"

# Preflight rights — HOST_PROFILE via EnvironmentFile hors api.env + drop-in systemd.
# Ne jamais lire ni écrire /etc/helvetic/api.env.
log "Preflight"
PRE=$(ssh_r 'set +e
  echo "id=$(id -un)"
  sudo -n '"$SYSTEMCTL"' is-active '"$UNIT"' 2>&1
  echo "is_active_rc=$?"
  test -w '"$API"' && echo api_w=1 || echo api_w=0
  ENVF='"$API"'/host-profile.env
  if [ -f "$ENVF" ] && grep -qx "HOST_PROFILE=ionos" "$ENVF"; then
    echo host_profile_env=ok
  else
    printf "%s\n" "HOST_PROFILE=ionos" > "$ENVF" && chmod 644 "$ENVF" && echo host_profile_env=written || echo host_profile_env=fail
  fi
  DROPIN=/etc/systemd/system/helvetic-api.service.d/10-host-profile.conf
  if [ -f "$DROPIN" ]; then
    echo dropin=present
  else
    echo dropin=absent
  fi
  test -d '"$API"'/dist.snapshot-20260728-050451 && echo july_snapshot=ok || echo july_snapshot=missing
')
echo "$PRE" | tee -a "$REPORT"
echo "$PRE" | grep -q 'is_active_rc=0' || fail "is-active preflight refused or not active"
echo "$PRE" | grep -q 'api_w=1' || fail "API dir not writable"
echo "$PRE" | grep -qE 'host_profile_env=(ok|written)' || fail "host-profile.env not writable"
echo "$PRE" | grep -q 'july_snapshot=ok' || fail "july snapshot missing"
if ! echo "$PRE" | grep -q 'dropin=present'; then
  fail "refus de droits: drop-in absent (/etc/systemd/system/helvetic-api.service.d/10-host-profile.conf). sudoers ne permet pas à deploy de le poser. Frédéric doit le créer en root avant 22:00 (pas de daemon-reload requis avant le restart de bascule)."
fi
# ========== A. DRILL ==========
log "A. Drill"
DRILL_OUT=$(ssh_r 'set -euo pipefail
API='"$API"'
UNIT='"$UNIT"'
SYSTEMCTL='"$SYSTEMCTL"'
STAMP=$(date +%Y%m%d-%H%M%S)
echo "DRILL_STAMP=$STAMP"
cp -a "$API/dist" "$API/dist.new"
mv "$API/dist" "$API/dist.drill-$STAMP"
mv "$API/dist.new" "$API/dist"
cat > "$API/rollback-drill-$STAMP.sh" <<EOF
#!/bin/bash
set -euo pipefail
API=$API
UNIT=$UNIT
SYSTEMCTL=$SYSTEMCTL
mv "\$API/dist" "\$API/dist.abort-drill-$STAMP"
mv "\$API/dist.drill-$STAMP" "\$API/dist"
sudo -n "\$SYSTEMCTL" restart "\$UNIT"
EOF
chmod +x "$API/rollback-drill-$STAMP.sh"
bash "$API/rollback-drill-$STAMP.sh"
T0=$(sudo -n "$SYSTEMCTL" is-active "$UNIT"); echo "DRILL_ACTIVE_T0=$T0"
sleep 60
T60=$(sudo -n "$SYSTEMCTL" is-active "$UNIT"); echo "DRILL_ACTIVE_T60=$T60"
rm -rf "$API/dist.drill-$STAMP" "$API/dist.abort-drill-$STAMP" "$API/rollback-drill-$STAMP.sh"
test ! -e "$API/dist.new"
echo "DRILL_CLEAN=ok"
')
echo "$DRILL_OUT" | tee -a "$REPORT"
echo "$DRILL_OUT" | grep -q 'DRILL_ACTIVE_T0=active' || fail "drill is-active t+0"
echo "$DRILL_OUT" | grep -q 'DRILL_ACTIVE_T60=active' || fail "drill is-active t+60"

# ========== Stage dist.new ==========
log "Stage dist.new"
ssh_r "rm -rf '$API/dist.new' && mkdir -p '$API/dist.new'"
scp -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes \
  "$LOCAL_DIST/index.mjs" "$LOCAL_DIST/index.mjs.map" \
  "$HOST:$API/dist.new/"
ssh_r 'set -euo pipefail
test -s '"$API"'/dist.new/index.mjs
test -s '"$API"'/dist.new/index.mjs.map
test -z "$(ls -d '"$API"'/dist.drill-* 2>/dev/null || true)"
echo STAGE_OK
' | tee -a "$REPORT"

# ========== HOST_PROFILE (EnvironmentFile déjà posé ; drop-in vérifié en preflight) ==========
log "HOST_PROFILE path = $API/host-profile.env + drop-in (no api.env)"
ssh_r 'set -euo pipefail
test -f /etc/systemd/system/helvetic-api.service.d/10-host-profile.conf
grep -qx "HOST_PROFILE=ionos" '"$API"'/host-profile.env
echo HOST_PROFILE_PATH_OK
' | tee -a "$REPORT"

# ========== B. Bascule ==========
log "B. Bascule atomique"
BASCULE_OUT=$(ssh_r 'set -euo pipefail
API='"$API"'
UNIT='"$UNIT"'
SYSTEMCTL='"$SYSTEMCTL"'
test -f "$API/dist.new/index.mjs" && test -s "$API/dist.new/index.mjs"
test -z "$(ls -d "$API"/dist.drill-* 2>/dev/null || true)"
# Note: drop-in takes effect on this restart (first load). No prior daemon-reload required
# if the drop-in was already on disk — systemd reads unit+drop-ins at start.
STAMP=$(date +%Y%m%d-%H%M%S)
echo "BAK_STAMP=$STAMP"
cat > "$API/rollback-$STAMP.sh" <<EOF
#!/bin/bash
set -euo pipefail
API=$API
UNIT=$UNIT
SYSTEMCTL=$SYSTEMCTL
mv "\$API/dist" "\$API/dist.failed-$STAMP"
mv "\$API/dist.bak-$STAMP" "\$API/dist"
sudo -n "\$SYSTEMCTL" restart "\$UNIT"
EOF
chmod +x "$API/rollback-$STAMP.sh"
mv "$API/dist" "$API/dist.bak-$STAMP"
mv "$API/dist.new" "$API/dist"
sudo -n "$SYSTEMCTL" restart "$UNIT"
T0=$(sudo -n "$SYSTEMCTL" is-active "$UNIT"); echo "ACTIVE_T0=$T0"
if [ "$T0" != "active" ]; then
  echo "ANOMALY=is-active-t0"
  bash "$API/rollback-$STAMP.sh"
  echo "AFTER_ROLLBACK=$(sudo -n "$SYSTEMCTL" is-active "$UNIT")"
  exit 10
fi
sleep 60
T60=$(sudo -n "$SYSTEMCTL" is-active "$UNIT"); echo "ACTIVE_T60=$T60"
if [ "$T60" != "active" ]; then
  echo "ANOMALY=is-active-t60"
  bash "$API/rollback-$STAMP.sh"
  echo "AFTER_ROLLBACK=$(sudo -n "$SYSTEMCTL" is-active "$UNIT")"
  exit 11
fi
# journal error spike?
ERRS=$(journalctl -u helvetic-api --since "90 seconds ago" --no-pager -o cat 2>/dev/null | grep -c '"level":50' || true)
echo "JOURNAL_ERR_LEVEL50=$ERRS"
if [ "${ERRS:-0}" -gt 5 ]; then
  echo "ANOMALY=journal-errors"
  bash "$API/rollback-$STAMP.sh"
  echo "AFTER_ROLLBACK=$(sudo -n "$SYSTEMCTL" is-active "$UNIT")"
  exit 12
fi
echo "BASCULE_OK stamp=$STAMP"
')
echo "$BASCULE_OUT" | tee -a "$REPORT"
BAK_STAMP=$(echo "$BASCULE_OUT" | sed -n 's/^BAK_STAMP=//p' | tail -1)
if echo "$BASCULE_OUT" | grep -q '^ANOMALY='; then
  fail "bascule anomaly — rollback launched (see report)"
fi
echo "$BASCULE_OUT" | grep -q 'ACTIVE_T0=active' || fail "active t+0"
echo "$BASCULE_OUT" | grep -q 'ACTIVE_T60=active' || fail "active t+60"

rollback_now() {
  local reason="$1"
  log "ROLLBACK: $reason"
  ssh_r "bash '$API/rollback-$BAK_STAMP.sh'; sudo -n '$SYSTEMCTL' is-active '$UNIT'" | tee -a "$REPORT"
  fail "$reason (rollback done)"
}

# ========== C. Sonde ==========
# C. Sonde SANS création de lead.
# Candidats mesurés sur les binaires :
#   - GET /api/healthz → 200 {"status":"ok"}  (binaire live juillet)
#   - GET /api/health  → 200 {"status":"ok"}  (arbre reconciled ; pas de healthz)
#   - OPTIONS /api/leads → 204 (les deux ; ne discrimine pas les builds)
#   - aucun en-tête de version / build id
# Aucun ne prouve le pipeline lead (normalize + deliver) qu'un POST 201 prouvait.
# On refuse donc le POST. Empreinte retenue pour UNE bascule vers reconciled :
#   /api/health 200 + body ok  ET  /api/healthz 404  → le nouveau binaire répond,
#   pas l'ancien. La preuve « lead path OK » attend une route de santé dédiée
#   (ou un mode sonde CRM) — à ajouter avant de retenter une bascule métier.
log "C. Sonde santé (pas de POST /api/leads)"
PROBE_OUT=$(ssh_r 'set +e
CODE_H=$(curl -sS -o /tmp/h.body -w "%{http_code}" --max-time 5 \
  "http://127.0.0.1:3000/api/health")
BODY_H=$(cat /tmp/h.body)
CODE_Z=$(curl -sS -o /tmp/z.body -w "%{http_code}" --max-time 5 \
  "http://127.0.0.1:3000/api/healthz")
BODY_Z=$(cat /tmp/z.body)
echo "HEALTH_HTTP=$CODE_H"
echo "HEALTH_BODY=$BODY_H"
echo "HEALTHZ_HTTP=$CODE_Z"
echo "HEALTHZ_BODY=$BODY_Z"
echo "---JOURNAL---"
journalctl -u helvetic-api --since "2 minutes ago" --no-pager -o cat 2>/dev/null \
  | grep -E "error|Error|HOST_PROFILE|Unknown host|Error listening" | tail -40
')
echo "$PROBE_OUT" | tee -a "$REPORT"

CODE_H=$(echo "$PROBE_OUT" | awk -F= '/^HEALTH_HTTP=/{print $2; exit}' | tr -d '\r')
BODY_H=$(echo "$PROBE_OUT" | awk -F= '/^HEALTH_BODY=/{print substr($0,13); exit}' | tr -d '\r')
CODE_Z=$(echo "$PROBE_OUT" | awk -F= '/^HEALTHZ_HTTP=/{print $2; exit}' | tr -d '\r')

if [ "$CODE_H" != "200" ] || ! echo "$BODY_H" | grep -q '"status":"ok"'; then
  rollback_now "sonde /api/health HTTP=$CODE_H body=$BODY_H (attendu 200 {\"status\":\"ok\"})"
fi
if [ "$CODE_Z" != "404" ]; then
  rollback_now "sonde /api/healthz HTTP=$CODE_Z (attendu 404 — sinon ancien binaire encore actif)"
fi
if echo "$PROBE_OUT" | grep -qE 'Unknown host profile|Error listening|HOST_PROFILE environment'; then
  rollback_now "journal erreur critique après sonde santé"
fi
echo "PROBE_HEALTH_OK /api/health=200 /api/healthz=404" | tee -a "$REPORT"

# ========== CORS ==========
log "CORS both directions"
CORS_OUT=$(ssh_r 'set +e
echo "=== CORS allow (terrassement) ==="
curl -sS -D- -o /dev/null -X OPTIONS "http://127.0.0.1:3000/api/leads" \
  -H "Origin: https://helvetique-terrassement.ch" \
  -H "Access-Control-Request-Method: POST" | tr -d "\r" | grep -iE "HTTP/|access-control-allow-origin"
echo "=== CORS block (hetzner dachdecker) ==="
curl -sS -D- -o /tmp/cors.block -X OPTIONS "http://127.0.0.1:3000/api/leads" \
  -H "Origin: https://helvetic-dachdecker.ch" \
  -H "Access-Control-Request-Method: POST" | tr -d "\r" | grep -iE "HTTP/|access-control-allow-origin|Error"
# also try actual POST preflight result code
CODE=$(curl -sS -o /tmp/cors.body -w "%{http_code}" -X OPTIONS "http://127.0.0.1:3000/api/leads" \
  -H "Origin: https://helvetic-dachdecker.ch" \
  -H "Access-Control-Request-Method: POST")
echo "BLOCK_HTTP=$CODE"
')
echo "$CORS_OUT" | tee -a "$REPORT"
# Allow: must see Allow-Origin terrassement (or echo origin)
echo "$CORS_OUT" | grep -qi 'https://helvetique-terrassement.ch' || rollback_now "CORS allow terrassement manquant"
# Block: must NOT allow dachdecker
if echo "$CORS_OUT" | grep -A2 'CORS block' | grep -qi 'helvetic-dachdecker.ch'; then
  rollback_now "CORS a autorisé origine Hetzner"
fi

# Plus de cleanup CRM : la sonde ne crée plus de lead.

END="$(TZ=$TZ_ZONE date -Iseconds)"
log "END=$END"
{
  echo "END=$END"
  echo "RESULT=SUCCESS"
  echo "BAK_STAMP=$BAK_STAMP"
  echo "ROLLBACK_SCRIPT=$API/rollback-$BAK_STAMP.sh"
} | tee -a "$REPORT"
log "DONE — report $REPORT"
exit 0
