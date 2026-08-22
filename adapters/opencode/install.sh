#!/bin/bash
# install.sh — instala artefatos do adapter opencode no destino do CLI
# Uso: adapters/opencode/install.sh [--dry-run]
#
# Idempotente: symlink só é (re)criado se ainda não apontar para o alvo correto.
#
# TODO-VERIFICAR: `opencode --help` (adapters/opencode/DISCOVERY.md) não documenta
# convenção de diretório de plugin/config de projeto (ex.: se é `.opencode/` na raiz
# do repo ou `$HOME/.config/opencode/`). Até confirmar via smoke test real,
# este script só cria `.opencode/` local no repo, que é o padrão mais comum
# documentado em `AGENTS.md` de projetos opencode — não confirmado no DISCOVERY.md.

set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"
DEST_DIR="$REPO_ROOT/.opencode"

echo "🔧 install.sh (opencode) — destino: $DEST_DIR"

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

install_link "$ADAPTER_DIR/plugin.sh" "$DEST_DIR/plugin.sh"
install_link "$ADAPTER_DIR/AGENTS.md" "$DEST_DIR/AGENTS.md"

echo "✅ install.sh (opencode) concluído (dry_run=$DRY_RUN)"
