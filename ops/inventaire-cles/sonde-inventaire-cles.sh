#!/usr/bin/env bash
# Enveloppe : délègue à sonde-inventaire-cles.py (portable bash 3 / 5).
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIR/sonde-inventaire-cles.py"
