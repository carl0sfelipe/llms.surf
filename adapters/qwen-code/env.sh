#!/bin/bash
# env.sh — configuração de ambiente para o adapter qwen-code
# Uso: source adapters/qwen-code/env.sh
#
# ⚠️ ADAPTER EXPERIMENTAL: a CLI `qwen` não existe neste host
# (adapters/qwen-code/DISCOVERY.md, Passo 0). O runner falha com exit 3 por
# design — ver QWEN.md para o caminho suportado hoje (via opencode).

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="qwen-code"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=0

# Estado do semáforo de token plan (RF-05.2)
export TOKEN_PLAN_STATE="$REPO_ROOT/.dispatch/qwen-token-plan.json"

# DB_PATH não é exportado: sem CLI, não há store de sessão conhecido.
# TODO-VERIFICAR no Passo 0 quando a CLI existir.

mkdir -p "$LOG_DIR" "$PID_DIR"
