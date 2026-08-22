#!/bin/bash
# attach.sh — Anexa TUI interativa na sessão de um worker
# Uso: bin/attach.sh <task_name> [--dry-run]
# Resolve session_id via timestamp do PID file e abre a TUI do CLI ativo.
#
# Env obrigatória: DISPATCH_RUNNER (binário base do CLI, ex: "opencode" — não o runner.sh
#   de dispatch; attach TUI ainda não faz parte do contrato runner.sh, ver core/runner-contract.md),
#   DB_PATH, PID_DIR
#
# NOTA: attach interativo não está no contrato runner.sh (seção 4.2 do PRD só cobre
# dispatch, não TUI). Depende de adapters/<cli>/capabilities.env declarar ATTACH_TUI=1
# — capacidade ausente sai com exit 3 (seção 4.5 do PRD: nunca degrada em silêncio).

set -euo pipefail

: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida.}"
: "${DB_PATH:?Erro: env DB_PATH não definida. Caminho do banco de sessões do CLI ativo.}"
: "${PID_DIR:?Erro: env PID_DIR não definida. Defina o diretório onde PID files são gravados.}"

if [ -n "${CAPABILITIES_FILE:-}" ]; then
  if [ -f "$CAPABILITIES_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CAPABILITIES_FILE"
    if [ "${ATTACH_TUI:-0}" != "1" ]; then
      echo "❌ Erro: adapter ativo (${DISPATCH_RUNNER_NAME:-?}) não declara ATTACH_TUI=1 em $CAPABILITIES_FILE — attach.sh não suportado neste CLI." >&2
      exit 3
    fi
  else
    echo "❌ Erro: CAPABILITIES_FILE definido mas não encontrado: $CAPABILITIES_FILE" >&2
    exit 3
  fi
fi

TASK_NAME="${1:?Uso: attach.sh <task_name> [--dry-run]}"
DRY_RUN="${2:-}"
PID_FILE="$PID_DIR/dispatch-${TASK_NAME}.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "PID file não encontrado: $PID_FILE"
  exit 1
fi

if [ ! -f "$DB_PATH" ]; then
  echo "DB não encontrado: $DB_PATH"
  exit 1
fi

if [[ "$(uname)" == "Darwin" ]]; then
  TS_SECS=$(stat -f "%B" "$PID_FILE")
else
  TS_SECS=$(stat -c "%Y" "$PID_FILE")
fi
TS_MS=$((TS_SECS * 1000))

i=0
while IFS='|' read -r id title dir ts; do
  S_IDS[$i]="$id"
  S_TITLES[$i]="$title"
  S_DIRS[$i]="$dir"
  S_TS[$i]="$ts"
  i=$((i + 1))
done < <(sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT id, coalesce(title, ''), coalesce(directory, ''), time_created
FROM session
WHERE time_created >= $TS_MS
ORDER BY time_created ASC
LIMIT 5;
")
COUNT=$i

if [ "$COUNT" -eq 0 ]; then
  echo "Nenhuma sessão encontrada a partir do timestamp $(date -r "$TS_SECS" '+%Y-%m-%dT%H:%M:%S' 2>/dev/null || echo "$TS_SECS")"
  exit 1
fi

SELECTED=0
if [ "$COUNT" -gt 1 ]; then
  echo "Múltiplas sessões encontradas após o timestamp do PID. Escolha:"
  for j in $(seq 0 $((COUNT - 1))); do
    echo "  $((j + 1)). ${S_IDS[$j]}  ${S_TITLES[$j]}  (${S_DIRS[$j]})"
  done
  echo ""
  read -p "Número [1]: " CHOICE
  SELECTED=$((${CHOICE:-1} - 1))
fi

SESSION_ID="${S_IDS[$SELECTED]}"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null)
  if kill -0 "$PID" 2>/dev/null; then
    echo "⚠️  Worker ainda está executando (PID: $PID); anexar abre a mesma sessão — mensagens novas entram na fila"
  fi
fi

CMD=("$DISPATCH_RUNNER" -s "$SESSION_ID")
if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "Session ID: $SESSION_ID"
  echo "Comando: ${CMD[*]}"
  exit 0
fi

exec "${CMD[@]}"
