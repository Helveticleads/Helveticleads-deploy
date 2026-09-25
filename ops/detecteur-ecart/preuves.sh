#!/usr/bin/env bash
# Harness des preuves (dry-run sauf mention). Ne ferme JAMAIS l'issue.
# Grade 1 = rouge natif · Grade 2 = rouge par sabotage.
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

assert_no_rassurant() {
  local body="$1" grade="$2" ctx="$3"
  if grep -qiE 'tout à jour|détecteur opérationnel|detecteur operationnel' "$body"; then
    ko "$grade" "$ctx — phrase rassurante indue"
  fi
}

# --- Preuve 7 : exclus jamais en listes mesurables ---
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

# --- Preuve 8 : date expiration ---
preuve_8_expiration() {
  local grade=1
  need_token
  run_dry p8 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q '2027-09-23' "$OUT/p8/issue-body.md" || ko "$grade" "date expiration absente"
  grep -q 'jeton_expire=2027-09-23' "$OUT/p8/meta.txt" || ko "$grade" "meta sans jeton_expire"
  ok "$grade" "preuve 8 — expiration 2027-09-23"
}

# --- Preuve 1 : site à jour → A_JOUR ---
preuve_1_a_jour() {
  local grade=1
  need_token
  run_dry p1 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'n_a_jour=1' "$OUT/p1/meta.txt" || ko "$grade" "piscine pas A_JOUR"
  grep -q 'helvetique-piscine.ch' "$OUT/p1/a-jour.tsv" || ko "$grade" "absent de a-jour.tsv"
  ok "$grade" "preuve 1 — helvetique-piscine.ch A_JOUR"
}

# --- Preuve 2 : EN_RETARD par sabotage ---
preuve_2_en_retard() {
  local grade=2
  need_token
  DETECTEUR_MODE=preuve DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    run_dry p2 env
  grep -q 'PREUVE-ecart-fabrique' "$OUT/p2/en-retard.tsv" || ko "$grade" "pas EN_RETARD"
  local ecart
  ecart=$(awk -F'\t' '$2=="PREUVE-ecart-fabrique"{print $5}' "$OUT/p2/en-retard.tsv")
  awk -v e="$ecart" 'BEGIN{exit !(e+0 > 40)}' || ko "$grade" "écart=$ecart"
  ok "$grade" "preuve 2 — EN_RETARD écart=${ecart}h"
}

# --- Preuve 3 : 1er injoignable → avertissement (non bloquant) ---
preuve_3_injoignable() {
  local grade=1
  need_token
  DETECTEUR_MODE=preuve DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    run_dry p3 env
  grep -q 'PREUVE-domaine-inexistant' "$OUT/p3/avertissement-injoignable.tsv" \
    || ko "$grade" "pas AVERT_INJOIGNABLE (got $(ls "$OUT/p3"/*.tsv))"
  if grep -q 'PREUVE-domaine-inexistant' "$OUT/p3/injoignable.tsv" 2>/dev/null; then
    ko "$grade" "1er échec indûment INJOIGNABLE"
  fi
  if grep -q 'PREUVE-domaine-inexistant' "$OUT/p3/non-mesure.tsv" 2>/dev/null; then
    ko "$grade" "injoignable encore en NON_MESURE"
  fi
  ok "$grade" "preuve 3 — 1er injoignable → avertissement non bloquant"
}

# --- Preuve 4 : jeton vidé ---
preuve_4_auth() {
  local grade=2
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_MODE=normal run_dry p4 env \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'auth_fail=auth' "$OUT/p4/meta.txt" || ko "$grade" "auth_fail manquant"
  grep -q 'peut_fermer=0' "$OUT/p4/meta.txt" || ko "$grade" "peut_fermer devrait être 0"
  grep -q 'ÉCHEC D' "$OUT/p4/issue-body.md" || ko "$grade" "raison auth absente"
  assert_no_rassurant "$OUT/p4/issue-body.md" "$grade" "preuve 4"
  ok "$grade" "preuve 4 — auth fail → NON_MESURE + pas de clôture"
}

