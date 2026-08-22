#!/bin/bash
# install.sh — instala a skill cursor do Oracfit em ~/.cursor/skills/oracfit/
# Uso: adapters/cursor/install.sh [--dry-run]

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.cursor/skills/oracfit"

install_link() {
  SRC="$1"
  DEST="$2"
  if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
    echo "   already installed: $DEST -> $SRC"
    return 0
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "   [dry-run] ln -sf $SRC $DEST"
    return 0
  fi
  mkdir -p "$(dirname "$DEST")"
  ln -sf "$SRC" "$DEST"
  echo "   installed: $DEST -> $SRC"
}

echo "Installing cursor thin skill ..."
install_link "$ADAPTER_DIR/SKILL.md" "$DEST_DIR/SKILL.md"
install_link "$ADAPTER_DIR/env.sh" "$DEST_DIR/env.sh"
install_link "$ADAPTER_DIR/CURSOR.md" "$DEST_DIR/CURSOR.md"
echo "Done (dry_run=$DRY_RUN)"
