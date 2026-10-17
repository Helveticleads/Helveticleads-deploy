#!/usr/bin/env bash
# Garde noindex — RACINE du build uniquement ($SRC/index.html).
# Une page interne en noindex est légitime ; un index.html racine en noindex
# sort le site entier de l'index : refus avant rsync.
# Aucun drapeau, aucune variable de contournement.
#
# Usage : garde-noindex-racine.sh <SRC>
#   SRC = répertoire racine du build (contient index.html)
# Sortie : GATE_OK ou GATE_FAIL avec motif + emplacement exact ; exit 1 si refus.
set -euo pipefail

SRC="${1:?usage: garde-noindex-racine.sh <SRC>}"
INDEX="$SRC/index.html"

if [ ! -f "$INDEX" ]; then
  echo "GATE_FAIL build:noindex_racine:index_absent:$INDEX"
  exit 1
fi

# Lignes candidates : meta robots / googlebot / … ou X-Robots-Tag (http-equiv ou brut).
# Insensible à la casse. On ne lit QUE la racine.
refuse() {
  local kind="$1" line_no="$2" excerpt="$3"
  # Motif : directive trouvée + emplacement exact (fichier:ligne + extrait).
  echo "GATE_FAIL build:noindex_racine:${kind}:fichier=${INDEX}:ligne=${line_no}:extrait=${excerpt}"
  exit 1
}

line_no=0
while IFS= read -r line || [ -n "$line" ]; do
  line_no=$((line_no + 1))
  # Normaliser espaces pour l'extrait affiché (une ligne).
  excerpt=$(printf '%s' "$line" | tr '\t' ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/[[:space:]]\{1,\}/ /g')
  [ -n "$excerpt" ] || continue

  lower=$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')

  # meta name="robots" (ou googlebot, bingbot, …) avec noindex dans content
  if printf '%s' "$lower" | grep -qE '<meta[^>]*name=["'"'"']?(robots|googlebot|bingbot|yandex)["'"'"']?[^>]*>'; then
    if printf '%s' "$lower" | grep -qE 'content=["'"'"'][^"'"'"']*noindex'; then
      refuse "meta_robots_noindex" "$line_no" "$excerpt"
    fi
  fi
  # content avant name (ordre d'attributs inversé)
  if printf '%s' "$lower" | grep -qE '<meta[^>]*content=["'"'"'][^"'"'"']*noindex[^"'"'"']*["'"'"'][^>]*name=["'"'"']?(robots|googlebot|bingbot|yandex)["'"'"']?'; then
    refuse "meta_robots_noindex" "$line_no" "$excerpt"
  fi

  # <meta http-equiv="X-Robots-Tag" content="noindex">
  if printf '%s' "$lower" | grep -qE '<meta[^>]*http-equiv=["'"'"']?x-robots-tag["'"'"']?'; then
    if printf '%s' "$lower" | grep -qE 'content=["'"'"'][^"'"'"']*noindex'; then
      refuse "meta_http_equiv_x_robots_tag_noindex" "$line_no" "$excerpt"
    fi
  fi

  # En-tête brut éventuel dans le fichier (X-Robots-Tag: noindex)
  if printf '%s' "$lower" | grep -qE 'x-robots-tag[[:space:]]*:[[:space:]]*[^[:space:]]*noindex'; then
    refuse "x_robots_tag_header_noindex" "$line_no" "$excerpt"
  fi
done < "$INDEX"

echo "GATE_OK build:noindex_racine:$INDEX"
exit 0
