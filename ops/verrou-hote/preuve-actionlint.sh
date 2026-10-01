#!/usr/bin/env bash
# Preuve : actionlint passe sur les workflows actuels et échoue sur le YAML #7 cassé.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

if ! command -v actionlint >/dev/null 2>&1; then
  echo "FAIL actionlint absent (installer : https://github.com/rhysd/actionlint)"
  exit 1
fi

BROKEN="ops/verrou-hote/fixtures/deploy-infomaniak-ff24c99-broken.yml"
test -f "$BROKEN"

echo "=== actionlint workflows actuels (attendu : exit 0, silence) ==="
set +e
actionlint .github/workflows/*.yml
rc_ok=$?
set -e
echo "exit=$rc_ok"
if [ "$rc_ok" -ne 0 ]; then
  echo "FAIL workflows actuels doivent parser"
  exit 1
fi
echo "PASS workflows actuels"

echo "=== actionlint fixture #7 cassée (attendu : exit ≠ 0) ==="
set +e
actionlint "$BROKEN"
rc_bad=$?
set -e
echo "exit=$rc_bad"
if [ "$rc_bad" -eq 0 ]; then
  echo "FAIL la garde aurait dû attraper le YAML #7"
  exit 1
fi
echo "PASS fixture #7 rejetée"
echo "ALL_PASS preuve-actionlint"
