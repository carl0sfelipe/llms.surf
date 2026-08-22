#!/bin/bash
# decide-context.sh — Decide REUSE/FORK/FRESH para uma sessão
# Uso: bin/decide-context.sh <session_id> [--related]
# Exit: 0=REUSE, 1=FORK, 2=FRESH, 3=erro
# Env obrigatória: DB_PATH

: "${DB_PATH:?Erro: env DB_PATH não definida. Caminho do banco de sessões do CLI ativo.}"

SESSION_ID="${1:?Uso: decide-context.sh <session_id> [--related]}"
RELATED="${2:-}"

if [ ! -f "$DB_PATH" ]; then
  echo "FRESH db-not-found"
  exit 2
fi

ROW=$(sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT
  (SELECT COUNT(*) FROM message m WHERE m.session_id = '$SESSION_ID'),
  s.tokens_input,
  s.time_archived
FROM session s
WHERE s.id = '$SESSION_ID';
")

if [ -z "$ROW" ]; then
  echo "FRESH session-not-found"
  exit 2
fi

MSGS=$(echo "$ROW" | cut -d'|' -f1)
TOKENS=$(echo "$ROW" | cut -d'|' -f2)
ARCHIVED=$(echo "$ROW" | cut -d'|' -f3)

if [ -n "$ARCHIVED" ] && [ "$ARCHIVED" != "" ]; then
  echo "FRESH archived"
  exit 2
fi

if [ "$MSGS" -gt 50 ] || [ "$TOKENS" -gt 100000 ]; then
  echo "FRESH msgs=${MSGS}>50 or tokens=${TOKENS}>100k — consolidar antes"
  exit 2
fi

if [ "$MSGS" -lt 20 ]; then
  if [ "$RELATED" = "--related" ]; then
    echo "REUSE $SESSION_ID msgs=${MSGS} tokens=${TOKENS} — contexto pequeno + task relacionada"
    exit 0
  else
    echo "FORK $SESSION_ID msgs=${MSGS} tokens=${TOKENS} — contexto pequeno + task independente"
    exit 1
  fi
fi

if [ "$MSGS" -ge 20 ] && [ "$MSGS" -le 50 ] && [ "$TOKENS" -lt 100000 ]; then
  if [ "$RELATED" = "--related" ]; then
    echo "FORK $SESSION_ID msgs=${MSGS} tokens=${TOKENS} — médio + relacionada (fork seguro)"
    exit 1
  else
    echo "FRESH msgs=${MSGS} tokens=${TOKENS} — médio + independente (fork caro)"
    exit 2
  fi
fi

echo "FRESH fallback msgs=${MSGS} tokens=${TOKENS}"
exit 2
