#!/bin/bash
# poll-status.sh — Verifica status de uma task despachada em background
# Uso: bin/poll-status.sh <task_name>
# Env obrigatória: LOG_DIR, PID_DIR

set -euo pipefail

: "${LOG_DIR:?Erro: env LOG_DIR não definida. Defina o diretório onde logs de dispatch são gravados.}"
: "${PID_DIR:?Erro: env PID_DIR não definida. Defina o diretório onde PID files são gravados.}"

TASK_NAME="${1:?Uso: poll-status.sh <task_name>}"
LOG_FILE="$LOG_DIR/dispatch-${TASK_NAME}.log"
PID_FILE="$PID_DIR/dispatch-${TASK_NAME}.pid"

if [ ! -f "$LOG_FILE" ]; then
  echo "❌ Task não encontrada: $TASK_NAME"
  echo "   Log esperado: $LOG_FILE"
  exit 1
fi

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" 2>/dev/null; then
    echo "⏳ RODANDO (PID: $PID)"
    echo "   Últimas linhas:"
    tail -5 "$LOG_FILE" | sed 's/^/   /'
    exit 0
  else
    echo "✅ TERMINOU (PID: $PID não está mais ativo)"
  fi
else
  echo "ℹ️  Sem PID file (task pode ter terminado)"
fi

echo ""
echo "📋 Resultado (últimas 20 linhas):"
tail -20 "$LOG_FILE" | sed 's/^/   /'

if grep -qi "commit\|DONE\|Feito\|Concluído" "$LOG_FILE"; then
  echo ""
  echo "✅ Sucesso detectado no output"
elif grep -qi "error\|FAIL\|failed" "$LOG_FILE"; then
  echo ""
  echo "⚠️  Possível falha — verificar log completo: $LOG_FILE"
fi
