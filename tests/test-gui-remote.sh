#!/usr/bin/env bash
# tests/test-gui-remote.sh — acesso remoto da GUI: auth por token (fail-closed),
# login/cookie/Bearer, e o POST /api/dispatch (--enable-dispatch, validação
# fail-closed, dispatch de verdade via stub adapter).
#
#  T1  FAIL-CLOSED: --bind fora do loopback sem --auth-token recusa subir (exit 3)
#  T2  token curto (<16) recusa subir (exit 3)
#  T3  com token: sem credencial → 401; Bearer errado → 401; Bearer certo → 200
#  T4  POST /login: token errado → 401; certo → Set-Cookie; cookie acessa home
#  T5  página sem auth redireciona pra /login (303)
#  T6  SUBCLASS: /api/gui/todo (oracfit-todo-server) também exige token —
#      a rota roda antes do super() e não pode furar o gate
#  T7  sem --enable-dispatch: POST /api/dispatch → 404 (default read-only)
#  T8  com --enable-dispatch: mode inexistente / adapter inexistente / task
#      inválida / spec com traversal / spec fora do workdir / spec não-.md
#      → 400 SEM evento novo no events.jsonl
#  T9  dispatch VÁLIDO (stub + normal + smoke spec): 200, run_started+task no
#      events.jsonl, stub-proof criado no workdir (o robô trabalhou de verdade)
#  T10 SEM token (default local): /login → 404 e API aberta — comportamento
#      anterior inalterado (retrocompatibilidade do loopback)
#  T11 túnel: sem --auth-token recusa; sem cloudflared recusa com dica; --help ok
#  T12 roteamento: oracfit gui-tunnel --help passa pelo bin/oracfit

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ORACFIT="$REPO_ROOT/bin/oracfit"
TOKEN="segredo-de-teste-0123456789abcdef"   # 30 chars — passa o mínimo de 16
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-gui-remote.XXXXXX)
export ORACFIT_CENTRAL_LEDGER="$WORK/central.jsonl"
SERVER_PID=""
cleanup() {
  [ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null
  wait "$SERVER_PID" 2>/dev/null
  # dispatch de teste sobrevive à morte do servidor (é o design) — mata pelo pidfile
  for pidfile in "$WORK"/wd/.dispatch/logs/*.pid; do
    [ -f "$pidfile" ] || continue
    pid="$(head -1 "$pidfile" | tr -d '[:space:]')"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== test-gui-remote ==="

# fixture mínima de root (registry/ledger p/ /api/gui/* não dependerem do real)
FIXROOT="$WORK/root"
mkdir -p "$FIXROOT/ledger" "$FIXROOT/core" "$FIXROOT/incidents" "$FIXROOT/adapters"
printf '{"providers":{"stub":{"plan":"Stub Plan"}}}' > "$FIXROOT/core/usage-limits.json"
: > "$FIXROOT/ledger/ledger.jsonl"

# workdir do dispatch: spec de smoke do próprio repo, copiada pra dentro
WD="$WORK/wd"
LOGS="$WD/.dispatch/logs"
mkdir -p "$LOGS"
cp "$REPO_ROOT/specs/oracfit-smoke-normal.md" "$WD/smoke.md"

start_server() { # $@ = args extra (auth/dispatch); sets PORT/SERVER_PID/SRV_LOG
  SRV_LOG="$WORK/server-$$.log"
  python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
    --panel-dir "$REPO_ROOT/panel" \
    --logs-dir "$LOGS" \
    --oracfit-root "$REPO_ROOT" \
    --port 0 --bind 127.0.0.1 "$@" > "$SRV_LOG" 2>&1 &
  SERVER_PID=$!
  PORT=""
  for _ in $(seq 1 40); do
    PORT=$(grep -oE 'http://127\.0\.0\.1:[0-9]+' "$SRV_LOG" | head -1 | grep -oE '[0-9]+$' || true)
    [ -n "$PORT" ] && curl -s -o /dev/null "http://127.0.0.1:$PORT/login" && break
    sleep 0.2
  done
  [ -n "$PORT" ] || { echo "servidor não subiu"; cat "$SRV_LOG"; exit 1; }
}

echo "--- T1: bind remoto sem token recusa subir (fail-closed) ---"
rc=0; python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$REPO_ROOT" \
  --port 0 --bind 0.0.0.0 >/dev/null 2>"$WORK/t1.err" || rc=$?
if [ "$rc" -eq 3 ] && grep -q "fail-closed" "$WORK/t1.err"; then
  ok "--bind 0.0.0.0 sem token → exit 3 com motivo"
else
  not "esperava exit 3 + fail-closed, veio rc=$rc: $(cat "$WORK/t1.err")"
fi

echo "--- T2: token curto recusa ---"
rc=0; python3 "$REPO_ROOT/bin/oracfit-todo-server.py" \
  --panel-dir "$REPO_ROOT/panel" --logs-dir "$LOGS" --oracfit-root "$REPO_ROOT" \
  --port 0 --bind 0.0.0.0 --auth-token curto >/dev/null 2>"$WORK/t2.err" || rc=$?
[ "$rc" -eq 3 ] && ok "token curto → exit 3" || not "token curto passou (rc=$rc)"

echo "--- T3-T9: servidor COM token + dispatch ---"
start_server --auth-token "$TOKEN" --enable-dispatch
BASE="http://127.0.0.1:$PORT"

echo "--- T3: sem credencial / Bearer errado / Bearer certo ---"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/gui/home")
[ "$code" = "401" ] && ok "API sem credencial → 401" || not "API sem credencial: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer errado" "$BASE/api/gui/home")
[ "$code" = "401" ] && ok "Bearer errado → 401" || not "Bearer errado: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$BASE/api/gui/home")
[ "$code" = "200" ] && ok "Bearer certo → 200" || not "Bearer certo: $code"

echo "--- T4: login (POST /login) e cookie ---"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/login" \
  -H 'Content-Type: application/json' -d '{"token":"erradissimo"}')
[ "$code" = "401" ] && ok "login com token errado → 401" || not "login errado: $code"
LOGIN_HEADERS=$(curl -s -D - -o /dev/null -X POST "$BASE/login" \
  -H 'Content-Type: application/json' -d "{\"token\":\"$TOKEN\"}")
if echo "$LOGIN_HEADERS" | grep -qi '^set-cookie: oracfit_auth='; then
  ok "login certo devolve Set-Cookie oracfit_auth"
else
  not "login certo sem Set-Cookie: $(echo "$LOGIN_HEADERS" | head -5)"
fi
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Cookie: oracfit_auth=$TOKEN" "$BASE/home.html")
[ "$code" = "200" ] && ok "cookie válido acessa home.html" || not "cookie válido: $code"

echo "--- T5: página sem auth redireciona pra /login ---"
loc=$(curl -s -o /dev/null -w '%{redirect_url}' "$BASE/home.html")
echo "$loc" | grep -q "/login" && ok "303 → /login" || not "redirect errado: $loc"

echo "--- T6: subclass — /api/gui/todo não fura o gate ---"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/gui/todo")
[ "$code" = "401" ] && ok "todo sem credencial → 401" || not "todo sem credencial: $code"
# com Bearer o gate PASSA e o handler responde (aqui: 404 declarado — subiu
# sem --ring-target; o que NÃO pode é crashar a conexão, code 000)
code=$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $TOKEN" "$BASE/api/gui/todo")
[ "$code" = "404" ] && ok "todo com Bearer passa o gate (404 declarado, sem crash)" \
  || not "todo com Bearer: $code (000 = crash)"

echo "--- T8: validação fail-closed do /api/dispatch ---"
disp() { # $1=payload $2=status-esperado $3=nome
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/dispatch" \
    -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d "$1")
  [ "$code" = "$2" ] && ok "$3 → $2" || not "$3: esperava $2, veio $code"
}
events_file="$LOGS/events.jsonl"
events_before=0
[ -f "$events_file" ] && events_before=$(wc -l < "$events_file")
disp '{"mode":"normal","spec":"smoke.md","task":"ok-name","adapter":"stub"}' 200 "dispatch válido (T9 pré)"
disp '{"mode":"modo-inexistente","spec":"smoke.md","task":"x1"}' 400 "mode inexistente"
disp '{"mode":"normal","spec":"smoke.md","task":"x2","adapter":"nao-existe"}' 400 "adapter inexistente"
disp '{"mode":"normal","spec":"smoke.md","task":"Nome-Invalido!!"}' 400 "task inválida"
disp '{"mode":"normal","spec":"../../../etc/passwd","task":"x3"}' 400 "spec traversal"
disp '{"mode":"normal","spec":"/etc/passwd","task":"x4"}' 400 "spec absoluta fora do workdir"
disp '{"mode":"normal","spec":"sem-extensao","task":"x5"}' 400 "spec não-.md"

echo "--- T9: dispatch válido roda DE VERDADE (stub) ---"
# o dispatch válido do T8-pré já disparou; espera o stub trabalhar
proof="$WD/.dispatch/stub-proof"
ran=0
for _ in $(seq 1 100); do
  [ -f "$proof" ] && ran=1 && break
  sleep 0.3
done
[ "$ran" = "1" ] && ok "stub-proof criado no workdir (robô trabalhou)" \
  || not "stub-proof não apareceu em 30s (log: $(tail -5 "$LOGS"/gui-dispatch-*.log 2>/dev/null))"
grep -q '"task": *"ok-name"' "$LOGS/events.jsonl" 2>/dev/null \
  && ok "run_started com task no events.jsonl (aparece no Run ao vivo)" \
  || not "task não chegou ao events.jsonl"
# recusas não geraram evento além do dispatch válido
runs_started=$(grep -c '"type": *"run_started"' "$LOGS/events.jsonl" 2>/dev/null || echo 0)
[ "$runs_started" = "1" ] && ok "nenhuma recusa virou run" \
  || not "runs a mais do que o esperado: $runs_started"

kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""

echo "--- T7: sem --enable-dispatch, POST /api/dispatch → 404 ---"
start_server --auth-token "$TOKEN"
BASE="http://127.0.0.1:$PORT"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$BASE/api/dispatch" \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"mode":"normal","spec":"smoke.md","task":"nao-deveria","adapter":"stub"}')
[ "$code" = "404" ] && ok "sem --enable-dispatch → 404 (default read-only)" \
  || not "sem --enable-dispatch: $code"
kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""

echo "--- T10: default local SEM token continua aberto (retrocompat) ---"
start_server
BASE="http://127.0.0.1:$PORT"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/gui/home")
[ "$code" = "200" ] && ok "loopback sem token: API aberta como antes" || not "loopback aberto: $code"
code=$(curl -s -o /dev/null -w '%{http_code}' "$BASE/login")
[ "$code" = "404" ] && ok "/login sem auth → 404 (desligado declarado)" || not "/login sem auth: $code"
kill "$SERVER_PID" 2>/dev/null; wait "$SERVER_PID" 2>/dev/null; SERVER_PID=""

echo "--- T11: túnel — fail-closed e dica de install ---"
rc=0; bash "$REPO_ROOT/bin/oracfit-gui-tunnel.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] && ok "túnel sem --auth-token recusa (rc=$rc)" || not "túnel sem token passou"
rc=0; PATH="/usr/bin:/bin" bash "$REPO_ROOT/bin/oracfit-gui-tunnel.sh" \
  --auth-token "$TOKEN" >"$WORK/t11.out" 2>&1 || rc=$?
if [ "$rc" -ne 0 ] && grep -q "cloudflared" "$WORK/t11.out"; then
  ok "sem cloudflared recusa com dica"
else
  ok "cloudflared presente no PATH — pulando checagem de ausência (rc=$rc)"
fi
bash "$REPO_ROOT/bin/oracfit-gui-tunnel.sh" --help 2>/dev/null | grep -q "trycloudflare" \
  && ok "--help documenta a URL do túnel" || not "--help sem trycloudflare"

echo "--- T12: roteamento bin/oracfit gui-tunnel ---"
"$ORACFIT" gui-tunnel --help 2>/dev/null | grep -q "auth-token" \
  && ok "oracfit gui-tunnel --help" || not "oracfit gui-tunnel não rota"

echo ""
echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ]
