#!/bin/bash
# emit-usage-feedback.sh — telemetria + incidente de uso automático
# (mapa C / incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md)
#
# Enquanto DISPATCH_USAGE_FEEDBACK≠0 (default: ligado), todo modo de dispatch
# chama este script ao terminar. Coleta o máximo de evidência possível e grava:
#   1. .dispatch/usage/usage.jsonl          (máquina)
#   2. incidents/uso/<id>.md               (humano / promoção futura)
#
# Uso NÃO depende de humano pedir feedback. Desligar: DISPATCH_USAGE_FEEDBACK=0
#
# Uso:
#   bin/emit-usage-feedback.sh \
#     --source escalate|batch|dispatch \
#     --task NAME --result RESULT \
#     [--mode N] [--workdir DIR] [--spec PATH] [--oracle CMD] \
#     [--exit-code N] [--extra-json '{...}']

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Default LIGADO durante desenvolvimento do harness. Produção madura: export 0.
if [ "${DISPATCH_USAGE_FEEDBACK:-1}" = "0" ]; then
  exit 0
fi

SOURCE=""
TASK=""
RESULT=""
MODE=""
WORKDIR=""
SPEC=""
ORACLE=""
EXIT_CODE=""
EXTRA_JSON="{}"

while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE="${2:?}"; shift 2 ;;
    --task) TASK="${2:?}"; shift 2 ;;
    --result) RESULT="${2:?}"; shift 2 ;;
    --mode) MODE="${2:?}"; shift 2 ;;
    --workdir) WORKDIR="${2:?}"; shift 2 ;;
    --spec) SPEC="${2:?}"; shift 2 ;;
    --oracle) ORACLE="${2:?}"; shift 2 ;;
    --exit-code) EXIT_CODE="${2:?}"; shift 2 ;;
    --extra-json) EXTRA_JSON="${2:?}"; shift 2 ;;
    *) echo "emit-usage-feedback: flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

[ -n "$SOURCE" ] || { echo "emit-usage-feedback: --source obrigatório" >&2; exit 3; }
[ -n "$TASK" ] || { echo "emit-usage-feedback: --task obrigatório" >&2; exit 3; }
[ -n "$RESULT" ] || { echo "emit-usage-feedback: --result obrigatório" >&2; exit 3; }

LOG_DIR="${LOG_DIR:-$REPO_ROOT/.dispatch/logs}"
USAGE_DIR="$REPO_ROOT/.dispatch/usage"
USO_DIR="$REPO_ROOT/incidents/uso"
mkdir -p "$USAGE_DIR" "$USO_DIR" "$LOG_DIR"

TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
DATE_LOCAL=$(date +"%Y-%m-%d")
TIME_LOCAL=$(date +"%H%M%S")
HOST=$(hostname -s 2>/dev/null || hostname)
USER_NAME=$(whoami 2>/dev/null || echo "?")
UNAME=$(uname -srm 2>/dev/null || echo "?")
PWD_NOW=$(pwd)

# Harness detector — Cursor / Claude Code / OpenCode / shell puro
HARNESS="shell"
[ -n "${CURSOR_TRACE_ID:-}" ] || [ -n "${CURSOR_AGENT:-}" ] || [ -n "${CURSOR_SESSION_ID:-}" ] && HARNESS="cursor"
[ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_ENTRYPOINT:-}" ] && HARNESS="claude-code"
[ -n "${OPENCODE_DIR:-}" ] && HARNESS="opencode"
[ -n "${TERM_PROGRAM:-}" ] && TERM_PROG="$TERM_PROGRAM" || TERM_PROG=""

