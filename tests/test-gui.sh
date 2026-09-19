#!/usr/bin/env bash
# tests/test-gui.sh — GUI local (oracfit gui / hitl): servidor único read-only
# + endpoint de score do HITL (o único write).
#
#  T1  servidor sobe e cada página responde 200 com marcador próprio
#  T2  /api/rings extrai anéis do ledger do alvo (hipótese, to_score)
#  T3  ANTI-ÂNCORA: anel fechado sem nota NÃO carrega a previsão do critic
#  T3b bloco "Em português claro" (template determinístico) presente por anel
#      e SEM a previsão do critic dentro dele
#  T4  POST /api/ring-score válido grava owner_score no ledger e devolve delta
#  T4b REGRESSÃO (bug de campo 2026-08-13): alvo com state.json ANTERIOR à
#      feature central_ledger (sem a chave) — score funcionava? `[ -n ] &&`
#      como última linha de require_state matava o runner em silêncio (exit 1
#      sem stderr) e a página mostrava "exit 1" seco
#  T5  validação de input do score: 11, texto, float, bool, ring path-traversal,
#      ring inexistente e nota repetida recusam SEM linha nova no ledger
#  T5b recusa REAL do runner volta com motivo legível (nunca "exit N" seco)
#  T6  /api/gui/dispatches declara as 3 fontes (regra 38) — ausente aparece
#  T7  /api/gui/rings agrupa eventos ring-v1 do ledger central por run
#  T8  /api/gui/registry lê model-registry.json e usage-limits.json
#  T9  path traversal continua bloqueado (logs e estáticos)
#  T10 roteamento: oracfit gui --help; oracfit hitl sem alvo recusa

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACFIT="$REPO_ROOT/bin/oracfit"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-gui.XXXXXX)
export ORACFIT_CENTRAL_LEDGER="$WORK/central.jsonl"
SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== test-gui ==="

