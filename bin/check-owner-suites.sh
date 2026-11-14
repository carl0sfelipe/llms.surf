#!/usr/bin/env bash
# bin/check-owner-suites.sh — confere que as suítes de aceitação do dono estão
# intactas, por HASH (o modelo pode mover o arquivo de lugar, não alterá-lo).
#
# Portable: funciona em qualquer repo. O manifesto fica na raiz do repo:
#   .owner-suites.sha256   →   "<sha256>  <caminho>"
#
# Uso: bash bin/check-owner-suites.sh [caminho-do-repo]
# Exit: 0 = todas intactas; 1 = alguma alterada/sumiu.
set -uo pipefail
REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO" || exit 2

MANIFEST=".owner-suites.sha256"
[ -f "$MANIFEST" ] || { echo "FALTA: manifesto $MANIFEST ausente em $REPO" >&2; exit 1; }

declare -A INDEX
while read -r hash path; do
  [ -n "${hash:-}" ] || continue
  INDEX["$hash"]="$path"
done < <(find . -type f \
  -not -path "./node_modules/*" -not -path "./.git/*" -not -path "./dist/*" \
  -not -path "./.dispatch/*" -not -path "./_bmad-output/*" -print0 \
  | xargs -0 sha256sum 2>/dev/null)

FAILED=0
while read -r expected path; do
  [ -n "${expected:-}" ] || continue
  if [[ -n "${INDEX[$expected]:-}" ]]; then
    echo "ok: suíte do dono intacta (${INDEX[$expected]})"
  else
    echo "FALTA: suíte do dono alterada ou ausente: ${path} (sha256 ${expected})" >&2
    FAILED=1
  fi
done < "$MANIFEST"

exit "$FAILED"
