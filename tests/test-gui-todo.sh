#!/usr/bin/env bash
# tests/test-gui-todo.sh — visão TODO/backlog de anéis (oracfit gui → /todo.html
# + /api/gui/todo, servida pelo bin/oracfit-todo-server.py que herda o
# oracfit-panel-server.py sem tocá-lo).
#
#  T1  servidor-extensão sobe; /todo.html responde com marcador; herança
#      preservada (/api/gui/home e gui.css continuam respondendo)
#  T2  /api/gui/todo casa backlog (tabela+checkbox) com ledger ring-v1:
#      feito/andamento/fila, contadores, commit do close, tentativas,
#      teto de close do state.json
#  T3  ANTI-ÂNCORA: item de anel fechado sem nota NÃO carrega pred nem
#      owner_score_pred no payload
#  T4  graça: alvo SEM ring init (só backlog) — servidor sobe com WARN e o
#      endpoint responde ok com tudo na fila (regra 38: ausência declarada)
#  T5  graça: alvo sem docs/BACKLOG.md — itens só do ledger, backlog
#      declarado como ausente
#  T6  ?project= resolve na frota wt-*; projeto fora da frota → 404
#  T7  bin/oracfit-gui.sh --help menciona todo.html (e segue mencionando
#      hitl.html — contrato antigo intacto)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-gui-todo.XXXXXX)
SERVER_PID=""
SERVER2_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  [ -n "$SERVER2_PID" ] && kill "$SERVER2_PID" 2>/dev/null
  wait "$SERVER_PID" "$SERVER2_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== test-gui-todo ==="

# ── fixture: alvo com ring/ + backlog (ledger escrito à mão, schema ring-v1) ─
TARGET="$WORK/alvo"
mkdir -p "$TARGET/ring" "$TARGET/docs"
cat > "$TARGET/ring/state.json" <<'EOF'
{"schema":"ring-state-v1","mode":"ananke","run":"todo-1","ceiling":6,
 "close_attempt_ceiling":5,"score_field":"owner_score_pred","current_ring":"R-2"}
EOF
cat > "$TARGET/ring/ledger.jsonl" <<'EOF'
{"schema":"ring-v1","run":"todo-1","ring":"","event":"init","ts":"2026-08-13T00:00:00Z"}
{"schema":"ring-v1","run":"todo-1","ring":"R-1","event":"open","hypothesis":"fundação do alvo","ts":"2026-08-13T00:01:00Z"}
{"schema":"ring-v1","run":"todo-1","ring":"R-1","event":"close_attempt","reason":"faltou nota do executor","ts":"2026-08-13T00:02:00Z"}
{"schema":"ring-v1","run":"todo-1","ring":"R-1","event":"close","owner_score_pred":4.6,"oracle":{"exit":0,"runs":2},"files_staged":3,"test_files":1,"build_commit":"abc1234","ts":"2026-08-13T00:03:00Z"}
{"schema":"ring-v1","run":"todo-1","ring":"R-2","event":"open","hypothesis":"pilar em obra","ts":"2026-08-13T00:04:00Z"}
{"schema":"ring-v1","run":"outro-run","ring":"Z-9","event":"open","hypothesis":"anel de outro run não entra","ts":"2026-08-12T00:00:00Z"}
EOF
cat > "$TARGET/docs/BACKLOG.md" <<'EOF'
# Backlog — alvo de teste

Texto de gente antes da tabela, deve ser ignorado.

| Anel | Escopo | Artefatos | Estado |
|---|---|---|---|
| R-1 | Fundação: base do projeto | `docs/a.md` | aberto |
| R-2 | Pilar um | `docs/b.md` | pendente |
| R-3 | Pilar dois | `docs/c.md` | pendente |
| R-4 | Consolidação | `docs/d.md` | pendente |

## Critérios transversais

- [x] R-9 item avulso já fechado à mão
- [ ] item avulso sem id de anel
EOF

# ── frota: irmão wt-* com ring mas SEM backlog (T5/T6) ───────────────────────
SEMBACK="$WORK/wt-semback"
mkdir -p "$SEMBACK/ring"
cat > "$SEMBACK/ring/state.json" <<'EOF'
{"schema":"ring-state-v1","mode":"smoketest","run":"sb-1","score_field":"owner_score_pred"}
EOF
cat > "$SEMBACK/ring/ledger.jsonl" <<'EOF'
{"schema":"ring-v1","run":"sb-1","ring":"S-1","event":"open","hypothesis":"anel sem backlog","ts":"2026-08-13T00:00:00Z"}
EOF

LOGS="$WORK/wd/.dispatch/logs"
mkdir -p "$LOGS" "$WORK/root/ledger"

SRV_LOG="$WORK/server.log"
python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$WORK/root" \
  --ring-target "$TARGET" --port 0 --bind 127.0.0.1 > "$SRV_LOG" 2>&1 &
SERVER_PID=$!
PORT=$(gui_wait_port "$SRV_LOG" todo.html || true)
BASE="http://127.0.0.1:$PORT"
[ -n "$PORT" ] || { not "servidor não subiu (log: $SRV_LOG)"; exit 1; }

echo "--- T1: página + herança do servidor base ---"
gui_get "$BASE/todo.html" | grep -q "backlog de anéis" \
  && ok "/todo.html com marcador" || not "/todo.html sem marcador"