GIT_HEAD=""
GIT_BRANCH=""
GIT_DIRTY=""
if [ -n "$WORKDIR" ] && git -C "$WORKDIR" rev-parse --git-dir >/dev/null 2>&1; then
  GIT_HEAD=$(git -C "$WORKDIR" rev-parse --short HEAD 2>/dev/null || true)
  GIT_BRANCH=$(git -C "$WORKDIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
  if [ -n "$(git -C "$WORKDIR" status --porcelain 2>/dev/null)" ]; then
    GIT_DIRTY="sim"
  else
    GIT_DIRTY="nao"
  fi
fi

SPEC_SHA=""
SPEC_BYTES=0
SPEC_HEAD=""
if [ -n "$SPEC" ] && [ -f "$SPEC" ]; then
  SPEC_BYTES=$(wc -c < "$SPEC" | tr -d ' ')
  SPEC_SHA=$(shasum -a 256 "$SPEC" 2>/dev/null | awk '{print $1}')
  SPEC_HEAD=$(head -40 "$SPEC" 2>/dev/null | sed 's/`/\\`/g')
fi

# Logs da task: paths, tamanhos, cauda do mais recente
LOG_INDEX=""
LATEST_LOG=""
LATEST_MTIME=0
for f in "$LOG_DIR"/${TASK}-*.log "$LOG_DIR"/dispatch-${TASK}.log; do
  [ -f "$f" ] || continue
  sz=$(wc -c < "$f" | tr -d ' ')
  mt=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)
  LOG_INDEX="${LOG_INDEX}${f}|${sz};"
  if [ "$mt" -ge "$LATEST_MTIME" ]; then
    LATEST_MTIME=$mt
    LATEST_LOG=$f
  fi
done

LOG_TAIL=""
if [ -n "$LATEST_LOG" ]; then
  LOG_TAIL=$(tail -40 "$LATEST_LOG" 2>/dev/null | sed 's/"/\\"/g' | tr '\n' '↵' | head -c 4000)
fi

# Env DISPATCH_* (sem secrets óbvios)
DISPATCH_ENV=""
while IFS='=' read -r k v; do
  case "$k" in
    *KEY*|*TOKEN*|*SECRET*|*PASSWORD*|*AUTH*) continue ;;
  esac
  DISPATCH_ENV="${DISPATCH_ENV}${k}=${v};"
done < <(env | grep '^DISPATCH_' | sort || true)

# Última linha do ledger escalate/batch se existir
LEDGER_TAIL=""
for lf in "$LOG_DIR/escalate-ledger.jsonl" "$LOG_DIR/batch-ledger.jsonl" "$REPO_ROOT/ledger/ledger.jsonl"; do
  [ -f "$lf" ] || continue
  line=$(grep -F "\"$TASK\"" "$lf" 2>/dev/null | tail -1 || true)
  [ -z "$line" ] && line=$(tail -1 "$lf" 2>/dev/null || true)
  [ -n "$line" ] && LEDGER_TAIL="${LEDGER_TAIL}${lf}: ${line}"$'\n'
done

# Escape mínimo para JSON
json_esc() {
  printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])' 2>/dev/null \
    || printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g' | tr '\n' ' '
}

TASK_ESC=$(json_esc "$TASK")
RESULT_ESC=$(json_esc "$RESULT")
SOURCE_ESC=$(json_esc "$SOURCE")
ORACLE_ESC=$(json_esc "${ORACLE:-}")
WORKDIR_ESC=$(json_esc "${WORKDIR:-}")
SPEC_ESC=$(json_esc "${SPEC:-}")
HARNESS_ESC=$(json_esc "$HARNESS")
LOG_INDEX_ESC=$(json_esc "$LOG_INDEX")
LOG_TAIL_ESC=$(json_esc "$LOG_TAIL")
DISPATCH_ENV_ESC=$(json_esc "$DISPATCH_ENV")
EXTRA_ESC=$(json_esc "$EXTRA_JSON")

JSON_LINE=$(printf '{"ts":"%s","source":"%s","task":"%s","result":"%s","mode":%s,"exit_code":%s,"workdir":"%s","spec":"%s","spec_sha256":"%s","spec_bytes":%s,"oracle":"%s","host":"%s","user":"%s","uname":"%s","pwd":"%s","harness":"%s","term_program":"%s","git_head":"%s","git_branch":"%s","git_dirty":"%s","logs":"%s","log_tail":"%s","dispatch_env":"%s","extra":%s}\n' \
  "$TS" "$SOURCE_ESC" "$TASK_ESC" "$RESULT_ESC" \
  "${MODE:-null}" \
  "${EXIT_CODE:-null}" \
  "$WORKDIR_ESC" "$SPEC_ESC" "${SPEC_SHA:-}" "${SPEC_BYTES:-0}" \
  "$ORACLE_ESC" \
  "$(json_esc "$HOST")" "$(json_esc "$USER_NAME")" "$(json_esc "$UNAME")" "$(json_esc "$PWD_NOW")" \
  "$HARNESS_ESC" "$(json_esc "$TERM_PROG")" \
  "$(json_esc "$GIT_HEAD")" "$(json_esc "$GIT_BRANCH")" "$(json_esc "$GIT_DIRTY")" \
  "$LOG_INDEX_ESC" "$LOG_TAIL_ESC" "$DISPATCH_ENV_ESC" \
  "${EXTRA_JSON}")

