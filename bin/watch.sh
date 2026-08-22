#!/bin/bash
# watch.sh — Acompanhar dispatches em background
# Uso: bin/watch.sh (sem args = lista) | bin/watch.sh <task_name> (tail -f do log)
# Read-only, exit 0 sempre.
# Env obrigatória: LOG_DIR, PID_DIR

: "${LOG_DIR:?Erro: env LOG_DIR não definida. Defina o diretório onde logs de dispatch são gravados.}"
: "${PID_DIR:?Erro: env PID_DIR não definida. Defina o diretório onde PID files são gravados.}"

TASK_NAME="${1:-}"

if [ -z "$TASK_NAME" ]; then
  for pid_file in "$PID_DIR"/dispatch-*.pid; do
    [ -f "$pid_file" ] || continue
    task="${pid_file#"$PID_DIR"/dispatch-}"
    task="${task%.pid}"
    log_file="$LOG_DIR/dispatch-${task}.log"
    pid=$(cat "$pid_file" 2>/dev/null)
    status="TERMINOU"
    kill -0 "$pid" 2>/dev/null && status="RODANDO"
    size=$(wc -c < "$log_file" 2>/dev/null || echo 0)
    last_line=$(tail -1 "$log_file" 2>/dev/null | sed $'s/\033\\[[0-9;]*m//g' | grep -v '^[[:space:]]*$' | head -1)
    [ -z "$last_line" ] && last_line="(vazio)"
    printf "%-30s %-10s %8s B  %s\n" "$task" "$status" "$size" "$last_line"
  done
  exit 0
fi

log_file="$LOG_DIR/dispatch-${TASK_NAME}.log"
if [ ! -f "$log_file" ]; then
  echo "Log não encontrado: $log_file"
  exit 0
fi

tail -f "$log_file" | sed $'s/\033\\[[0-9;]*m//g'
