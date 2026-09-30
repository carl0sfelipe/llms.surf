#!/usr/bin/env bash
# tests/test-cursor-stream.sh — adaptador cursor ao vivo (docs/stories/adapter-cursor-stream.md)
# cursor-agent falso no PATH reproduz a amostra real tests/fixtures/cursor-stream-sample.jsonl.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/adapters/cursor/runner.sh"
FIX="$REPO_ROOT/tests/fixtures/cursor-stream-sample.jsonl"
pass=0; fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

W=$(mktemp -d /tmp/test-cursor-stream.XXXXXX); trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/wd"
cat > "$W/bin/cursor-agent" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "$W/args"
[ -n "\${FAKE_OUT:-}" ] && { echo "\$FAKE_OUT"; exit 1; }
while IFS= read -r l; do printf '%s\n' "\$l"; sleep "\${FAKE_SLEEP:-0}"; done < "$FIX"
echo "linha que não é json"
EOF
chmod +x "$W/bin/cursor-agent"
printf '{"models":[{"id":"grok","cli_hints":{"cursor":"cursor-grok-4.6-xhigh-fast"}}]}' > "$W/reg.json"
echo "faça algo" > "$W/spec.md"
run() { PATH="$W/bin:$PATH" CURSOR_API_KEY=x MODEL_REGISTRY="$W/reg.json" ORACFIT_WORKDIR="$W/wd" "$@"; }
EV="$W/wd/.dispatch/logs/events.jsonl"
J() { python3 -c "import json,sys; ev=[json.loads(l) for l in open('$EV')]; $1"; }

echo "=== test-cursor-stream ==="
OUT=$(run env ORACFIT_RUN_ID=r1 bash "$RUNNER" grok "$W/spec.md"); RC=$?
[ $RC -eq 0 ] && ok "exit 0" || not "exit $RC"
grep -q -- '--output-format stream-json' "$W/args" && ok "chama com stream-json" || not "args: $(cat "$W/args")"
echo "$OUT" | grep -q '"type":"result"' && ok "linhas cruas repassadas no stdout" || not "stdout sem result"
echo "$OUT" | grep -q 'linha que não é json' && ok "linha não-JSON repassada" || not "linha não-JSON perdida"
J "t=[e for e in ev if e['type']=='tool_call']; assert [e['tool'] for e in t]==['read','edit'], t" 2>/dev/null && ok "2 tool_call: read, edit" || not "tool_call: $(cat "$EV" 2>/dev/null | head -5)"
J "t=[e for e in ev if e['type']=='tool_call']; assert t[0]['preview'].startswith('[read]') and 'a.txt' in t[0]['preview'] and 'b.txt' in t[1]['preview'] and all(len(e['preview'])<=160 for e in t)" 2>/dev/null && ok "preview com arquivo" || not "preview"
J "th=[e for e in ev if e['type']=='thinking']; assert len(th)==3 and 'a.txt' in th[0]['detail'] and all(len(e['detail'])<=200 for e in th)" 2>/dev/null && ok "3 thinking acumulados" || not "thinking"
J "m=[e for e in ev if e['type']=='metric' and e.get('name')=='cursor_usage']; assert len(m)==1 and str(m[0]['input_tokens'])=='13279' and str(m[0]['output_tokens'])=='138' and str(m[0]['cache_read_tokens'])=='26048' and str(m[0]['duration_ms'])=='9260'" 2>/dev/null && ok "metric cursor_usage" || not "cursor_usage"
J "assert all(e['v']==1 and e['run_id']=='r1' and e['ts'] for e in ev)" 2>/dev/null && ok "formato do lib-oracfit-events" || not "formato"

echo "--- ao vivo ---"
rm -f "$EV"
( run env ORACFIT_RUN_ID=r2 FAKE_SLEEP=0.3 bash "$RUNNER" grok "$W/spec.md" >/dev/null ) &
BG=$!
sleep 4
kill -0 $BG 2>/dev/null && grep -q '"tool_call"' "$EV" 2>/dev/null && ok "tool_call aparece antes do fim do run" || not "eventos só no fim (bufferizado)"
wait $BG

echo "--- sem run id / modos / exit codes ---"
rm -rf "$W/wd/.dispatch"
run bash "$RUNNER" grok "$W/spec.md" >/dev/null; RC=$?
[ $RC -eq 0 ] && [ ! -f "$EV" ] && ok "sem ORACFIT_RUN_ID não grava eventos" || not "gravou sem run id (rc=$RC)"
run env DISPATCH_RUNNER_FORMAT_JSON=0 bash "$RUNNER" grok "$W/spec.md" >/dev/null
grep -q -- '--output-format' "$W/args" && not "modo texto passou --output-format" || ok "FORMAT_JSON=0 sem --output-format"
run env FAKE_OUT="Error: 429 rate limit" bash "$RUNNER" grok "$W/spec.md" >/dev/null; RC=$?
[ $RC -eq 2 ] && ok "rate limit exit 2" || not "rate limit rc=$RC"
run env FAKE_OUT="boom" bash "$RUNNER" grok "$W/spec.md" >/dev/null; RC=$?
[ $RC -eq 1 ] && ok "falha do cursor-agent exit 1 (PIPESTATUS)" || not "exit perdido no pipe rc=$RC"

echo "=== resultado: $pass PASS, $fail FAIL ==="
[ "$fail" -eq 0 ] && echo "PASS test-cursor-stream"
[ "$fail" -eq 0 ]
