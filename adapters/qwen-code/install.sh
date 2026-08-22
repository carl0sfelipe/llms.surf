#!/bin/bash
# install.sh — instala artefatos do adapter qwen-code no destino do CLI
# Uso: adapters/qwen-code/install.sh [--dry-run]
#
# ⚠️ EXPERIMENTAL: a CLI `qwen` não existe neste host (ver DISCOVERY.md).
# TODO-VERIFICAR: o destino abaixo ($HOME/.qwen/skills/dispatch) é suposição por
# analogia com ~/.claude/skills e ~/.hermes/skills — NÃO confirmado por `qwen --help`
# (PRD seção 11, regra 5). Rode o Passo 0 antes de instalar de verdade.
#
# Idempotente: symlink só é (re)criado se ainda não apontar para o alvo correto.

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.qwen/skills/dispatch"

echo "🔧 install.sh (qwen-code) — destino: $DEST_DIR"

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

install_link "$ADAPTER_DIR/QWEN.md" "$DEST_DIR/SKILL.md"
install_link "$ADAPTER_DIR/env.sh" "$DEST_DIR/env.sh"

echo "✅ install.sh (qwen-code) concluído (dry_run=$DRY_RUN)"
