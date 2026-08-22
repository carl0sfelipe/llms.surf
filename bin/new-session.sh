#!/bin/bash
# new-session.sh — Cria sessão de mapeamento e devolve session_id (sem race condition)
# Uso: bin/new-session.sh <model_id> <map_spec_or_file>
# Output: session_id na última linha (para capturar com $())
#
# Env obrigatória: DISPATCH_RUNNER, DB_PATH
# Env opcional: DISPATCH_RUNNER_FORMAT_JSON=1 — se o runner ativo suportar `--format json`
#   (ver adapters/<cli>/capabilities.env). Sem essa flag, cai no fallback de
#   parse de texto com warning (RF-03.2 do PRD — sem COUNT+SELECT).
#   CAPABILITIES_FILE (setado pelo env.sh do adapter ativo) — se SESSION_REUSE=0
#   ali, sai com exit 3 (seção 4.5 do PRD: capacidade ausente nunca degrada em silêncio).

set -uo pipefail

: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Aponte para adapters/<cli>/runner.sh.}"
: "${DB_PATH:?Erro: env DB_PATH não definida. Caminho do banco de sessões do CLI ativo.}"

if [ -n "${CAPABILITIES_FILE:-}" ]; then
  if [ -f "$CAPABILITIES_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CAPABILITIES_FILE"
    if [ "${SESSION_REUSE:-0}" != "1" ]; then
      echo "❌ Erro: adapter ativo (${DISPATCH_RUNNER_NAME:-?}) não declara SESSION_REUSE=1 em $CAPABILITIES_FILE — new-session.sh requer essa capacidade." >&2
      exit 3
    fi
  else
    echo "❌ Erro: CAPABILITIES_FILE definido mas não encontrado: $CAPABILITIES_FILE" >&2
    exit 3
  fi
fi

MODEL="${1:?Uso: new-session.sh <model_id> <map_spec_or_file>}"
SPEC_INPUT="${2:?Uso: new-session.sh <model_id> <map_spec_or_file>}"

if [ -f "$SPEC_INPUT" ]; then
  SPEC_FILE="$SPEC_INPUT"
else
  SPEC_FILE="$(mktemp)"
  printf '%s' "$SPEC_INPUT" > "$SPEC_FILE"
fi

echo "🗺️  Criando sessão base de mapeamento..." >&2
echo "   Modelo: $MODEL" >&2

SESSION_ID=""

if [ "${DISPATCH_RUNNER_FORMAT_JSON:-0}" = "1" ]; then
  RAW_OUTPUT=$("$DISPATCH_RUNNER" "$MODEL" "$SPEC_FILE" --format json 2>&1)
  RUNNER_EXIT=$?
  if [ $RUNNER_EXIT -ne 0 ]; then
    echo "❌ Runner falhou (exit $RUNNER_EXIT)" >&2
    echo "$RAW_OUTPUT" >&2
    exit "$RUNNER_EXIT"
  fi
  SESSION_ID=$(echo "$RAW_OUTPUT" | python3 -c "
import json, sys
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        d = json.loads(line)
    except json.JSONDecodeError:
        continue
    sid = d.get('sessionID') or d.get('session_id') or d.get('id')
    if sid:
        print(sid)
        break
" 2>/dev/null)
  if [ -z "$SESSION_ID" ]; then
    echo "❌ Erro: --format json não retornou session_id reconhecível" >&2
    exit 3
  fi
else
  echo "⚠️  AVISO: DISPATCH_RUNNER_FORMAT_JSON não ativado — usando parse de texto (best-effort, sem garantia de precisão). Ver core/runner-contract.md." >&2
  RAW_OUTPUT=$("$DISPATCH_RUNNER" "$MODEL" "$SPEC_FILE" 2>&1)
  RUNNER_EXIT=$?
  echo "$RAW_OUTPUT" >&2
  if [ $RUNNER_EXIT -ne 0 ]; then
    echo "❌ Runner falhou (exit $RUNNER_EXIT)" >&2
    exit "$RUNNER_EXIT"
  fi
  SESSION_ID=$(echo "$RAW_OUTPUT" | grep -oE 'ses_[A-Za-z0-9]+' | tail -1)
  if [ -z "$SESSION_ID" ]; then
    echo "❌ Erro: não foi possível extrair session_id do output em modo texto" >&2
    exit 3
  fi
fi

MSGS=$(sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT COUNT(*) FROM message WHERE session_id = '$SESSION_ID';
" 2>/dev/null || echo "")
TOKENS=$(sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT tokens_input + tokens_cache_read FROM session WHERE id = '$SESSION_ID';
" 2>/dev/null || echo "")

echo "✅ Sessão base criada: $SESSION_ID (${MSGS:-?} msgs, ${TOKENS:-?} tokens)" >&2

if [ -n "$MSGS" ] && [ -n "$TOKENS" ]; then
  if [ "$MSGS" -gt 20 ] 2>/dev/null || [ "$TOKENS" -gt 50000 ] 2>/dev/null; then
    echo "⚠️  Base acima do ideal (≤20 msgs / ≤50k tokens). Forks serão caros." >&2
  fi
fi

echo "$SESSION_ID"
