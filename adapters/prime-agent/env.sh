#!/bin/bash
# env.sh — configuração de ambiente para o adapter prime-agent
# Uso: source adapters/prime-agent/env.sh
#
# Paths verificados em adapters/prime-agent/DISCOVERY.md (Passo 0):
# binário em ~/.local/bin/prime-agent (installer oficial, v0.7.2).

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="prime-agent"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"

# ~/.local/bin pode não estar no PATH de shells não-interativos
case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac

mkdir -p "$LOG_DIR" "$PID_DIR"
