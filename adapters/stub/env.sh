#!/bin/bash
# env.sh — configuração de ambiente para o adapter stub (smoke sem API key).
# Uso: source adapters/stub/env.sh
# Mesmo contrato dos adapters reais (zcode/opencode/…) para o dispatch da GUI
# (POST /api/dispatch valida adapters/*/env.sh) — o stub fica elegível no
# formulário, permitindo testar o caminho inteiro sem gastar token.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="stub"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export ORACFIT_ROOT="${ORACFIT_ROOT:-$REPO_ROOT}"
export DISPATCH_ROOT="${DISPATCH_ROOT:-$ORACFIT_ROOT}"

mkdir -p "$LOG_DIR" "$PID_DIR"