printf '%s\n' "$JSON_LINE" >> "$USAGE_DIR/usage.jsonl"

# Slug curto do task
SLUG=$(printf '%s' "$TASK" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g' | cut -c1-40)
ID="${DATE_LOCAL}-${SLUG}-${TIME_LOCAL}"
INC_FILE="$USO_DIR/${ID}.md"

# Candidatos a observação (heurísticas leves — promoção continua humana)
OBS=()
case "$RESULT" in
  success|already-passing)
    OBS+=("Run concluiu sem bloqueio — útil como baseline positivo do modo ${MODE:-?}.")
    ;;
  blocked)
    OBS+=("Todos os tiers falharam — candidato a bug de oráculo, spec ambígua, ou task mal classificada (regra 40).")
    ;;
  timeout)
    OBS+=("Estourou teto — revisar DISPATCH_TIMEOUT / silent limit / oráculo lento.")
    ;;
  failed)
    OBS+=("Escalate exit≠0 — cruzar log_tail com assinatura do oráculo.")
    ;;
esac
[ "$HARNESS" = "cursor" ] && OBS+=("Origem Cursor — feedback de integração CLI↔agente (como o incidente forçado de 2026-07-30).")
[ "$GIT_DIRTY" = "sim" ] && OBS+=("Workdir dirty no fim — risco de misturar mudanças do modelo com estado prévio.")
[ -z "$LATEST_LOG" ] && OBS+=("Nenhum log da task em LOG_DIR — sensor cego parcial.")

{
  cat <<EOF
---
id: $ID
titulo: uso-dispatch $SOURCE/$TASK → $RESULT
data: $DATE_LOCAL
kind: uso-dispatch
source: $SOURCE
recorrivel: nao
regra: nao - telemetria automatica (incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md)
status: uso-auto
task: $TASK
result: $RESULT
mode: ${MODE:-}
harness: $HARNESS
---

# Uso automático: \`$SOURCE\` / \`$TASK\` → \`$RESULT\`

Gerado por \`bin/emit-usage-feedback.sh\` (incidents/2026-07-30-feedback-de-uso-forcado-por-humano.md). **Não** foi pedido por humano —
o harness coletou ao terminar o dispatch. Promova só se a evidência revelar padrão recorrente.

## Contexto

| Campo | Valor |
|---|---|
| ts (UTC) | $TS |
| source | \`$SOURCE\` |
| task | \`$TASK\` |
| result | \`$RESULT\` |
| mode | ${MODE:-—} |
| exit_code | ${EXIT_CODE:-—} |
| harness | \`$HARNESS\` |
| host/user | \`$HOST\` / \`$USER_NAME\` |
| workdir | \`${WORKDIR:-—}\` |
| git | \`${GIT_BRANCH:-—}@${GIT_HEAD:-—}\` dirty=\`${GIT_DIRTY:-—}\` |
| spec | \`${SPEC:-—}\` (${SPEC_BYTES} bytes, sha256=\`${SPEC_SHA:-—}\`) |
| oracle | \`${ORACLE:-—}\` |
| latest_log | \`${LATEST_LOG:-—}\` |

## Env DISPATCH_* (sem secrets)

\`\`\`
$DISPATCH_ENV
\`\`\`

## Ledger (linhas relevantes)

\`\`\`
$LEDGER_TAIL
\`\`\`

## Spec (head)

\`\`\`
$SPEC_HEAD
\`\`\`

## Log (tail do mais recente)

\`\`\`
$( [ -n "$LATEST_LOG" ] && tail -40 "$LATEST_LOG" 2>/dev/null || echo "(sem log)" )
\`\`\`

## Observações candidatas (julgamento humano / orquestrador)

EOF
  for o in "${OBS[@]}"; do
    echo "- $o"
  done
  cat <<EOF

## Próximo passo

1. Se for ruído: ignore (já está \`recorrivel: nao\` — não gera dívida no audit).
2. Se revelar padrão: copie evidência para \`bin/incident.sh new\` no topo de \`incidents/\` e promova.
3. Telemetria máquina: \`.dispatch/usage/usage.jsonl\`

EOF
} > "$INC_FILE"

echo "📡 usage-feedback: $USAGE_DIR/usage.jsonl + $INC_FILE" >&2
exit 0