gui_get "$BASE/api/gui/home" | grep -q '"ok": true' \
  && ok "/api/gui/home herdado responde" || not "/api/gui/home quebrou na herança"
gui_get "$BASE/gui.css" | grep -q "bg-default" \
  && ok "gui.css servido" || not "gui.css não servido"
gui_get "$BASE/runtime-config.json" | grep -q '"todo": true' \
  && ok "runtime-config declara todo" || not "runtime-config sem todo"

echo "--- T2: backlog × ledger — estados, contadores, detalhe do close ---"
TODO=$(gui_get "$BASE/api/gui/todo")
echo "$TODO" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] and d['run'] == 'todo-1' and d['mode'] == 'ananke', d
c = d['counters']
assert c == {'feito': 2, 'andamento': 1, 'fila': 3, 'abortado': 0,
             'total': 6, 'closes_recusados': 1}, c
by = {i['id']: i for i in d['items']}
r1 = by['R-1']
assert r1['status'] == 'feito' and r1['source'] == 'backlog+ledger', r1
assert r1['build_commit'] == 'abc1234' and r1['attempts'] == 1, r1
assert r1['title'] == 'Fundação: base do projeto', r1
assert r1['hypothesis'] == 'fundação do alvo', r1
r2 = by['R-2']
assert r2['status'] == 'andamento' and r2['attempts'] == 0, r2
assert by['R-3']['status'] == 'fila' and by['R-4']['status'] == 'fila', by
assert by['R-9']['status'] == 'feito' and by['R-9']['source'] == 'backlog', by['R-9']
sem_id = [i for i in d['items'] if not i['id']]
assert len(sem_id) == 1 and sem_id[0]['status'] == 'fila', sem_id
assert 'Z-9' not in by, 'anel de outro run vazou'
assert d['state']['close_attempt_ceiling'] == 5 and d['state']['ring_ceiling'] == 6, d['state']
assert d['backlog']['exists'] and d['backlog']['items'] == 6, d['backlog']
" && ok "payload casa backlog com ledger (6 itens, 2 feitos, 1 andamento)" \
  || not "payload errado: $(echo "$TODO" | head -c 400)"

echo "--- T3: anti-âncora — fechado sem nota não carrega previsão ---"
if echo "$TODO" | grep -q '"pred"\|owner_score_pred'; then
  not "payload do TODO vazou a previsão do critic"
else
  ok "sem pred/owner_score_pred no payload"
fi

echo "--- T4: alvo sem ring init — WARN no boot, tudo na fila ---"
NORING="$WORK/noring"
mkdir -p "$NORING/docs"
printf '| Anel | Escopo | Estado |\n|---|---|---|\n| N-1 | primeiro item | pendente |\n' \
  > "$NORING/docs/BACKLOG.md"
SRV2_LOG="$WORK/server2.log"
python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$WORK/root" \
  --ring-target "$NORING" --port 0 --bind 127.0.0.1 > "$SRV2_LOG" 2>&1 &
SERVER2_PID=$!
PORT2=$(gui_wait_port "$SRV2_LOG" api/gui/todo || true)
[ -n "$PORT2" ] && ok "servidor sobe com alvo sem ring/" || { not "servidor recusou alvo sem ring/"; gui_dump_log "$SRV2_LOG"; }
grep -q "WARN" "$SRV2_LOG" && ok "boot avisa que falta ring init" || not "sem WARN no boot"
gui_get "http://127.0.0.1:$PORT2/api/gui/todo" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] and d['ring_initialized'] is False, d
assert d['counters']['fila'] == 1 and d['counters']['total'] == 1, d['counters']
assert d['items'][0]['id'] == 'N-1' and d['items'][0]['status'] == 'fila', d['items']
" && ok "endpoint ok com só backlog (N-1 na fila)" || not "endpoint quebrou sem ring/"
kill "$SERVER2_PID" 2>/dev/null; wait "$SERVER2_PID" 2>/dev/null; SERVER2_PID=""

echo "--- T5: frota — irmão wt-* sem backlog declara ausência ---"
gui_get "$BASE/api/gui/todo?project=semback" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] and d['project'] == 'semback', d
assert d['backlog']['exists'] is False, d['backlog']
assert d['counters'] == {'feito': 0, 'andamento': 1, 'fila': 0, 'abortado': 0,
                         'total': 1, 'closes_recusados': 0}, d['counters']
i = d['items'][0]
assert i['id'] == 'S-1' and i['source'] == 'ledger' and i['title'] == 'anel sem backlog', i
" && ok "?project=semback: 1 anel do ledger, backlog AUSENTE declarado" \
  || not "frota sem backlog errada"

echo "--- T6: projeto fora da frota recusa ---"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/gui/todo?project=nao-existe")
[ "$code" = "404" ] && ok "project fantasma → 404" || not "project fantasma: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/gui/todo?project=../../etc")
[ "$code" != "200" ] && ok "project traversal recusado ($code)" || not "project traversal vazou"

echo "--- T7: oracfit-gui.sh --help declara a página nova ---"
HELP=$(bash "$REPO_ROOT/bin/oracfit-gui.sh" --help)
echo "$HELP" | grep -q "todo.html" && ok "--help menciona todo.html" || not "--help sem todo.html"
echo "$HELP" | grep -q "hitl.html" && ok "--help segue mencionando hitl.html" || not "--help perdeu hitl.html"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
