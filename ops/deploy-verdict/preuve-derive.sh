#!/usr/bin/env bash
# Refuse d'exécuter les scripts hors du préfixe dépôt attendu (anti-dérive /usr/local).
# Usage : preuve-derive.sh <chemin-script-invoqué>
set -euo pipefail
target="${1:?chemin script manquant}"
abs="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
case "$abs" in
  */ops/deploy-verdict/*) echo "DERIVE_OK $abs"; exit 0 ;;
  */_verrou_hote/ops/deploy-verdict/*) echo "DERIVE_OK $abs"; exit 0 ;;
  */_deploy_verdict/ops/deploy-verdict/*) echo "DERIVE_OK $abs"; exit 0 ;;
esac
echo "DERIVE_FAIL script hors dépôt : $abs" >&2
exit 1