# --- Preuve 5 : dénominateur si dépôt ajouté ---
preuve_5_denom() {
  local grade=2
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_AJOUT_PREUVE=1 DETECTEUR_M_PRECEDENT=71 \
    DETECTEUR_MODE=normal run_dry p5 env
  grep -q 'M_declares=72' "$OUT/p5/meta.txt" || ko "$grade" "M≠72"
  grep -q 'M_changed=oui' "$OUT/p5/meta.txt" || ko "$grade" "M_changed absent"
  grep -q 'M a changé' "$OUT/p5/issue-body.md" || ko "$grade" "rapport sans changement M"
  grep -q 'n_non_mesure=57' "$OUT/p5/meta.txt" || ko "$grade" "attendu 57 NON_MESURE"
  ok "$grade" "preuve 5 — M 71→72"
}

# --- Preuve 6 : upsert sans duplication (dry — ne touche plus l'issue) ---
preuve_6_upsert() {
  local grade=1
  need_token
  # Deux dry-runs ciblés : même titre logique, peut_fermer=0, pas de phrase rassurante.
  run_dry p6a env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  run_dry p6b env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'peut_fermer=0' "$OUT/p6a/meta.txt" || ko "$grade" "p6a aurait pu fermer"
  grep -q 'peut_fermer=0' "$OUT/p6b/meta.txt" || ko "$grade" "p6b aurait pu fermer"
  grep -q 'PASSAGE CIBLÉ' "$OUT/p6a/issue-body.md" || ko "$grade" "titre ciblé absent"
  ok "$grade" "preuve 6 — deux passages ciblés dry, peut_fermer=0, pas de doublon écrit"
}

# --- Preuve 9 : N < M ⇒ pas rassurant, peut_fermer=0 (sabotage N=1 via UNIQUEMENT) ---
preuve_9_n_lt_m() {
  local grade=2
  need_token
  run_dry p9 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'N_mesures=1' "$OUT/p9/meta.txt" || ko "$grade" "N≠1"
  grep -q 'n_flotte=56' "$OUT/p9/meta.txt" || ko "$grade" "n_flotte≠56"
  grep -q 'peut_fermer=0' "$OUT/p9/meta.txt" || ko "$grade" "peut_fermer devrait être 0"
  grep -q 'couverture_complete=0' "$OUT/p9/meta.txt" || ko "$grade" "couverture devrait être 0"
  # Première ligne utile du rapport = N/M
  local first_nm
  first_nm=$(grep -n '^\*\*N/M\*\*' "$OUT/p9/issue-body.md" | head -1 | cut -d: -f1)
  [ -n "$first_nm" ] || ko "$grade" "N/M absent du rapport"
  # N/M doit apparaître avant tout tableau
  local first_table
  first_table=$(grep -n '^|' "$OUT/p9/issue-body.md" | head -1 | cut -d: -f1)
  [ "$first_nm" -lt "$first_table" ] || ko "$grade" "N/M pas avant les tableaux ($first_nm >= $first_table)"
  assert_no_rassurant "$OUT/p9/issue-body.md" "$grade" "preuve 9"
  grep -q 'passage incomplet\|PASSAGE CIBLÉ\|aucune conclusion' "$OUT/p9/issue-body.md" \
    || ko "$grade" "verdict incomplet/ciblé absent"
  ok "$grade" "preuve 9 — N=1 < M=56 → pas rassurant, peut_fermer=0, N/M en tête"
}

# --- Preuve 10 : 2e injoignable consécutif → INJOIGNABLE bloquant ---
preuve_10_injoignable_2() {
  local grade=1
  need_token
  local prev="$OUT/prev-inj.txt"
  printf 'domaine-qui-nexiste-pas-hl-detecteur.test 1 2026-09-01T00:00:00Z\n' > "$prev"
  DETECTEUR_INJOIGNABLE_PREV="$prev" DETECTEUR_MODE=preuve \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
    run_dry p10 env
  grep -q 'PREUVE-domaine-inexistant' "$OUT/p10/injoignable.tsv" \
    || ko "$grade" "pas INJOIGNABLE au 2e passage"
  grep -q 'n_injoignable=1' "$OUT/p10/meta.txt" || ko "$grade" "n_injoignable≠1"
  # Ciblé → peut_fermer=0 de toute façon ; on vérifie le seau + absence rassurant
  assert_no_rassurant "$OUT/p10/issue-body.md" "$grade" "preuve 10"
  ok "$grade" "preuve 10 — 2e injoignable → INJOIGNABLE bloquant"
}

