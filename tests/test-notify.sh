#!/bin/bash
# tests/test-notify.sh — S9: o grito da praia, provado SEM rede externa.
#
# Fake server local (python3 http.server em 127.0.0.1) grava cada POST;
# nada sai da máquina. Contrato da spec S9 (docs/go-live/specs/S9-ntfy-run-notify.md):
#   (a) tópico unset  → nenhum POST (opt-in; silêncio absoluto)
#   (b) run_finished  → EXATAMENTE um POST terso com run_id e status,
#                       roteado no tópico, sem vazar caminho do workdir
#   (c) servidor morto → exit de quem emitiu intocado (advisory, nunca gate)
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/oracfit-notify-test.XXXXXX)"
RECORD="$TMP/posts.txt"
cleanup() { [ -n "${SRV_PID:-}" ] && kill "$SRV_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

pas=0
falhas=0
ok()  { echo "PASS: $1"; pas=$((pas + 1)); }
not() { echo "FAIL: $1"; falhas=$((falhas + 1)); }

# ── fake ntfy: grava path + body de cada POST ───────────────────────────────
cat >"$TMP/server.py" <<'PY'
import http.server, sys
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n).decode('utf-8', 'replace')
        with open(sys.argv[2], 'a', encoding='utf-8') as f:
            f.write(self.path + '\n' + body + '\n---\n')
        self.send_response(200)
        self.end_headers()
    def log_message(self, *a):
        pass
http.server.HTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
PY
PORT="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')"
python3 "$TMP/server.py" "$PORT" "$RECORD" >/dev/null 2>&1 &
SRV_PID=$!
for _ in $(seq 1 40); do
  python3 -c "import socket; socket.create_connection(('127.0.0.1', $PORT), 0.2)" 2>/dev/null && break
  sleep 0.1
done
export ORACFIT_NTFY_URL="http://127.0.0.1:$PORT"
export ORACFIT_WORKDIR="$TMP"
export ORACFIT_RUN_ID="run-notify-t1"

emitir() {  # emitir <type> [key=val...]
  ( source "$ROOT/bin/lib-oracfit-events.sh" && oracfit_emit_event "$@" )
}

# ═══ (a) tópico unset → nenhum POST ═══
unset ORACFIT_NTFY_TOPIC
emitir run_finished status=pass task=t-a
if [ ! -s "$RECORD" ]; then
  ok "tópico unset: silêncio absoluto (nenhum POST)"
else
  not "tópico unset produziu POST"
fi

# ═══ (b) run_finished → exatamente 1 POST terso, no tópico ═══
export ORACFIT_NTFY_TOPIC="topico-secreto-do-teste"
emitir run_finished status=pass task=t-b
n_posts="$(grep -c '^---$' "$RECORD" 2>/dev/null || true)"
n_posts="${n_posts:-0}"
body="$(sed -n 2p "$RECORD" 2>/dev/null)"
path_line="$(sed -n 1p "$RECORD" 2>/dev/null)"
if [ "$n_posts" -eq 1 ]; then
  ok "exatamente um POST por evento terminal"
else
  not "esperava 1 POST, vieram $n_posts"
fi
if printf '%s' "$body" | grep -q "run-notify-t1" && printf '%s' "$body" | grep -q "pass"; then
  ok "corpo terso com run_id e status"
else
  not "corpo sem run_id/status: '$body'"
fi
if [ "$path_line" = "/topico-secreto-do-teste" ]; then
  ok "roteado no tópico"
else
  not "path errado: '$path_line'"
fi
if printf '%s' "$body" | grep -q "$TMP"; then
  not "corpo vaza caminho do workdir"
else
  ok "nenhum caminho do workdir no corpo"
fi

# ═══ (c) servidor morto → exit do emissor intocado ═══
kill "$SRV_PID" 2>/dev/null
wait "$SRV_PID" 2>/dev/null
SRV_PID=""
( source "$ROOT/bin/lib-oracfit-events.sh" \
    && oracfit_emit_event run_finished status=fail task=t-c >/dev/null 2>&1; exit 7 )
rc=$?
if [ "$rc" -eq 7 ]; then
  ok "ntfy morto não mudou o exit do chamador (7 preservado)"
else
  not "notify morto contaminou o exit: $rc"
fi
# e o evento foi emitido mesmo assim (o funil não depende do notify)
if grep -q '"type": "run_finished"' "$TMP/.dispatch/logs/events.jsonl" 2>/dev/null \
   || grep -q '"type":"run_finished"' "$TMP/.dispatch/logs/events.jsonl" 2>/dev/null; then
  ok "eventos seguem gravados com notify morto"
else
  not "funil de eventos parou com notify morto"
fi

echo ""
echo "resultado: $pas pass, $falhas fail"
[ "$falhas" -eq 0 ]
