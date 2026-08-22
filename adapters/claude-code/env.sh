#!/bin/bash
# env.sh — configuração de ambiente para o adapter claude-code
# Uso: source adapters/claude-code/env.sh
#
# TODO-VERIFICAR: claude CLI não expõe um DB sqlite de sessões (diferente de
# opencode) — `find $HOME/.claude -iname '*.db'` não encontrou nada; sessões
# ficam em `$HOME/.claude/projects/*.jsonl`. DB_PATH abaixo aponta para esse
# diretório só para não deixar a env vazia; scripts em bin/ que fazem query
# sqlite (bin/new-session.sh, bin/attach.sh) degradam para "?" nas métricas
# quando o arquivo não é um DB válido — comportamento já previsto nesses scripts,
# não uma nova degradação silenciosa deste adapter.

ADAPTER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
REPO_ROOT="$(cd "$ADAPTER_DIR/../.." && pwd)"

export DISPATCH_RUNNER="$ADAPTER_DIR/runner.sh"
export DISPATCH_RUNNER_NAME="claude-code"
export DB_PATH="$HOME/.claude/projects"
export LOG_DIR="$REPO_ROOT/.dispatch/logs"
export PID_DIR="$REPO_ROOT/.dispatch/pids"
export MODEL_REGISTRY="$REPO_ROOT/model-registry.json"
export CAPABILITIES_FILE="$ADAPTER_DIR/capabilities.env"
export DISPATCH_RUNNER_FORMAT_JSON=1

mkdir -p "$LOG_DIR" "$PID_DIR"