# --- Preuve 11 : passage ciblé — titre + pas de conclusion ---
preuve_11_cible() {
  local grade=1
  need_token
  run_dry p11 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  head -5 "$OUT/p11/issue-body.md" | grep -q 'PASSAGE CIBLÉ' \
    || ko "$grade" "titre PASSAGE CIBLÉ absent en tête"
  grep -q 'FR-helvetique-piscine.ch|helvetique-piscine.ch' "$OUT/p11/issue-body.md" \
    || ko "$grade" "cible non nommée"
  grep -q 'verdict=cible' "$OUT/p11/meta.txt" || ko "$grade" "verdict≠cible"
  grep -q 'peut_fermer=0' "$OUT/p11/meta.txt" || ko "$grade" "ciblé ne doit pas fermer"
  assert_no_rassurant "$OUT/p11/issue-body.md" "$grade" "preuve 11"
  # Schedule refuse le ciblage
  if DETECTEUR_EVENT_NAME=schedule DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch" \
      DETECTEUR_DRY_RUN=1 DETECTEUR_RESULT_DIR="$OUT/p11s" \
      bash "$DIR/detecteur.sh" 2>"$OUT/p11s.err"; then
    ko "$grade" "schedule+UNIQUEMENT aurait dû échouer"
  else
    grep -qi 'interdit\|ERREUR' "$OUT/p11s.err" || ko "$grade" "message d'interdiction schedule absent"
  fi
  ok "$grade" "preuve 11 — ciblé nommé, pas de conclusion, schedule refuse"
}

# --- Preuve 12 : publication manuelle = 16 sur inventaire complet ---
preuve_12_manuels() {
  local grade=1
  need_token
  # Auth vide + flotte complète : pas d'HTTP, compte manuels flotte intact.
  JETON_LECTURE_DEPOTS="" DETECTEUR_MODE=normal run_dry p12 env
  grep -q 'n_manuels=16' "$OUT/p12/meta.txt" || ko "$grade" "meta n_manuels≠16 ($(grep n_manuels "$OUT/p12/meta.txt"))"
  grep -q 'Publication manuelle : \*\*16\*\*' "$OUT/p12/issue-body.md" \
    || ko "$grade" "rapport sans Publication manuelle : 16"
  grep -q 'Publication manuelle (16)' "$OUT/p12/issue-body.md" \
    || ko "$grade" "section manuels absente"
  # Même sous ciblage, le compte flotte reste 16
  JETON_LECTURE_DEPOTS="" run_dry p12c env \
    DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'n_manuels=16' "$OUT/p12c/meta.txt" || ko "$grade" "ciblé a remis manuels à 0"
  ok "$grade" "preuve 12 — publication manuelle = 16 (flotte et ciblé)"
}

# --- Preuve 13 : N/M en première ligne du rapport ---
preuve_13_nm_tete() {
  local grade=1
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_MODE=normal run_dry p13 env
  local first
  first=$(head -1 "$OUT/p13/issue-body.md")
  printf '%s' "$first" | grep -q '^\*\*N/M\*\*' \
    || ko "$grade" "ligne 1 n'est pas N/M : $first"
  ok "$grade" "preuve 13 — N/M est la ligne 1 du rapport"
}