# ── fixture: alvo com 2 anéis fechados de verdade (runner real, não mock) ────
TARGET="$WORK/alvo"
mkdir -p "$TARGET"
( cd "$TARGET" \
  && git init -q \
  && git config user.email gui@test.dev && git config user.name GuiTest \
  && echo hi > README.md && git add README.md && git commit -qm init \
  && "$ORACFIT" ring init --mode smoketest --target . --oracle-cmd "true" --ceiling 3 \
  && python3 -c "
import json
d = json.load(open('ring/state.json')); d['min_disk_gb'] = 0
json.dump(d, open('ring/state.json','w'))" \
  && ORACFIT_RING_COMMIT=1 git commit -qam "test: disk gate off" ) >/dev/null 2>&1

close_ring() { # $1=ring $2=hipótese $3=pred $4=arquivo
  ( cd "$TARGET" \
    && "$ORACFIT" ring open "$1" "$2" --target . \
    && mkdir -p ring/verdicts ring/notes \
    && printf '{"verdict":"APPROVED","biggest_gap":"gap real do %s","owner_score_pred":%s}' "$1" "$3" > "ring/verdicts/$1.json" \
    && echo "notas do executor" > "ring/notes/$1.md" \
    && echo conteudo > "$4" \
    && "$ORACFIT" ring close "$1" --target . -- "$4" ) >/dev/null 2>&1
}
close_ring G-1 "primeira hipótese de teste" 4.6 file1.txt || not "fixture: close G-1 falhou"
close_ring G-2 "segunda hipótese de teste" 4.9 file2.txt || not "fixture: close G-2 falhou"

# ── fixture: root da GUI (ledger central + registry + incidents) ─────────────
FIXROOT="$WORK/root"
mkdir -p "$FIXROOT/ledger" "$FIXROOT/core" "$FIXROOT/incidents"
cp "$ORACFIT_CENTRAL_LEDGER" "$FIXROOT/ledger/ledger.jsonl"
cat >> "$FIXROOT/ledger/ledger.jsonl" <<'EOF'
{"task_name":"smoke-dispatch","spec_file":"/tmp/spec.md","model":{"id":"test-model","providerID":"stub"},"started_at":"2026-08-13T00:00:00Z","duration_seconds":10,"exit_status":"ok","runner_exit":"0","oracle_status":"passou","log_file":"/tmp/x.log"}
EOF
printf '{"$schema":"core/model-registry-spec.md","version":1,"models":[{"id":"m-vivo","provider":"stub","tier":"free","accuracy":0.9,"latency_ms":100,"best_for":["teste"]},{"id":"m-morto","provider":"stub","tier":"free","id_status":"APOSENTADO-410"}]}' \
  > "$FIXROOT/model-registry.json"
printf '{"providers":{"stub":{"plan":"Stub Plan","windows":{"day":{"limit_tokens":null}}}}}' \
  > "$FIXROOT/core/usage-limits.json"
printf '# Incidente de teste\n' > "$FIXROOT/incidents/2026-08-13-incidente-de-teste.md"

# ── fixture: workdir com events + escalate (batch AUSENTE de propósito) ──────
WD="$WORK/wd"
LOGS="$WD/.dispatch/logs"
mkdir -p "$LOGS"
NOW_TS=$(python3 -c "import datetime;print(datetime.datetime.now(datetime.timezone.utc).isoformat())")
cat > "$LOGS/events.jsonl" <<EOF
{"v":1,"ts":"$NOW_TS","run_id":"run-vivo","type":"run_started","mode":"normal","task":"tarefa-viva","model_id":"stub/model"}
{"v":1,"ts":"2026-08-01T00:00:00Z","run_id":"run-velho","type":"run_started","mode":"normal","task":"morto-sem-finish"}
EOF
printf '{"task_name":"esc-1","mode":2,"result":"success","tier":"flash","model":"stub/flash","attempt":1,"duration_s":10,"runner_exit":0,"oracle_exit":0}\n' \
  > "$LOGS/escalate-ledger.jsonl"

# ── sobe o servidor em porta efêmera ─────────────────────────────────────────
SRV_LOG="$WORK/server.log"
python3 "$REPO_ROOT/bin/oracfit-panel-server.py" \
  --panel-dir "$REPO_ROOT/panel" \
  --logs-dir "$LOGS" \
  --oracfit-root "$FIXROOT" \
  --ring-target "$TARGET" \
  --port 0 --bind 127.0.0.1 > "$SRV_LOG" 2>&1 &
SERVER_PID=$!

PORT=$(gui_wait_port "$SRV_LOG" home.html || true)
BASE="http://127.0.0.1:$PORT"
[ -n "$PORT" ] || { not "servidor não subiu (log: $SRV_LOG)"; exit 1; }

echo "--- T1: páginas respondem 200 com marcador ---"
check_page() { # $1=página $2=marcador
  body=$(gui_get "$BASE/$1" || true)
  if echo "$body" | grep -q -- "$2"; then ok "$1 (marcador '$2')"; else not "$1 sem marcador '$2'"; fi
}
check_page home.html "Agora"
check_page hitl.html "Que nota\|Calibração"
check_page rings.html "god mode"
check_page dispatches.html "regra 38"
check_page incidents.html "incident.sh audit"
check_page registry.html "model-registry"
check_page index.html 'id="metric-bar"'
check_page gui.css "bg-default"
check_page gui.js "renderCapped"

echo "--- T2: /api/rings extrai do ledger do alvo ---"
RINGS=$(gui_get "$BASE/api/rings")
n=$(echo "$RINGS" | python3 -c "import json,sys;d=json.load(sys.stdin);print(len(d['rings']))")
ts=$(echo "$RINGS" | python3 -c "import json,sys;print(json.load(sys.stdin)['to_score'])")
hyp=$(echo "$RINGS" | python3 -c "import json,sys;print(json.load(sys.stdin)['rings'][0]['hypothesis'])")
[ "$n" = "2" ] && ok "2 anéis fechados extraídos" || not "esperava 2 anéis, veio $n"
[ "$ts" = "2" ] && ok "to_score=2" || not "to_score errado: $ts"
[ "$hyp" = "primeira hipótese de teste" ] && ok "hipótese do open no payload" || not "hipótese errada: $hyp"

echo "--- T3: anti-âncora — sem nota, sem previsão no payload ---"
if echo "$RINGS" | grep -q '"pred"'; then
  not "payload de anel sem nota carrega 'pred' (âncora vazou)"
else
  ok "previsão do critic fora do payload antes da nota"
fi
if echo "$RINGS" | grep -q "owner_score_pred"; then
  not "payload vazou owner_score_pred (checkpoint sem filtro?)"
else
  ok "checkpoint_excerpt não vaza owner_score_pred"
fi

echo "--- T3b: bloco 'Em português claro' por anel ---"
plain=$(echo "$RINGS" | python3 -c "import json,sys;print(json.load(sys.stdin)['rings'][0].get('plain',''))")
echo "$plain" | grep -q "Um robô trabalhou" \
  && ok "campo plain gerado do template" || not "campo plain ausente/errado: $plain"
echo "$plain" | grep -q "primeira hipótese de teste" \
  && ok "plain usa a hipótese real do anel" || not "plain sem a hipótese: $plain"
if echo "$plain" | grep -qE "4[.,]6|revisor previu|nota prevista"; then
  not "plain vazou a previsão do critic (anti-âncora furada)"
else
  ok "plain não vaza a previsão do critic"
fi
gui_get "$BASE/hitl.html" | grep -q "Em português claro" \
  && ok "hitl.html renderiza o rótulo 'Em português claro'" || not "rótulo ausente no hitl.html"

echo "--- T4: POST score válido grava e devolve delta ---"
RES=$(curl -s -X POST "$BASE/api/ring-score" -H 'Content-Type: application/json' -d '{"ring":"G-1","real":4}')
echo "$RES" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True and d['ring'] == 'G-1', d
assert d['real'] == 4 and abs(d['pred'] - 4.6) < 1e-9, d
assert abs(d['delta'] - (-0.6)) < 1e-9, d
" && ok "resposta com real=4 pred=4.6 delta=-0.6" || not "resposta do score errada: $RES"
if grep -q '"event": "owner_score"' "$TARGET/ring/ledger.jsonl" \
   && grep -q '"delta": -0.6' "$TARGET/ring/ledger.jsonl"; then
  ok "owner_score com delta no ledger do alvo (write real)"
else
  not "owner_score não apareceu no ledger"
fi
if grep -q '"event": "owner_score"' "$ORACFIT_CENTRAL_LEDGER"; then
  ok "owner_score também no ledger central"
else
  not "owner_score ausente do central"
fi

echo "--- T5: validação de input do score ---"
lines_before=$(wc -l < "$TARGET/ring/ledger.jsonl")
bad_post() { # $1=payload $2=status esperado $3=nome
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/ring-score" \
    -H 'Content-Type: application/json' -d "$1")
  [ "$code" = "$2" ] && ok "$3 → $2" || not "$3: esperava $2, veio $code"
}
bad_post '{"ring":"G-2","real":11}' 400 "nota 11"
bad_post '{"ring":"G-2","real":-1}' 400 "nota -1"
bad_post '{"ring":"G-2","real":"abc"}' 400 "nota texto"
bad_post '{"ring":"G-2","real":7.5}' 400 "nota float"
bad_post '{"ring":"G-2","real":true}' 400 "nota bool"
bad_post '{"ring":"../../etc/passwd","real":5}' 400 "ring com path traversal"
bad_post '{"ring":"G-99","real":5}' 404 "ring inexistente"
bad_post '{"ring":"G-1","real":5}' 409 "nota repetida"
lines_after=$(wc -l < "$TARGET/ring/ledger.jsonl")
[ "$lines_before" = "$lines_after" ] && ok "nenhuma recusa gerou linha no ledger" \
  || not "recusa sujou o ledger ($lines_before → $lines_after)"

echo "--- T4b: state pré-feature (sem central_ledger) não mata o score ---"
ALVO2="$WORK/alvo2"
mkdir -p "$ALVO2"
( cd "$ALVO2" \
  && git init -q \
  && git config user.email gui@test.dev && git config user.name GuiTest \
  && echo hi > README.md && git add README.md && git commit -qm init \
  && "$ORACFIT" ring init --mode smoketest --target . --oracle-cmd "true" --ceiling 2 \
  && python3 -c "
import json
d = json.load(open('ring/state.json'))
d['min_disk_gb'] = 0
d.pop('central_ledger', None)   # simula alvo criado antes da feature
json.dump(d, open('ring/state.json','w'))" \
  && ORACFIT_RING_COMMIT=1 git commit -qam "test: pre-feature state" ) >/dev/null 2>&1
( cd "$ALVO2" \
  && "$ORACFIT" ring open H-1 "anel pré-feature" --target . \
  && printf '{"verdict":"APPROVED","biggest_gap":"gap real do H-1","owner_score_pred":4.7}' > ring/verdicts/H-1.json \
  && echo notas > ring/notes/H-1.md \
  && echo conteudo > h1.txt \
  && "$ORACFIT" ring close H-1 --target . -- h1.txt ) >/dev/null 2>&1 \
  || not "fixture alvo2: close H-1 falhou"

SRV2_LOG="$WORK/server2.log"
python3 "$REPO_ROOT/bin/oracfit-panel-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$FIXROOT" \
  --ring-target "$ALVO2" --port 0 --bind 127.0.0.1 > "$SRV2_LOG" 2>&1 &
SERVER2_PID=$!
PORT2=$(gui_wait_port "$SRV2_LOG" api/rings || true)
[ -n "$PORT2" ] || { not "servidor 2 não subiu"; gui_dump_log "$SRV2_LOG"; }
RES2=$(curl -s -X POST "http://127.0.0.1:$PORT2/api/ring-score" \
  -H 'Content-Type: application/json' -d '{"ring":"H-1","real":5}')
echo "$RES2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is True and abs(d['delta'] - 0.3) < 1e-9, d
" && ok "score em alvo pré-feature grava (delta 0.3)" \
  || not "score em alvo pré-feature falhou: $RES2"

echo "--- T5b: recusa real do runner volta com motivo legível ---"
( cd "$ALVO2" \
  && "$ORACFIT" ring open H-2 "anel p/ recusa" --target . \
  && printf '{"verdict":"APPROVED","biggest_gap":"gap real do H-2","owner_score_pred":4.8}' > ring/verdicts/H-2.json \
  && echo notas > ring/notes/H-2.md \
  && echo conteudo > h2.txt \
  && "$ORACFIT" ring close H-2 --target . -- h2.txt ) >/dev/null 2>&1 \
  || not "fixture alvo2: close H-2 falhou"
# score_field quebrado força o runner a recusar DEPOIS da validação do servidor
python3 -c "
import json
p = '$ALVO2/ring/state.json'
d = json.load(open(p)); d['score_field'] = 'campo_inexistente'
json.dump(d, open(p, 'w'))"
RES3=$(curl -s -X POST "http://127.0.0.1:$PORT2/api/ring-score" \
  -H 'Content-Type: application/json' -d '{"ring":"H-2","real":5}')
echo "$RES3" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['ok'] is False, d
assert 'campo_inexistente' in d['error'] or 'sem campo' in d['error'], d
assert d['error'].strip() not in ('', 'exit 1', 'exit 2'), d
" && ok "recusa carrega o motivo do runner, não 'exit N' seco" \
  || not "recusa sem motivo legível: $RES3"
kill "$SERVER2_PID" 2>/dev/null; wait "$SERVER2_PID" 2>/dev/null

echo "--- T6: dispatches declara as 3 fontes (regra 38) ---"
DISP=$(gui_get "$BASE/api/gui/dispatches")
echo "$DISP" | python3 -c "
import json, sys
d = json.load(sys.stdin)
srcs = {s['source']: s for s in d['sources']}
assert set(srcs) == {'dispatch', 'escalate', 'batch'}, srcs
assert srcs['dispatch']['exists'] and srcs['dispatch']['entries'] == 1, srcs['dispatch']
assert srcs['escalate']['exists'] and srcs['escalate']['entries'] == 1, srcs['escalate']
assert srcs['batch']['exists'] is False, srcs['batch']
tasks = {r['task'] for r in d['runs']}
assert 'smoke-dispatch' in tasks and 'esc-1' in tasks, tasks
" && ok "3 fontes declaradas, batch ausente aparece como ausente" \
  || not "declaração de fontes errada: $(echo "$DISP" | head -c 300)"

echo "--- T7: /api/gui/rings agrupa central por run ---"
gui_get "$BASE/api/gui/rings" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['groups'], 'sem grupos'
g = d['groups'][0]
assert g['closed'] == 2, g
assert {r['ring'] for r in g['rings']} == {'G-1', 'G-2'}, g
" && ok "grupo do run com G-1/G-2 fechados" || not "agrupamento central errado"

echo "--- T8: registry lê fixtures ---"
gui_get "$BASE/api/gui/registry" | python3 -c "
import json, sys
d = json.load(sys.stdin)
ms = {m['id']: m for m in d['models']}
assert ms['m-vivo']['retired'] is False and ms['m-morto']['retired'] is True, ms
assert d['limits']['stub']['plan'] == 'Stub Plan', d['limits']
" && ok "registry + limits no payload" || not "registry errado"

echo "--- T9: path traversal bloqueado ---"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/logs/../../etc/passwd" || true)
[ "$CODE" != "200" ] && ok "logs traversal ($CODE)" || not "logs traversal vazou"
CODE=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/../../etc/passwd" || true)
[ "$CODE" != "200" ] && ok "estático traversal ($CODE)" || not "estático traversal vazou"

echo "--- T10: roteamento no bin/oracfit ---"
"$ORACFIT" gui --help 2>/dev/null | grep -q "hitl.html" && ok "oracfit gui --help" || not "gui --help sem hitl.html"
rc=0; "$ORACFIT" hitl >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "oracfit hitl sem alvo recusa (rc=$rc)" || not "hitl sem alvo passou"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
