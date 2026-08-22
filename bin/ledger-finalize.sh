#!/bin/bash
# ledger-finalize.sh — Finalizador de ledger para dispatches background
# Uso: nohup bash bin/ledger-finalize.sh <task_name> &
# Chamado automaticamente por dispatch.sh. Nao executar manualmente.
#
# Env obrigatória: DB_PATH, LOG_DIR, PID_DIR
# Env opcional: DISPATCH_RUNNER_NAME (RF-07 — nome do CLI que despachou, grava campo
#   "runner" no ledger, retrocompatível pois é opcional), DISPATCH_LOCK_FILE (removido
#   ao final, ver RNF-07 em bin/dispatch.sh)

set -euo pipefail

: "${DB_PATH:?Erro: env DB_PATH não definida. Caminho do banco de sessões do CLI ativo.}"
: "${LOG_DIR:?Erro: env LOG_DIR não definida.}"
: "${PID_DIR:?Erro: env PID_DIR não definida.}"

TASK_NAME="${1:?Uso: ledger-finalize.sh <task_name>}"
META_FILE="$PID_DIR/dispatch-${TASK_NAME}.meta"
PID_FILE="$PID_DIR/dispatch-${TASK_NAME}.pid"
LOG_FILE="$LOG_DIR/dispatch-${TASK_NAME}.log"
LEDGER_DIR="$(cd "$(dirname "$0")/.." && pwd)/ledger"
LEDGER_FILE="$LEDGER_DIR/ledger.jsonl"

[ -f "$META_FILE" ] || exit 0
source "$META_FILE"

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [ -n "$PID" ]; then
    while kill -0 "$PID" 2>/dev/null; do
      sleep 3
    done
  fi
fi

# runner_exit — exit code REAL do runner, não "log não vazio" (esse proxy
# registrou "ok" para o dispatch d-07, que alucinou e não fez nada — ver
# plan_dispatch_2.0_fixed.md). dispatch.sh escreve este arquivo depois que o
# runner termina; se o watchdog matou o grupo antes, o arquivo nunca aparece.
EXIT_FILE="$PID_DIR/dispatch-${TASK_NAME}.exit"
if [ -f "$EXIT_FILE" ]; then
  RUNNER_EXIT=$(cat "$EXIT_FILE" 2>/dev/null || echo "")
  [ -n "$RUNNER_EXIT" ] || RUNNER_EXIT="unknown"
else
  RUNNER_EXIT="killed"
fi

