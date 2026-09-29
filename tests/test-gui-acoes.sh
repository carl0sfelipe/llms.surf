#!/usr/bin/env bash
# tests/test-gui-acoes.sh — Story GUI-2 (docs/stories/gui-acoes-do-dono.md):
# pedidos de agente ao dono viram passos na GUI.
#
#  T1  oracfit acao add/list: grava e lista; recusas não gravam
#  T2  /api/gui/steps: passo dono = ação aberta mais antiga, com secondary
#  T3  POST /api/gui/acao feito → some; depois → snooze esconde
#  T4  recusas do POST (id fechado, choice inválida) não gravam
#  T5  linha lixo no arquivo não derruba a API; id repetido substitui
#  T6  sem ações → dono feito; oracfit acao done fecha pela CLI
#  T7  docs/gui-pipeline.md existe com a regra do acao add

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACFIT="$REPO_ROOT/bin/oracfit"
# shellcheck source=lib-gui-http.sh
source "$REPO_ROOT/tests/lib-gui-http.sh"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); gui_dump_log "${SRV_LOG:-}"; }

WORK=$(mktemp -d /tmp/test-gui-acoes.XXXXXX)
export ORACFIT_OWNER_ACTIONS="$WORK/acoes.jsonl"
SERVER_PID=""
cleanup() { [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
lines() { [ -f "$ORACFIT_OWNER_ACTIONS" ] && wc -l < "$ORACFIT_OWNER_ACTIONS" || echo 0; }
J() { python3 -c "import json,sys; d=json.load(sys.stdin); $1"; }

echo "=== test-gui-acoes ==="

echo "--- T1: CLI ---"
"$ORACFIT" acao add oauth-github --title "Criar o OAuth App no GitHub" \
  --plain "Crie o app e cole o ID e o segredo no .env do cloud." \
  --href "https://github.com/settings/developers" --source "opus/cloud C1" --blocks "login real" >/dev/null 2>&1 \
  && ok "add com --href" || not "add falhou"
sleep 1
"$ORACFIT" acao add dns-now --title "Arrumar o DNS do now.orbe.live" \
  --plain "Apague o registro errado e crie o CNAME now." --command "echo dns" >/dev/null 2>&1 \
  && ok "add com --command" || not "add 2 falhou"
N=$(lines)
"$ORACFIT" acao add "ID Ruim" --title x --plain y >/dev/null 2>&1; [ $? -eq 2 ] && ok "id inválido exit 2" || not "id inválido aceito"
"$ORACFIT" acao add sem-titulo --title "" --plain y >/dev/null 2>&1; [ $? -eq 2 ] && ok "title vazio exit 2" || not "title vazio aceito"
"$ORACFIT" acao add longo --title x --plain "$(printf 'a%.0s' $(seq 1 141))" >/dev/null 2>&1; [ $? -eq 2 ] && ok "plain >140 exit 2" || not "plain longo aceito"
[ "$(lines)" = "$N" ] && ok "recusas não gravaram" || not "recusa gravou"
"$ORACFIT" acao list | head -1 | cut -f1 | grep -qx oauth-github && ok "list: mais antiga primeiro" || not "list: $("$ORACFIT" acao list)"
"$ORACFIT" acao list --json | J "assert [a['id'] for a in d]==['oauth-github','dns-now']" 2>/dev/null && ok "list --json" || not "list --json"

echo "--- sobe servidor ---"
WD="$WORK/wd"; mkdir -p "$WD/.dispatch/logs"
ROOT="$WORK/root"; mkdir -p "$ROOT/ledger" "$ROOT/core"
printf '{"version":1,"models":[{"id":"m-vivo","provider":"stub","tier":"free"}]}' > "$ROOT/model-registry.json"
printf '{"providers":{}}' > "$ROOT/core/usage-limits.json"
SRV_LOG="$WORK/server.log"
python3 "$REPO_ROOT/bin/oracfit-panel-server.py" --panel-dir "$REPO_ROOT/panel" \
  --logs-dir "$WD/.dispatch/logs" --oracfit-root "$ROOT" --port 0 --bind 127.0.0.1 > "$SRV_LOG" 2>&1 &
SERVER_PID=$!
PORT=$(gui_wait_port "$SRV_LOG" passos.html || true)
BASE="http://127.0.0.1:$PORT"
steps() { gui_get "$BASE/api/gui/steps"; }
dono() { steps | J "print(json.dumps([s for s in d['steps'] if s['id']=='dono'][0]))"; }

echo "--- T2: passo dono ---"
steps | J "assert [s['id'] for s in d['steps']]==['modelos','dono','falhas','notas','despachar','pronto'] and d['current']=='dono'" 2>/dev/null \
  && ok "ordem com dono; current=dono" || not "ordem/current: $(steps)"
D=$(dono)
echo "$D" | J "assert d['item']['id']=='oauth-github' and d['remaining']==1 and d['title']=='Criar o OAuth App no GitHub'" 2>/dev/null \
  && ok "mostra a mais antiga, remaining=1" || not "item: $D"
echo "$D" | J "a=d['action']; assert a['kind']=='link' and a['href'].startswith('https://github.com') and [x['id'] for x in a['secondary']]==['feito','depois']" 2>/dev/null \
  && ok "ação link + Já fiz / Me lembre amanhã" || not "action: $D"
echo "$D" | J "assert d['item']['source']=='opus/cloud C1' and d['item']['blocks']=='login real'" 2>/dev/null \
  && ok "source e blocks expostos" || not "source/blocks"

echo "--- T3/T4: POST /api/gui/acao ---"
post() { curl -s -o "$WORK/resp" -w '%{http_code}' -H 'Content-Type: application/json' -d "$1" "$BASE/api/gui/acao"; }
N=$(lines)
[ "$(post '{"id":"oauth-github","choice":"explodir"}')" = 400 ] && ok "choice inválida 400" || not "choice inválida aceita"
[ "$(post '{"id":"nao-existe","choice":"feito"}')" = 400 ] && ok "id inexistente 400" || not "id inexistente aceito"
[ "$(lines)" = "$N" ] && ok "recusas não gravaram" || not "recusa gravou"
[ "$(post '{"id":"oauth-github","choice":"feito"}')" = 200 ] && ok "feito 200" || not "feito: $(cat "$WORK/resp")"
[ "$(post '{"id":"oauth-github","choice":"feito"}')" = 400 ] && ok "feito de novo 400" || not "fechar 2x aceito"
dono | J "assert d['item']['id']=='dns-now' and d['action']['kind']=='copy' and d['action']['command']=='echo dns'" 2>/dev/null \
  && ok "próxima ação aparece (copy)" || not "após feito: $(dono)"
[ "$(post '{"id":"dns-now","choice":"depois"}')" = 200 ] && ok "depois 200" || not "depois: $(cat "$WORK/resp")"
steps | J "st={s['id']:s['state'] for s in d['steps']}; assert st['dono']=='feito' and d['current']!='dono'" 2>/dev/null \
  && ok "snooze esconde; dono feito" || not "snooze: $(steps)"
grep -q '"type": *"snooze"' "$ORACFIT_OWNER_ACTIONS" && grep -q '"until"' "$ORACFIT_OWNER_ACTIONS" && ok "snooze gravado com until" || not "snooze sem until"

echo "--- T5: robustez ---"
echo 'isto não é json' >> "$ORACFIT_OWNER_ACTIONS"
"$ORACFIT" acao add revisar-prs --title "Revisar PRs" --plain "Primeira versão." >/dev/null 2>&1
"$ORACFIT" acao add revisar-prs --title "Revisar PRs 18 e 19" --plain "Versão nova substitui." >/dev/null 2>&1
dono | J "assert d['item']['id']=='revisar-prs' and d['title']=='Revisar PRs 18 e 19' and d['remaining']==0" 2>/dev/null \
  && ok "linha lixo ignorada; add repetido substitui" || not "robustez: $(dono)"

echo "--- T6: done pela CLI ---"
"$ORACFIT" acao done revisar-prs >/dev/null 2>&1 && ok "acao done" || not "acao done falhou"
"$ORACFIT" acao done revisar-prs >/dev/null 2>&1; [ $? -eq 2 ] && ok "done 2x exit 2" || not "done 2x aceito"
steps | J "assert [s for s in d['steps'] if s['id']=='dono'][0]['state']=='feito'" 2>/dev/null && ok "sem abertas → feito" || not "dono não fechou"

echo "--- T7: pipeline documentado ---"
grep -q 'oracfit acao add' "$REPO_ROOT/docs/gui-pipeline.md" 2>/dev/null && ok "docs/gui-pipeline.md com a regra" || not "docs/gui-pipeline.md ausente"

echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
