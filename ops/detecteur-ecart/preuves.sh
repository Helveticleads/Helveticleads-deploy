#!/usr/bin/env bash
# Harness local des 8 preuves (dry-run sauf mention).
# Grade 1 = rouge natif (assertion échoue si le comportement est faux).
# Grade 2 = rouge par sabotage (on casse volontairement une entrée).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/.detecteur-preuves"
mkdir -p "$OUT"
chmod +x "$DIR/detecteur.sh"

pass=0; fail=0
ok()   { pass=$((pass+1)); echo "PASS [$1] $2"; }
ko()   { fail=$((fail+1)); echo "FAIL [$1] $2"; exit 1; }

need_token() {
  if [ -z "${JETON_LECTURE_DEPOTS:-}" ]; then
    # En local : réutilise le token gh (pas le secret Actions — on ne le lit pas).
    JETON_LECTURE_DEPOTS="$(gh auth token)"
    export JETON_LECTURE_DEPOTS
  fi
  export GITHUB_TOKEN="${GITHUB_TOKEN:-$JETON_LECTURE_DEPOTS}"
}

run_dry() {
  local label="$1"; shift
  local dest="$OUT/$label"
  rm -rf "$dest"; mkdir -p "$dest"
  DETECTEUR_DRY_RUN=1 DETECTEUR_RESULT_DIR="$dest" \
    DETECTEUR_MODE="${DETECTEUR_MODE:-normal}" \
    "$@" bash "$DIR/detecteur.sh"
}

# --- Preuve 7 (hors réseau) : exclus jamais en EN_RETARD dans les listes ---
preuve_7_exclus() {
  local grade=1
  if grep -E '^(Helveticleads-|IT-elvetica-|debarasstout|FR-helvetique-paysagiste)' \
      "$DIR/sites-auto.txt" "$DIR/sites-declares.txt" 2>/dev/null; then
    ko "$grade" "un exclu apparaît dans les listes mesurables"
  fi
  local n
  n=$(grep -cvE '^#|^$' "$DIR/exclusions.txt" || true)
  [ "$n" -eq 15 ] || ko "$grade" "exclusions=$n (attendu 15)"
  ok "$grade" "preuve 7 — 15 exclus absents des listes mesurables"
}

# --- Preuve 8 : date expiration dans le corps ---
preuve_8_expiration() {
  local grade=1
  need_token
  run_dry p8 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q '2027-09-23' "$OUT/p8/issue-body.md" || ko "$grade" "date expiration absente du rapport"
  grep -q 'JETON_LECTURE_DEPOTS' "$OUT/p8/issue-body.md" || ko "$grade" "nom du jeton absent"
  grep -q 'jeton_expire=2027-09-23' "$OUT/p8/meta.txt" || ko "$grade" "meta sans jeton_expire"
  ok "$grade" "preuve 8 — expiration 2027-09-23 dans rapport + meta"
}

# --- Preuve 1 : site à jour → A_JOUR ---
preuve_1_a_jour() {
  local grade=1
  need_token
  run_dry p1 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'n_a_jour=1' "$OUT/p1/meta.txt" || ko "$grade" "piscine pas A_JOUR (meta=$(cat "$OUT/p1/meta.txt"))"
  grep -q 'helvetique-piscine.ch' "$OUT/p1/a-jour.tsv" || ko "$grade" "absent de a-jour.tsv"
  ok "$grade" "preuve 1 — helvetique-piscine.ch classé A_JOUR"
}

# --- Preuve 2 : fichier servi plus ancien → EN_RETARD (sabotage date commit) ---
preuve_2_en_retard() {
  local grade=2
  need_token
  DETECTEUR_MODE=preuve DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    run_dry p2 env
  grep -q 'PREUVE-ecart-fabrique' "$OUT/p2/en-retard.tsv" \
    || ko "$grade" "écart fabriqué pas EN_RETARD"
  local ecart
  ecart=$(awk -F'\t' '$2=="PREUVE-ecart-fabrique"{print $5}' "$OUT/p2/en-retard.tsv")
  awk -v e="$ecart" 'BEGIN{exit !(e+0 > 40)}' \
    || ko "$grade" "écart=$ecart h (attendu > 40)"
  ok "$grade" "preuve 2 — EN_RETARD avec écart=${ecart}h (sabotage +2j)"
}

# --- Preuve 3 : domaine injoignable → NON_MESURE ---
preuve_3_injoignable() {
  local grade=1
  need_token
  DETECTEUR_MODE=preuve DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    run_dry p3 env
  grep -q 'PREUVE-domaine-inexistant' "$OUT/p3/non-mesure.tsv" \
    || ko "$grade" "domaine inexistant pas NON_MESURE"
  if grep -q 'PREUVE-domaine-inexistant' "$OUT/p3/a-jour.tsv" 2>/dev/null; then
    ko "$grade" "domaine inexistant indûment A_JOUR"
  fi
  ok "$grade" "preuve 3 — domaine injoignable → NON_MESURE"
}