# --- Preuve 14 : limite écrite au pied ---
preuve_14_limite() {
  local grade=1
  need_token
  JETON_LECTURE_DEPOTS="" DETECTEUR_MODE=normal run_dry p14 env
  grep -q "Limite (sites datés)" "$OUT/p14/issue-body.md" \
    || ko "$grade" "phrase de limite absente du pied"
  grep -q "DETECTEUR_EMPREINTES_V1" "$OUT/p14/issue-body.md" \
    || ko "$grade" "bloc persistance empreintes absent"
  ok "$grade" "preuve 14 — limite + bloc persistance présents"
}

# --- Preuve 15 : sans Last-Modified → SUIVI PAR EMPREINTE (pas À JOUR / EN RETARD) ---
preuve_15_suivi_empreinte() {
  local grade=1
  need_token
  run_dry p15 env DETECTEUR_UNIQUEMENT="FR-domisane-suisse.ch|domisane-suisse.ch"
  grep -q 'n_suivi=1' "$OUT/p15/meta.txt" || ko "$grade" "domisane pas en suivi (meta=$(grep n_ "$OUT/p15/meta.txt"))"
  grep -q 'domisane-suisse.ch' "$OUT/p15/suivi-empreinte.tsv" || ko "$grade" "absent de suivi-empreinte.tsv"
  grep -q 'première observation' "$OUT/p15/suivi-empreinte.tsv" || ko "$grade" "pas de première observation"
  grep -qi 'ne compare pas à main\|ne compare rien à' "$OUT/p15/issue-body.md" \
    || ko "$grade" "phrase « ne compare pas à main » absente"
  grep -qi 'cache de 24 h\|s-maxage=86400' "$OUT/p15/suivi-empreinte.tsv" "$OUT/p15/issue-body.md" \
    || ko "$grade" "mention cache 24 h absente"
  if grep -q 'domisane' "$OUT/p15/a-jour.tsv" 2>/dev/null; then
    ko "$grade" "domisane indûment A_JOUR"
  fi
  if grep -q 'domisane' "$OUT/p15/en-retard.tsv" 2>/dev/null; then
    ko "$grade" "domisane indûment EN_RETARD"
  fi
  grep -q 'peut_fermer=0' "$OUT/p15/meta.txt" || ko "$grade" "suivi ne doit pas permettre de fermer"
  ok "$grade" "preuve 15 — SUIVI PAR EMPREINTE + cache 24 h + ne compare pas à main"
}

# --- Preuve 16 : empreinte inchangée / changée (sabotage PREV) ---
preuve_16_empreinte_delta() {
  local grade=2
  need_token
  local prev="$OUT/prev-emp.txt"
  # Hash réel actuel de domisane
  local real
  real=$(curl -sL --max-time 15 "https://domisane-suisse.ch/" | shasum -a 256 | awk '{print substr($1,1,12)}')
  printf 'domisane-suisse.ch %s 2026-09-01T00:00:00Z cache\n' "$real" > "$prev"
  DETECTEUR_EMPREINTES_PREV="$prev" \
    run_dry p16a env DETECTEUR_UNIQUEMENT="FR-domisane-suisse.ch|domisane-suisse.ch"
  grep -q 'inchangé depuis le 2026-09-01' "$OUT/p16a/suivi-empreinte.tsv" \
    || ko "$grade" "attendu inchangé (got $(cat "$OUT/p16a/suivi-empreinte.tsv"))"
  # Sabotage : hash précédent faux → a changé
  printf 'domisane-suisse.ch deadbeefdead 2026-09-01T00:00:00Z cache\n' > "$prev"
  DETECTEUR_EMPREINTES_PREV="$prev" \
    run_dry p16b env DETECTEUR_UNIQUEMENT="FR-domisane-suisse.ch|domisane-suisse.ch"
  grep -q 'a changé le ' "$OUT/p16b/suivi-empreinte.tsv" \
    || ko "$grade" "attendu a changé (got $(cat "$OUT/p16b/suivi-empreinte.tsv"))"
  ok "$grade" "preuve 16 — inchangé / a changé selon PREV (sabotage hash)"
}

