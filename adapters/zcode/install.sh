#!/bin/bash
# install.sh — instala artefatos do adapter zcode
# Uso: adapters/zcode/install.sh [--dry-run]

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.zcode/skills/oracfit"
ZCODE_APP="/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs"
ZCODE_LINK="$HOME/.local/bin/zcode"
CLI_CONFIG="$HOME/.zcode/cli/config.json"

echo "install.sh (zcode) — destino skill: $DEST_DIR"

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

if [ -f "$ZCODE_APP" ]; then
  if [ $DRY_RUN -eq 1 ]; then
    echo "   [dry-run] ln -sfn $ZCODE_APP $ZCODE_LINK"
  else
    mkdir -p "$(dirname "$ZCODE_LINK")"
    ln -sfn "$ZCODE_APP" "$ZCODE_LINK"
    echo "   zcode CLI: $ZCODE_LINK -> $ZCODE_APP"
  fi
else
  echo "   WARN: ZCode.app não encontrado em $ZCODE_APP"
fi

install_link "$ADAPTER_DIR/ZCODE.md" "$DEST_DIR/SKILL.md"
install_link "$ADAPTER_DIR/env.sh" "$DEST_DIR/env.sh"

# Seed cli config se ainda não existe (sem apiKey — user faz zcode login)
if [ ! -f "$CLI_CONFIG" ] && [ $DRY_RUN -eq 0 ]; then
  mkdir -p "$(dirname "$CLI_CONFIG")"
  cat > "$CLI_CONFIG" <<'EOF'
{
  "model": {
    "main": "builtin:zai-coding-plan/GLM-5.2"
  },
  "provider": {
    "builtin:zai-coding-plan": {
      "kind": "anthropic",
      "options": {
        "baseURL": "https://api.z.ai/api/anthropic"
      }
    }
  }
}
EOF
  echo "   seeded $CLI_CONFIG (falta apiKey — rode: zcode login)"
elif [ $DRY_RUN -eq 1 ]; then
  echo "   [dry-run] seed $CLI_CONFIG if missing"
fi

echo "install.sh (zcode) done (dry_run=$DRY_RUN)"
