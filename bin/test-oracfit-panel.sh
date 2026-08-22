#!/bin/bash
# test-oracfit-panel.sh — Epic 2 smoke (observe-only panel, v3 events)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PORT=18765
WORKDIR=$(mktemp -d)
LOGS="$WORKDIR/.dispatch/logs"
mkdir -p "$LOGS"

cleanup() {
  if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

echo "── Oracfit panel smoke ──"

# Seed v3 events: pass run with pipeline + fail run with preflight/loop-back
cat > "$LOGS/events.jsonl" <<'EOF'
{"v":1,"ts":"2026-08-11T20:00:00Z","run_id":"run-aaa-pass","type":"classify_result","class":"MECANICO_TRANSFORM","allowed":"true"}
{"v":1,"ts":"2026-08-11T20:00:01Z","run_id":"run-aaa-pass","type":"preflight_result","step":"check-spec","pass":"true","reason":"ok"}
{"v":1,"ts":"2026-08-11T20:00:02Z","run_id":"run-aaa-pass","type":"run_started","mode":"content_factory","stage":"multi","task":"smoke-pass","stages":"4","model_id":"deepseek/deepseek-v4-flash-direct"}
{"v":1,"ts":"2026-08-11T20:00:03Z","run_id":"run-aaa-pass","type":"stage_changed","stage":"run","index":"0"}
{"v":1,"ts":"2026-08-11T20:00:04Z","run_id":"run-aaa-pass","type":"attempt_started","attempt":"1","mode":"content_factory"}
{"v":1,"ts":"2026-08-11T20:00:05Z","run_id":"run-aaa-pass","type":"tool_call","tool":"read","preview":"[read] specs/smoke.md","cmd_exit":"0"}
{"v":1,"ts":"2026-08-11T20:00:06Z","run_id":"run-aaa-pass","type":"thinking","detail":"verificando spec antes do oracle"}
{"v":1,"ts":"2026-08-11T20:00:07Z","run_id":"run-aaa-pass","type":"oracle_result","exit":"0","attempt":"1","stage":"run","command":"from-spec"}
{"v":1,"ts":"2026-08-11T20:00:08Z","run_id":"run-aaa-pass","type":"stage_changed","stage":"export","index":"1"}
{"v":1,"ts":"2026-08-11T20:00:09Z","run_id":"run-aaa-pass","type":"oracle_result","exit":"0","attempt":"1","stage":"export","command":"export-bundle"}
{"v":1,"ts":"2026-08-11T20:00:10Z","run_id":"run-aaa-pass","type":"attempt_finished","attempt":"1","duration_s":"12.5","runner_exit":"0"}
{"v":1,"ts":"2026-08-11T20:00:11Z","run_id":"run-aaa-pass","type":"metric","mode_id":"content_factory","stage":"multi","oracle_exit":"0","attempt":"1","flash_work_s":"12.5","frontier_wait_s":"0","estimated_cost":"0","task":"smoke-pass","status":"pass"}
{"v":1,"ts":"2026-08-11T20:00:12Z","run_id":"run-aaa-pass","type":"run_finished","status":"pass","attempt":"1","duration_s":"12.5","oracle_exit":"0","stages":"4"}
{"v":1,"ts":"2026-08-11T21:00:00Z","run_id":"run-bbb-fail","type":"run_started","mode":"content_factory","stage":"multi","task":"smoke-fail","stages":"4"}
{"v":1,"ts":"2026-08-11T21:00:01Z","run_id":"run-bbb-fail","type":"stage_changed","stage":"run","index":"0"}
{"v":1,"ts":"2026-08-11T21:00:02Z","run_id":"run-bbb-fail","type":"preflight_result","step":"check-oracle","pass":"false","reason":"lint-error","oracle_exit":"2","oracle_lint":"1"}
{"v":1,"ts":"2026-08-11T21:00:03Z","run_id":"run-bbb-fail","type":"attempt_started","attempt":"1","mode":"content_factory"}
{"v":1,"ts":"2026-08-11T21:00:04Z","run_id":"run-bbb-fail","type":"oracle_result","exit":"1","attempt":"1","stage":"run","command":"from-spec"}
{"v":1,"ts":"2026-08-11T21:00:05Z","run_id":"run-bbb-fail","type":"stage_changed","stage":"vision_gate","index":"3"}
{"v":1,"ts":"2026-08-11T21:00:06Z","run_id":"run-bbb-fail","type":"oracle_result","exit":"1","attempt":"2","stage":"vision_gate","command":"vision-check"}
{"v":1,"ts":"2026-08-11T21:00:07Z","run_id":"run-bbb-fail","type":"gauntlet_loop_back","from":"vision_gate","to":"export","count":"3","ceiling":"4"}
{"v":1,"ts":"2026-08-11T21:00:08Z","run_id":"run-bbb-fail","type":"metric","mode_id":"content_factory","stage":"multi","oracle_exit":"1","attempt":"2","flash_work_s":"45.2","frontier_wait_s":"0","estimated_cost":"0","task":"smoke-fail","status":"fail"}
{"v":1,"ts":"2026-08-11T21:00:09Z","run_id":"run-bbb-fail","type":"run_finished","status":"fail","reason":"oracle_fail","attempt":"2","duration_s":"45.2","oracle_exit":"1","stages":"4"}
EOF

export ORACFIT_ROOT="$ROOT"
python3 "$ROOT/bin/oracfit-panel-server.py" \
  --panel-dir "$ROOT/panel" \
  --logs-dir "$LOGS" \
  --port "$PORT" \
  --bind 127.0.0.1 &
SERVER_PID=$!

# wait for listen
for i in 1 2 3 4 5 6 7 8 9 10; do
  if curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

HTML=$(curl -sf "http://127.0.0.1:$PORT/")
echo "$HTML" | grep -q "Oracfit — Carlos Felipe"
echo "$HTML" | grep -q 'id="metric-bar"'
echo "$HTML" | grep -q 'id="session-bar"'
echo "$HTML" | grep -q 'observe-only'

CFG=$(curl -sf "http://127.0.0.1:$PORT/runtime-config.json")
echo "$CFG" | grep -q '"observe_only": false'
echo "$CFG" | grep -q '"hitl_v1": true'
echo "$CFG" | grep -q '/logs/events.jsonl'

EV=$(curl -sf "http://127.0.0.1:$PORT/logs/events.jsonl")
echo "$EV" | grep -q 'run-aaa-pass'
echo "$EV" | grep -q 'flash_work_s'

# CSS/JS present
CSS=$(curl -sf "http://127.0.0.1:$PORT/styles.css")
echo "$CSS" | grep -q -- '--metric'
JS=$(curl -sf "http://127.0.0.1:$PORT/app.js")
echo "$JS" | grep -q 'POLL_MS'
echo "$JS" | grep -q 'observe-only'

# path traversal blocked (should 404 or empty denied)
CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/logs/../../etc/passwd" || true)
test "$CODE" != "200" || { echo "FAIL: path traversal leaked"; exit 1; }

# cold empty logs dir still serves panel
EMPTY=$(mktemp -d)
python3 "$ROOT/bin/oracfit-panel-server.py" \
  --panel-dir "$ROOT/panel" \
  --logs-dir "$EMPTY/.dispatch/logs" \
  --port $((PORT+1)) \
  --bind 127.0.0.1 &
PID2=$!
sleep 0.4
curl -sf "http://127.0.0.1:$((PORT+1))/" | grep -q "Oracfit"
CODE404=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$((PORT+1))/logs/events.jsonl" || true)
# empty file may 404 — panel JS treats 404 as cold
test "$CODE404" = "404" -o "$CODE404" = "200"
kill "$PID2" 2>/dev/null || true
wait "$PID2" 2>/dev/null || true
rm -rf "$EMPTY"

# wrapper script help
bash "$ROOT/bin/oracfit-panel.sh" --help | grep -qi observe-only

# gauntlet log tail API
GAUNTLET="$LOGS/inbox/run-aaa-111.run.gauntlet"
mkdir -p "$GAUNTLET"
cat > "$GAUNTLET/mech-1.log" <<'LOGEOF'
2026-08-11 20:00:00 | INFO | BMADCrew | Starting hierarchical execution
2026-08-11 20:00:01 | INFO | BMADCrew | Executing task: T2-JUDGE with agent: test-auditor
2026-08-11 20:00:02 | INFO | BMADCrew | Checkpoint saved
LOGEOF

RUNFILES=$(curl -sf "http://127.0.0.1:$PORT/api/runfiles?run_id=run-aaa-111")
echo "$RUNFILES" | grep -q 'mech-1.log'

TAIL=$(curl -sf "http://127.0.0.1:$PORT/api/tail?run_id=run-aaa-111&file=mech-1.log")
echo "$TAIL" | grep -q 'T2-JUDGE'

TRAV_CODE=$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$PORT/api/tail?run_id=run-aaa-111&file=../../etc/passwd" || true)
test "$TRAV_CODE" != "200" || { echo "FAIL: tail traversal leaked"; exit 1; }

echo "✅ panel smoke PASS"
exit 0
