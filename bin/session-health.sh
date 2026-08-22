#!/bin/bash
# session-health.sh — Dashboard de sessões, tokens, rate limit, recomendação
# Uso: bin/session-health.sh [horas]
# Read-only no DB. Exit 0 sempre (informativo).
# Env obrigatória: DB_PATH
# Env opcional: LOG_PATH (log do CLI, para seção de rate limit — sem ela, seção é pulada)

: "${DB_PATH:?Erro: env DB_PATH não definida. Caminho do banco de sessões do CLI ativo.}"

HOURS="${1:-24}"
CUTOFF=$(( ($(date +%s) - HOURS * 3600) * 1000 ))

if [ ! -f "$DB_PATH" ]; then
  echo "❌ DB não encontrado: $DB_PATH"
  exit 3
fi

echo "═══ Session Health (últimas ${HOURS}h) ═══"
echo ""
printf "%-38s %-30s %5s %10s %10s %8s %4s %s\n" \
  "SESSION_ID" "MODEL" "MSGS" "TOK_IN" "TOK_CACHE" "COST" "FORK" "REC"
printf "%s\n" "$(printf '─%.0s' {1..130})"

sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT
  s.id,
  json_extract(s.model, '$.id') as model,
  (SELECT COUNT(*) FROM message m WHERE m.session_id = s.id) as msgs,
  s.tokens_input,
  s.tokens_cache_read,
  printf('%.4f', s.cost) as cost,
  CASE WHEN s.parent_id IS NOT NULL THEN 'Y' ELSE '' END as is_fork,
  s.time_updated
FROM session s
WHERE s.time_updated > $CUTOFF
ORDER BY s.time_updated DESC
LIMIT 20;
" | while IFS='|' read -r id model msgs tok_in tok_cache cost is_fork time_upd; do
  rec="FRESH"
  if [ "$msgs" -lt 20 ] && [ "$tok_in" -lt 50000 ]; then
    rec="REUSE/FORK"
  elif [ "$msgs" -lt 50 ] && [ "$tok_in" -lt 100000 ]; then
    rec="FORK"
  fi
  printf "%-38s %-30s %5s %10s %10s %8s %4s %s\n" \
    "$id" "$model" "$msgs" "$tok_in" "$tok_cache" "$cost" "$is_fork" "$rec"
done

echo ""
echo "═══ Rate Limit (última hora) ═══"
if [ -n "${LOG_PATH:-}" ] && [ -f "$LOG_PATH" ]; then
  ONE_HOUR_AGO=$(date -v-1H +%Y-%m-%dT%H 2>/dev/null || date -d '1 hour ago' +%Y-%m-%dT%H)
  RL_COUNT=$(grep -c "rate.limit\|429\|temporarily" "$LOG_PATH" 2>/dev/null || echo 0)
  RL_RECENT=$(grep "rate.limit\|429\|temporarily" "$LOG_PATH" 2>/dev/null | grep -c "$ONE_HOUR_AGO" || echo 0)
  echo "  Total menções rate limit: $RL_COUNT"
  echo "  Última hora: $RL_RECENT"
  if [ "$RL_RECENT" -gt 0 ]; then
    echo "  ⚠️  Rate limit ATIVO — evitar free models"
    grep "rate.limit\|429\|temporarily" "$LOG_PATH" | tail -3 | sed 's/^/  /'
  else
    echo "  ✅ Sem rate limit recente"
  fi
else
  echo "  (env LOG_PATH não definida ou log não encontrado — seção pulada)"
fi

echo ""
echo "═══ Forks (linhagem) ═══"
sqlite3 "file:${DB_PATH}?mode=ro" "
SELECT s.id, s.parent_id, json_extract(s.model, '$.id')
FROM session s
WHERE s.parent_id IS NOT NULL
ORDER BY s.time_created DESC
LIMIT 5;
" | while IFS='|' read -r id parent model; do
  echo "  $id ← $parent ($model)"
done
