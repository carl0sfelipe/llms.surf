#!/bin/bash
# env.sh — configuração de ambiente para o adapter hermes
# Uso: source adapters/hermes/env.sh
#
# Paths verificados no Passo 0 (adapters/hermes/DISCOVERY.md):
#   binário  → $(command -v hermes) = ~/.local/bin/hermes
#   state.db → $HOME/.hermes/state.db (mesmo path lido por scripts/hermes-watch.sh:10)

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="hermes"
export DB_PATH="$HOME/.hermes/state.db"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export ORACFIT_ROOT="${ORACFIT_ROOT:-$REPO_ROOT}"
export DISPATCH_ROOT="${DISPATCH_ROOT:-$ORACFIT_ROOT}"

# capabilities.env declara FORMAT_JSON=0 — `hermes -z` imprime texto puro.
export DISPATCH_RUNNER_FORMAT_JSON=0

mkdir -p "$LOG_DIR" "$PID_DIR"
