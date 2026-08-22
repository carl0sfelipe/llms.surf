#!/bin/bash
# install.sh — instala a skill claude-code do dispatch em ~/.claude/skills/
# Uso: adapters/claude-code/install.sh [--dry-run]
#
# Idempotente: symlink só é (re)criado se ainda não apontar para o alvo correto.

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude/skills/dispatch-claude-code"

echo "🔧 install.sh (claude-code) — destino: $DEST_DIR"

install_link() {
  SRC="$1"
  DEST="$2"
  if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
    echo "   já instalado: $DEST -> $SRC"
    return 0
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "   [dry-run] ln -sf $SRC $DEST"
    return 0
  fi
  mkdir -p "$(dirname "$DEST")"
  ln -sf "$SRC" "$DEST"
  echo "   instalado: $DEST -> $SRC"
}

install_link "$ADAPTER_DIR/SKILL.md" "$DEST_DIR/SKILL.md"

echo "✅ install.sh (claude-code) concluído (dry_run=$DRY_RUN)"
