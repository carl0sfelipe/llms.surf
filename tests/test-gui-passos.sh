#!/usr/bin/env bash
# tests/test-gui-passos.sh — Story GUI-1 (docs/stories/gui-passo-a-passo.md):
# a GUI calcula "o próximo passo" do estado real e grava decisões.
#
#  T1  /passos.html e / servem a página; gui.js tem o botão Simplificar
#  T2  /api/gui/steps: ordem fixa, 1 só "agora", notas pulado sem alvo
#  T3  falhas: choice com 3 opções, 1 recomendada; falha que depois passou NÃO conta
#  T4  despachar com dispatch desligado = comando para copiar
#  T5  POST /api/gui/decide inválido → 400 e nada gravado
#  T6  decisão válida grava e avança o passo atual
#  T7  workdir sem nada pendente → "pronto"
#  T8  B1: oracfit-gui.sh sobe sem ORACFIT_ROOT e sem ~/.oracfit
#  T9  B3: nenhum "None" nas linhas de /api/gui/dispatches

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-gui-passos.XXXXXX)
PIDS=()
cleanup() {
  for p in "${PIDS[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== test-gui-passos ==="

# ── fixture: root com 1 modelo vivo ─────────────────────────────────────────
FIXROOT="$WORK/root"
mkdir -p "$FIXROOT/ledger" "$FIXROOT/core" "$FIXROOT/incidents"
printf '{"version":1,"models":[{"id":"m-vivo","provider":"stub","tier":"free"}]}' > "$FIXROOT/model-registry.json"
printf '{"providers":{}}' > "$FIXROOT/core/usage-limits.json"
# webnext-02 falhou e DEPOIS passou (não pede decisão); webnext-03 falhou e nunca passou
cat > "$FIXROOT/ledger/ledger.jsonl" <<'EOF'
{"task_name":"webnext-02","model":{"id":"m-vivo"},"started_at":"2026-09-01T10:00:00Z","duration_seconds":60,"runner_exit":"1","oracle_status":"falhou"}
{"task_name":"webnext-02","model":{"id":"m-vivo"},"started_at":"2026-09-01T11:00:00Z","duration_seconds":60,"runner_exit":"0","oracle_status":"passou"}
{"task_name":"webnext-03","model":{"id":"m-vivo"},"started_at":"2026-09-02T10:00:00Z","duration_seconds":60,"runner_exit":"1","oracle_status":"falhou"}
EOF

# ── fixture: workdir com escalate falho (campos nulos) + 1 spec pendente ────
WD="$WORK/wd"
LOGS="$WD/.dispatch/logs"
mkdir -p "$LOGS" "$WD/docs/lair/specs"
printf '{"task_name":"L1-pending","ts":"2026-09-03T10:00:00Z","result":"failed","tier":null,"attempt":null,"model":null}\n' > "$LOGS/escalate-ledger.jsonl"
printf '# spec pendente\n' > "$WD/docs/lair/specs/L2-coisa.md"

start_server() { # $1=logs $2=root $3=log
  python3 "$REPO_ROOT/bin/oracfit-panel-server.py" --panel-dir "$REPO_ROOT/panel" \
    --logs-dir "$1" --oracfit-root "$2" --port 0 --bind 127.0.0.1 > "$3" 2>&1 &
  PIDS+=($!)
}

SRV_LOG="$WORK/server.log"
start_server "$LOGS" "$FIXROOT" "$SRV_LOG"
PORT=$(gui_wait_port "$SRV_LOG" passos.html || true)
BASE="http://127.0.0.1:$PORT"
[ -n "$PORT" ] || { not "servidor não subiu com passos.html"; echo "=== resultado: $pass PASS, $fail FAIL ==="; exit 1; }

J() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

echo "--- T1: página + Simplificar ---"
gui_get "$BASE/passos.html" | grep -q 'id="passos"' && ok "/passos.html tem main#passos" || not "/passos.html sem id=passos"
gui_get "$BASE/" | grep -q 'id="passos"' && ok "/ serve passos" || not "/ não serve passos.html"
GJS=$(gui_get "$BASE/gui.js")
echo "$GJS" | grep -q 'oracfit.simple' && echo "$GJS" | grep -q 'simplify' \
  && ok "gui.js tem botão simplify + localStorage oracfit.simple" || not "gui.js sem Simplificar"
echo "$GJS" | grep -q 'passos.html' && ok "sidebar aponta para passos.html" || not "sidebar sem Passo a passo"
gui_get "$BASE/gui.css" | grep -q 'body.simple' && ok "gui.css tem regras body.simple" || not "gui.css sem body.simple"

echo "--- T2: /api/gui/steps ---"
S=$(gui_get "$BASE/api/gui/steps")
echo "$S" | J "assert [s['id'] for s in d['steps']]==['modelos','falhas','notas','despachar','pronto']" 2>/dev/null \
  && ok "ordem fixa dos passos" || not "ordem dos passos: $S"
echo "$S" | J "assert [s['state'] for s in d['steps']].count('agora')==1" 2>/dev/null \
  && ok "exatamente 1 passo agora" || not "nº de passos agora != 1"
echo "$S" | J "assert d['current']=='falhas' and d['position']==2 and d['total']==4" 2>/dev/null \
  && ok "current=falhas, passo 2 de 4" || not "current/position/total errados"
echo "$S" | J "st={s['id']:s['state'] for s in d['steps']}; assert st['modelos']=='feito' and st['notas']=='pulado' and st['pronto']=='depois'" 2>/dev/null \
  && ok "modelos feito, notas pulado, pronto depois" || not "estados de modelos/notas/pronto"
echo "$S" | J "assert all(s['title'] and s['plain'] and len(s['plain'])<=140 for s in d['steps'])" 2>/dev/null \
  && ok "todo passo tem título e frase simples ≤140" || not "título/plain ausente ou longo"

echo "--- T3: falhas ---"
F=$(echo "$S" | J "print(json.dumps([s for s in d['steps'] if s['id']=='falhas'][0]))")
echo "$F" | J "a=d['action']; assert a['kind']=='choice' and [o['id'] for o in a['options']]==['tentar-de-novo','eu-faco','descartar']" 2>/dev/null \
  && ok "3 opções na ordem" || not "opções de falhas: $F"
echo "$F" | J "assert [o['id'] for o in d['action']['options'] if o.get('recommended')]==['tentar-de-novo']" 2>/dev/null \
  && ok "só tentar-de-novo recomendado" || not "recomendação errada"
echo "$F" | J "assert d['item']['task']=='L1-pending' and d['remaining']==2" 2>/dev/null \
  && ok "mais recente primeiro (L1-pending), 2 falhas (webnext-02 passou depois)" || not "item/remaining: $F"
KEY=$(echo "$F" | J "print(d['item']['run_key'])")

echo "--- T4: despachar desligado ---"
echo "$S" | J "s=[s for s in d['steps'] if s['id']=='despachar'][0]; a=s['action']; assert s['state']=='depois' and a['kind']=='copy' and a['command']=='oracfit run normal docs/lair/specs/L2-coisa.md L2-coisa'" 2>/dev/null \
  && ok "comando para copiar com spec relativa" || not "despachar: $(echo "$S" | J "print([s for s in d['steps'] if s['id']=='despachar'])")"

echo "--- T5: decide inválido ---"
post() { curl -s -o "$WORK/resp" -w '%{http_code}' -H 'Content-Type: application/json' -d "$1" "$BASE/api/gui/decide"; }
[ "$(post "{\"run_key\":\"$KEY\",\"choice\":\"explodir\"}")" = 400 ] && ok "choice inválida 400" || not "choice inválida aceita"
[ "$(post '{"run_key":"dispatch:nao-existe:x","choice":"descartar"}')" = 400 ] && ok "run_key inexistente 400" || not "run_key inexistente aceito"
[ "$(post 'lixo')" = 400 ] && ok "corpo inválido 400" || not "corpo inválido aceito"
[ ! -s "$LOGS/decisions.jsonl" ] && ok "nada gravado nas recusas" || not "recusa gravou linha"

echo "--- T6: decide válido ---"
[ "$(post "{\"run_key\":\"$KEY\",\"choice\":\"descartar\"}")" = 200 ] && ok "decisão aceita" || not "decisão válida recusada: $(cat "$WORK/resp")"
[ "$(wc -l < "$LOGS/decisions.jsonl" 2>/dev/null)" = 1 ] && ok "1 linha em decisions.jsonl" || not "decisions.jsonl sem a linha"
[ "$(post "{\"run_key\":\"$KEY\",\"choice\":\"descartar\"}")" = 400 ] && ok "decidir a mesma falha de novo 400" || not "decisão repetida aceita"
S2=$(gui_get "$BASE/api/gui/steps")
echo "$S2" | J "f=[s for s in d['steps'] if s['id']=='falhas'][0]; assert f['state']=='agora' and f['item']['task']=='webnext-03' and f['remaining']==1" 2>/dev/null \
  && ok "próxima falha aparece (webnext-03)" || not "após decisão: $S2"
K2=$(echo "$S2" | J "print([s for s in d['steps'] if s['id']=='falhas'][0]['item']['run_key'])")
post "{\"run_key\":\"$K2\",\"choice\":\"eu-faco\"}" >/dev/null
python3 -c "import json;print(json.load(open('$WORK/resp'))['next'])" 2>/dev/null | grep -qx despachar \
  && ok "resposta diz next=despachar" || not "next errado: $(cat "$WORK/resp")"
gui_get "$BASE/api/gui/steps" | J "assert d['current']=='despachar'" 2>/dev/null \
  && ok "passo atual virou despachar" || not "current não avançou"

echo "--- T7: nada pendente → pronto ---"
WD2="$WORK/wd2"; mkdir -p "$WD2/.dispatch/logs"
ROOT2="$WORK/root2"; mkdir -p "$ROOT2/ledger" "$ROOT2/core"
cp "$FIXROOT/model-registry.json" "$ROOT2/"; printf '{"providers":{}}' > "$ROOT2/core/usage-limits.json"
SRV2="$WORK/server2.log"
start_server "$WD2/.dispatch/logs" "$ROOT2" "$SRV2"
P2=$(gui_wait_port "$SRV2" passos.html || true)
gui_get "http://127.0.0.1:$P2/api/gui/steps" | J "assert d['current']=='pronto' and [s for s in d['steps'] if s['id']=='pronto'][0]['action']['kind']=='none'" 2>/dev/null \
  && ok "tudo em dia → pronto" || not "workdir vazio não chega em pronto"

echo "--- T8: B1 oracfit-gui.sh sem root configurado ---"
SRV3="$WORK/server3.log"
( cd "$WD2" && env -u ORACFIT_ROOT -u DISPATCH_ROOT HOME="$WORK/fakehome" \
    bash "$REPO_ROOT/bin/oracfit-gui.sh" --port 0 > "$SRV3" 2>&1 ) &
PIDS+=($!)
for _ in $(seq 1 25); do grep -q 'Oracfit panel http' "$SRV3" 2>/dev/null && break; sleep 0.2; done
grep -q 'Oracfit panel http' "$SRV3" && ok "sobe resolvendo o root pelo próprio repo" || not "B1: $(head -3 "$SRV3")"
pkill -f "oracfit-todo-server.py.*$WD2" 2>/dev/null

echo "--- T9: B3 sem None ---"
gui_get "$BASE/api/gui/dispatches" | grep -q 'None' && not "B3: 'None' em /api/gui/dispatches" || ok "sem None nas linhas"

echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
