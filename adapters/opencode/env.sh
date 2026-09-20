#!/bin/bash
# env.sh — configuração de ambiente para o adapter opencode
# Uso: source adapters/opencode/env.sh
#
# Paths verificados: `ls $HOME/.local/share/opencode/opencode.db` confirmado em
# adapters/opencode/DISCOVERY.md (Passo 0).

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="opencode"
export DB_PATH="$HOME/.local/share/opencode/opencode.db"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=1
export LLMS_KERNEL=shadow

mkdir -p "$LOG_DIR" "$PID_DIR"
