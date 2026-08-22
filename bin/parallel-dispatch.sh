#!/bin/bash
# parallel-dispatch.sh — Sequencia forks de uma sessão base
# Uso: bin/parallel-dispatch.sh <base_session_id> <tasks_file> <model_id>
# Tasks file: 1 spec por linha (ou caminho para arquivo .md por linha)
# Git sequencial: fork A termina → valida → fork B começa
# Env obrigatória: DISPATCH_RUNNER, LOG_DIR
#
# Interface do runner (core/runner-contract.md): $DISPATCH_RUNNER <model_id> <spec_file> [--session ID] [--fork]

set -uo pipefail

: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Aponte para adapters/<cli>/runner.sh.}"
: "${LOG_DIR:?Erro: env LOG_DIR não definida. Defina o diretório onde logs de fork são gravados.}"

BASE_SESSION="${1:?Uso: parallel-dispatch.sh <base_session_id> <tasks_file> <model_id>}"
TASKS_FILE="${2:?Uso: parallel-dispatch.sh <base_session_id> <tasks_file> <model_id>}"
MODEL="${3:?Uso: parallel-dispatch.sh <base_session_id> <tasks_file> <model_id> — model_id do model-registry.json, sem default}"

mkdir -p "$LOG_DIR"

if [ ! -f "$TASKS_FILE" ]; then
  echo "❌ Tasks file não encontrado: $TASKS_FILE"
  exit 3
fi

TOTAL=$(wc -l < "$TASKS_FILE" | tr -d ' ')
echo "═══ Parallel Fork Dispatch ═══"
echo "  Base: $BASE_SESSION"
echo "  Modelo: $MODEL"
echo "  Tasks: $TOTAL"
echo ""

N=0
while IFS= read -r task; do
  [ -z "$task" ] && continue
  N=$((N + 1))
  TS=$(date +%s)
  LOG_FILE="$LOG_DIR/fork-${N}-${TS}.log"

  echo "[$N/$TOTAL] Despachando fork..."
  echo "  Task: ${task:0:80}..."
  echo "  Log: $LOG_FILE"

  if [ -f "$task" ]; then
    SPEC_FILE="$task"
  else
    SPEC_FILE=$(mktemp)
    printf '%s' "$task" > "$SPEC_FILE"
  fi

  "$DISPATCH_RUNNER" "$MODEL" "$SPEC_FILE" --session "$BASE_SESSION" --fork > "$LOG_FILE" 2>&1
  EXIT_CODE=$?

  if [ $EXIT_CODE -ne 0 ]; then
    echo "  ❌ Fork $N falhou (exit $EXIT_CODE)"
    echo "  ABORTANDO fila — verificar: $LOG_FILE"
    tail -5 "$LOG_FILE" | sed 's/^/  /'
    exit 1
  fi

  if ! git diff --quiet 2>/dev/null; then
    echo "  ⚠️  Uncommitted changes após fork $N — commit necessário antes do próximo"
    git status --short | head -5 | sed 's/^/  /'
    echo "  ABORTANDO — commit ou stash antes de continuar"
    exit 1
  fi

  echo "  ✅ Fork $N OK"
  echo ""
done < "$TASKS_FILE"

echo "═══ Todos os $N forks completaram ═══"
echo "Logs: $LOG_DIR/fork-*.log"
