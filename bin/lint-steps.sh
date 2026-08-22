#!/usr/bin/env bash
set -euo pipefail

FLUXOS_DIR="${1:-fluxos}"
VIOLATIONS=0

while IFS= read -r -d '' file; do
  while IFS= read -r match; do
    echo "  $match"
    VIOLATIONS=$((VIOLATIONS + 1))
  done < <(grep -n -E 'opencode run|claude -p|curl ' "$file" 2>/dev/null || true)
done < <(find "$FLUXOS_DIR" -name 'step-*.md' -type f -print0 2>/dev/null)

if [ "$VIOLATIONS" -gt 0 ]; then
  echo ""
  echo "ERRO: $VIOLATIONS ocorrência(s) de comandos crus encontrada(s)."
  echo "Steps devem chamar os wrappers de bin/ em vez de comandos crus."
  exit 1
fi

echo "OK: Nenhum step com comandos crus encontrado."
exit 0
