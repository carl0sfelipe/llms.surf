#!/bin/bash
# env.sh — configuração de ambiente para o adapter cursor (cursor-agent)
# Uso: source adapters/cursor/env.sh

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="cursor"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=1
export ORACFIT_ROOT="${ORACFIT_ROOT:-$REPO_ROOT}"
export DISPATCH_ROOT="${DISPATCH_ROOT:-$ORACFIT_ROOT}"

# Preferir cursor-agent no PATH; fallback para Cursor.app
if command -v cursor-agent >/dev/null 2>&1; then
  export CURSOR_AGENT_BIN="${CURSOR_AGENT_BIN:-cursor-agent}"
elif [ -x "/Applications/Cursor.app/Contents/Resources/app/bin/cursor" ]; then
  export CURSOR_AGENT_BIN="${CURSOR_AGENT_BIN:-/Applications/Cursor.app/Contents/Resources/app/bin/cursor}"
  export CURSOR_AGENT_SUBCOMMAND=agent
fi

mkdir -p "$LOG_DIR" "$PID_DIR"
