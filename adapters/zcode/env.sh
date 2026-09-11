#!/bin/bash
# env.sh — configuração de ambiente para o adapter zcode
# Uso: source adapters/zcode/env.sh

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="zcode"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=1
export ORACFIT_ROOT="${ORACFIT_ROOT:-$REPO_ROOT}"
export DISPATCH_ROOT="${DISPATCH_ROOT:-$ORACFIT_ROOT}"

# Garante zcode no PATH.
# macOS: App bundle → symlink em ~/.local/bin.
# Linux: wrapper/AppImage vive em ~/.local/bin — só adiciona ao PATH (nada de
# symlink para caminho inexistente).
if ! command -v zcode >/dev/null 2>&1; then
  case "$(uname -s)" in
    Darwin)
      ZCODE_APP="/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs"
      if [ -f "$ZCODE_APP" ]; then
        mkdir -p "$HOME/.local/bin"
        ln -sfn "$ZCODE_APP" "$HOME/.local/bin/zcode"
      fi
      ;;
    Linux)
      if [ -x "$HOME/.local/bin/zcode" ]; then
        export PATH="$HOME/.local/bin:$PATH"
      fi
      ;;
  esac
fi

export ZCODE_BIN="${ZCODE_BIN:-zcode}"
export ZCODE_CLI_CONFIG="${ZCODE_CLI_CONFIG:-$HOME/.zcode/cli/config.json}"

mkdir -p "$LOG_DIR" "$PID_DIR"