# --- Preuve 4 : jeton vidé → TOUS NON_MESURE + raison en tête ---
preuve_4_auth() {
  local grade=2
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_MODE=normal run_dry p4 env \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'auth_fail=auth' "$OUT/p4/meta.txt" || ko "$grade" "auth_fail non signalé"
  grep -q 'n_a_jour=0' "$OUT/p4/meta.txt" || ko "$grade" "A_JOUR non nul malgré auth fail"
  grep -q 'ÉCHEC D' "$OUT/p4/issue-body.md" || ko "$grade" "raison auth absente en tête du rapport"
  grep -q '2027-09-23' "$OUT/p4/issue-body.md" || ko "$grade" "expiration absente même en auth fail"
  [ ! -s "$OUT/p4/a-jour.tsv" ] || ko "$grade" "a-jour non vide sous auth fail"
  [ ! -s "$OUT/p4/en-retard.tsv" ] || ko "$grade" "en-retard non vide sous auth fail"
  # UNIQUEMENT : M reste 71 (flotte), mais 1 ligne mesurée → NON_MESURE
  grep -q 'n_non_mesure=1' "$OUT/p4/meta.txt" || ko "$grade" "attendu 1 NON_MESURE en UNIQUEMENT"
  ok "$grade" "preuve 4 — jeton vidé → tous NON_MESURE + tête CAUTION"
}

# --- Preuve 5 : dénominateur exact si dépôt ajouté ---
# Sabotage auth (jeton vide) pour ne pas balayer 57 domaines : on vérifie M, pas HTTP.
preuve_5_denom() {
  local grade=2
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_AJOUT_PREUVE=1 DETECTEUR_M_PRECEDENT=71 \
    DETECTEUR_MODE=normal run_dry p5 env
  grep -q 'M_declares=72' "$OUT/p5/meta.txt" || ko "$grade" "M≠72 après ajout (meta=$(grep M_ "$OUT/p5/meta.txt"))"
  grep -q 'M_changed=oui' "$OUT/p5/meta.txt" || ko "$grade" "M_changed pas oui"
  grep -q 'M a changé' "$OUT/p5/issue-body.md" || ko "$grade" "rapport ne dit pas que M a changé"
  grep -E '\*\*[0-9]+\*\* mesurés sur \*\*72\*\* déclarés, dont \*\*15\*\* exclus et \*\*[0-9]+\*\* non mesurés' \
    "$OUT/p5/issue-body.md" \
    || ko "$grade" "libellé dénominateur inexact"
  # Sous auth fail, tous NON_MESURE ; N_mesures = 57 (56+1)
  grep -q 'n_non_mesure=57' "$OUT/p5/meta.txt" || ko "$grade" "attendu 57 NON_MESURE (flotte+ajout)"
  ok "$grade" "preuve 5 — M 71→72 + libellé N sur M dont X exclus et Y non mesurés"
}

# --- Preuve 6 : issue mise à jour, pas dupliquée (nécessite réseau + droits issues) ---
preuve_6_upsert() {
  local grade=1
  if [ "${DETECTEUR_SKIP_ISSUE:-0}" = "1" ]; then
    echo "SKIP [1] preuve 6 — DETECTEUR_SKIP_ISSUE=1"
    return
  fi
  need_token
  # Deux passages dry ne touchent pas l'issue ; on vérifie la logique de recherche
  # via un vrai double passage si GITHUB_TOKEN a issues:write (Actions).
  # En local on compte les issues existantes avant/après un upsert réel unique.
  local before after
  before=$(gh issue list -R Helveticleads/Helveticleads-deploy --state all --limit 50 \
    --json title --jq '[.[] | select(.title=="Écart fusionné ↔ servi")] | length')
  DETECTEUR_RESULT_DIR="$OUT/p6a" DETECTEUR_MODE=normal \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    bash "$DIR/detecteur.sh"
  DETECTEUR_RESULT_DIR="$OUT/p6b" DETECTEUR_MODE=normal \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    bash "$DIR/detecteur.sh"
  after=$(gh issue list -R Helveticleads/Helveticleads-deploy --state all --limit 50 \
    --json title --jq '[.[] | select(.title=="Écart fusionné ↔ servi")] | length')
  [ "$after" -eq "$before" ] || [ "$after" -eq 1 ] \
    || ko "$grade" "issues Écart : before=$before after=$after (duplication?)"
  [ "$after" -eq 1 ] || ko "$grade" "attendu exactement 1 issue, got $after"
  ok "$grade" "preuve 6 — une seule issue après deux passages (count=$after)"
}

echo "=== Preuves détecteur d'écart ==="
preuve_7_exclus
preuve_8_expiration
preuve_1_a_jour
preuve_3_injoignable
preuve_2_en_retard
preuve_4_auth
preuve_5_denom
preuve_6_upsert

echo
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