# --- Preuve 17 : marqueur brouillon → hors population ---
preuve_17_brouillon() {
  local grade=1
  need_token
  DETECTEUR_MARQUEUR_OVERRIDE="FR-helvetique-piscine.ch|brouillon|2026-09-01T00:00:00Z" \
    run_dry p17 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'helvetique-piscine.ch' "$OUT/p17/brouillon.tsv" || ko "$grade" "pas BROUILLON"
  grep -q 'n_brouillon=1' "$OUT/p17/meta.txt" || ko "$grade" "n_brouillon≠1"
  if grep -q 'helvetique-piscine' "$OUT/p17/en-retard.tsv" 2>/dev/null; then
    ko "$grade" "brouillon indûment EN_RETARD"
  fi
  if grep -q 'helvetique-piscine' "$OUT/p17/a-jour.tsv" 2>/dev/null; then
    ko "$grade" "brouillon indûment A_JOUR"
  fi
  grep -q 'Pas encore publiés\|pas encore publié' "$OUT/p17/issue-body.md" \
    || ko "$grade" "section pas encore publiés absente"
  ok "$grade" "preuve 17 — brouillon hors population + âge"
}

# --- Preuve 18 : brouillon ≥ 60 j → BROUILLON_DORMANT ---
preuve_18_brouillon_dormant() {
  local grade=1
  need_token
  DETECTEUR_MARQUEUR_OVERRIDE="FR-helvetique-piscine.ch|brouillon|2026-01-01T00:00:00Z" \
    run_dry p18 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'helvetique-piscine.ch' "$OUT/p18/brouillon-dormant.tsv" \
    || ko "$grade" "pas BROUILLON_DORMANT"
  grep -q 'n_brouillon_dormant=1' "$OUT/p18/meta.txt" || ko "$grade" "n_brouillon_dormant≠1"
  ok "$grade" "preuve 18 — brouillon ≥ 60 j → BROUILLON_DORMANT"
}

# --- Preuve 19 : marqueur ABSENT = en_ligne (site réel mesuré) ---
preuve_19_absent_en_ligne() {
  local grade=1
  need_token
  # Pas d'override → API ; piscine n'a pas de marqueur → en_ligne → A_JOUR
  run_dry p19 env DETECTEUR_UNIQUEMENT="FR-helvetique-piscine.ch|helvetique-piscine.ch"
  grep -q 'n_a_jour=1' "$OUT/p19/meta.txt" || ko "$grade" "absent ne doit pas sortir du filet"
  grep -q 'n_brouillon=0' "$OUT/p19/meta.txt" || ko "$grade" "absent traité comme brouillon"
  ok "$grade" "preuve 19 — marqueur absent = en_ligne = surveillé"
}

# --- Preuve 20 : README documente la convention ---
preuve_20_readme() {
  local grade=1
  local r="$DIR/README.md"
  [ -f "$r" ] || ko "$grade" "README absent"
  grep -q '\.helveticleads/publication' "$r" || ko "$grade" "chemin marqueur absent"
  grep -q 'brouillon' "$r" || ko "$grade" "valeur brouillon absente"
  grep -q 'en_ligne' "$r" || ko "$grade" "valeur en_ligne absente"
  grep -qiE 'absent.*=.*en_ligne|ABSENT.*en_ligne' "$r" || ko "$grade" "règle absence absente"
  grep -q '60' "$r" || ko "$grade" "seuil 60 j absent"
  grep -q 'MODIFS RÉSEAUX\|MODIFS RESEAUX' "$r" || ko "$grade" "passation MODIFS RÉSEAUX absente"
  grep -qi 'jamais servi\|dist/public\|pas.*servi' "$r" || ko "$grade" "interdiction de servir absente"
  ok "$grade" "preuve 20 — README convention publication"
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
preuve_9_n_lt_m
preuve_10_injoignable_2
preuve_11_cible
preuve_12_manuels
preuve_13_nm_tete
preuve_14_limite
preuve_15_suivi_empreinte
preuve_16_empreinte_delta
preuve_17_brouillon
preuve_18_brouillon_dormant
preuve_19_absent_en_ligne
preuve_20_readme

echo
echo "RESULT pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
