#!/bin/bash
# install.sh — instala skill Oracfit no Hermes (~/.hermes/skills/oracfit)
# Uso: adapters/hermes/install.sh [--dry-run]

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.hermes/skills/oracfit"
# legado: também mantém alias dispatch → oracfit skill
LEGACY_DIR="$HOME/.hermes/skills/dispatch"

echo "install.sh (hermes) — destino: $DEST_DIR"

install_link() {
  SRC="$1"
  DEST="$2"
  if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
    echo "   already: $DEST -> $SRC"
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

install_link "$ADAPTER_DIR/HERMES.md" "$DEST_DIR/SKILL.md"
install_link "$ADAPTER_DIR/env.sh" "$DEST_DIR/env.sh"
install_link "$ADAPTER_DIR/HERMES.md" "$LEGACY_DIR/SKILL.md"
install_link "$ADAPTER_DIR/env.sh" "$LEGACY_DIR/env.sh"

# Drop a tiny pointer so gateway sessions find ORACFIT_ROOT
POINTER="$HOME/.hermes/oracfit-root"
ORACFIT_ROOT_VAL="${ORACFIT_ROOT:-$HOME/.oracfit/current}"
if [ $DRY_RUN -eq 1 ]; then
  echo "   [dry-run] echo $ORACFIT_ROOT_VAL > $POINTER"
else
  echo "$ORACFIT_ROOT_VAL" > "$POINTER"
  echo "   pointer: $POINTER -> $ORACFIT_ROOT_VAL"
fi

echo "install.sh (hermes) done (dry_run=$DRY_RUN)"