# oracle_exit — resultado do comando declarado na seção ## Oráculo do spec,
# rodado DEPOIS que o runner terminou. Sem isto, "modelo despachado" e "modelo
# que resolveu" são a mesma linha no ledger; com isto, viram duas.
BIN_DIR="$(cd "$(dirname "$0")" && pwd)"
ORACULO_CMD=""
ORACULO_EXPECT="0"
if [ -f "$SPEC_FILE" ] && grep -qiE '^#{1,6}[[:space:]]*or(a|á)culo' "$SPEC_FILE"; then
  ORACULO_CMD=$(grep -iE '^[-*][[:space:]]*comando:' "$SPEC_FILE" | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//' | sed -E 's/^`(.*)`$/\1/')
  LINHA_EXPECT=$(grep -iE '^[-*][[:space:]]*exit esperado:' "$SPEC_FILE" | head -1)
  if [ -n "$LINHA_EXPECT" ]; then
    ORACULO_EXPECT=$(echo "$LINHA_EXPECT" | grep -oE '[0-9]+' | head -1)
    [ -n "$ORACULO_EXPECT" ] || ORACULO_EXPECT="0"
  fi
fi

if [ -n "$ORACULO_CMD" ]; then
  # set +e: o comando do oráculo pode legitimamente sair não-zero (ex.:
  # check-dup-kit.sh reporta duplicata pendente) — isso é DADO, não erro do
  # script. set -e mataria o finalizador no primeiro oráculo "esperado falhar".
  set +e
  bash "$BIN_DIR/run-check.sh" --quiet bash -c "$ORACULO_CMD" >/dev/null 2>&1
  ORACLE_EXIT=$?
  set -e
  if [ "$ORACLE_EXIT" = "$ORACULO_EXPECT" ]; then
    ORACLE_STATUS="passou"
  else
    ORACLE_STATUS="falhou"
  fi
else
  ORACLE_EXIT="null"
  ORACLE_STATUS="sem-oraculo"
fi

# EXIT_STATUS mantido só por compatibilidade com leitores antigos do ledger;
# runner_exit e oracle_exit são os campos que decidem algo de verdade agora.
EXIT_STATUS="ok"
if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
  EXIT_STATUS="unknown"
fi

SESSION_ID=""
TOKENS_INPUT=0; TOKENS_OUTPUT=0; TOKENS_REASONING=0
TOKENS_CACHE_READ=0; TOKENS_CACHE_WRITE=0
COST_USD=0; MODEL_ID=""; PROVIDER_ID=""

if [ -f "$DB_PATH" ]; then
  SESSION_ID=$(sqlite3 "file:${DB_PATH}?mode=ro" "
    SELECT id FROM session
    WHERE time_created >= $((STARTED_AT * 1000))
    ORDER BY time_created ASC LIMIT 1;
  " 2>/dev/null || true)

  if [ -n "$SESSION_ID" ]; then
    IFS='|' read -r TOKENS_INPUT TOKENS_OUTPUT TOKENS_REASONING \
      TOKENS_CACHE_READ TOKENS_CACHE_WRITE COST_USD MODEL_ID PROVIDER_ID < <(
      sqlite3 "file:${DB_PATH}?mode=ro" "
        SELECT tokens_input, tokens_output, tokens_reasoning,
               tokens_cache_read, tokens_cache_write,
               cost, json_extract(model,'$.id'), json_extract(model,'$.providerID')
        FROM session WHERE id = '$SESSION_ID';
      " 2>/dev/null || echo "0|0|0|0|0|0||"
    )

    FORKS=$(sqlite3 "file:${DB_PATH}?mode=ro" "
      SELECT id FROM session WHERE parent_id = '$SESSION_ID' ORDER BY time_created ASC;
    " 2>/dev/null || true)
  fi
fi

FINISHED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
STARTED_AT_ISO=$(date -u -r "$STARTED_AT" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d "@$STARTED_AT" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "$FINISHED_AT")
DURATION=$(( $(date +%s) - STARTED_AT ))
LOG_LINES=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
LOG_LINES=$((LOG_LINES))

[ -z "$MODEL_ID" ] && MODEL_ID="$MODEL"

mkdir -p "$LEDGER_DIR"

export TASK_NAME SPEC_FILE MODEL_ID PROVIDER_ID SESSION_ID
export STARTED_AT_ISO FINISHED_AT DURATION EXIT_STATUS
export TOKENS_INPUT TOKENS_OUTPUT TOKENS_REASONING TOKENS_CACHE_READ TOKENS_CACHE_WRITE COST_USD LOG_LINES LOG_FILE LEDGER_FILE FORKS
export RUNNER_NAME="${DISPATCH_RUNNER_NAME:-}"
export RUNNER_EXIT ORACLE_EXIT ORACLE_EXPECT="$ORACULO_EXPECT" ORACLE_STATUS ORACLE_CMD="$ORACULO_CMD"

python3 -c '
import json, os

forks_raw = os.environ.get("FORKS", "")
session_ids_forks = [f for f in forks_raw.split("\n") if f]

record = {
    "task_name": os.environ["TASK_NAME"],
    "spec_file": os.environ["SPEC_FILE"],
    "model": {
        "id": os.environ.get("MODEL_ID", ""),
        "providerID": os.environ.get("PROVIDER_ID", "")
    },
    "session_id": os.environ.get("SESSION_ID", ""),
    "session_ids_forks": session_ids_forks,
    "started_at": os.environ["STARTED_AT_ISO"],
    "finished_at": os.environ["FINISHED_AT"],
    "duration_seconds": int(os.environ["DURATION"]),
    "exit_status": os.environ["EXIT_STATUS"],
    "tokens_input": int(os.environ.get("TOKENS_INPUT", 0)),
    "tokens_output": int(os.environ.get("TOKENS_OUTPUT", 0)),
    "tokens_reasoning": int(os.environ.get("TOKENS_REASONING", 0)),
    "tokens_cache_read": int(os.environ.get("TOKENS_CACHE_READ", 0)),
    "tokens_cache_write": int(os.environ.get("TOKENS_CACHE_WRITE", 0)),
    "cost_usd": float(os.environ.get("COST_USD", 0) or 0),
    "log_lines": int(os.environ.get("LOG_LINES", 0)),
    "log_file": os.environ["LOG_FILE"],
    "quantization": "n/a — modelo cloud",
    "runner_exit": os.environ.get("RUNNER_EXIT", "unknown"),
    "oracle_exit": os.environ.get("ORACLE_EXIT", "null"),
    "oracle_expected": os.environ.get("ORACLE_EXPECT", ""),
    "oracle_status": os.environ.get("ORACLE_STATUS", "sem-oraculo"),
    "oracle_cmd": os.environ.get("ORACLE_CMD", "")
}

runner_name = os.environ.get("RUNNER_NAME", "")
if runner_name:
    record["runner"] = runner_name

with open(os.environ["LEDGER_FILE"], "a") as f:
    f.write(json.dumps(record, ensure_ascii=False) + "\n")
'

# Regra 41: telemetria + incidente de uso também no dispatch simples (background).
USAGE_RESULT="failed"
case "$ORACLE_STATUS" in
  passou) USAGE_RESULT="success" ;;
  sem-oraculo)
    case "$RUNNER_EXIT" in
      0) USAGE_RESULT="success" ;;
      killed) USAGE_RESULT="blocked" ;;
      *) USAGE_RESULT="failed" ;;
    esac
    ;;
  falhou) USAGE_RESULT="failed" ;;
esac
REPO_ROOT_FOR_USAGE="$(cd "$(dirname "$0")/.." && pwd)"
USAGE_ARGS=(
  --source dispatch
  --task "$TASK_NAME"
  --result "$USAGE_RESULT"
  --extra-json "{\"runner_exit\":\"$RUNNER_EXIT\",\"oracle_status\":\"$ORACLE_STATUS\",\"duration_s\":$DURATION,\"session_id\":\"${SESSION_ID:-}\"}"
)
[ -n "${SPEC_FILE:-}" ] && USAGE_ARGS+=(--spec "$SPEC_FILE")
[ -n "${ORACULO_CMD:-}" ] && USAGE_ARGS+=(--oracle "$ORACULO_CMD")
case "${RUNNER_EXIT:-}" in
  ''|unknown|killed) ;;
  *) USAGE_ARGS+=(--exit-code "$RUNNER_EXIT") ;;
esac
bash "$REPO_ROOT_FOR_USAGE/bin/emit-usage-feedback.sh" "${USAGE_ARGS[@]}" 2>/dev/null || true

rm -f "$META_FILE" "$EXIT_FILE"
[ -n "${DISPATCH_LOCK_FILE:-}" ] && rm -f "$DISPATCH_LOCK_FILE"

exit 0
