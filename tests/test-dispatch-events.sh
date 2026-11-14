#!/usr/bin/env bash
# tests/test-dispatch-events.sh — the simple dispatch announces the run and
# the finalizer closes it, so the panel can show a live run.
#
# Hermetic: workdir, LOG_DIR, PID_DIR, LEDGER_DIR, ORACFIT_USAGE_DIR and
# ORACFIT_USO_DIR live under a temp directory. A fake runner exits 0 (or 1
# when the proof asks). No network, no model, no GPU.
# Do not run this suite in parallel with another suite that dispatches in
# the same repository: bin/dispatch.sh refuses a second dispatch on the
# same repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISPATCH="$REPO_ROOT/bin/dispatch.sh"

WORKDIR="$(mktemp -d /tmp/test-dispatch-events.XXXXXX)"
cleanup() {
  if [ -d "$WORKDIR" ]; then
    for f in "$WORKDIR"/*/pids/dispatch-*.pid; do
      [ -f "$f" ] || continue
      pid=$(cat "$f" 2>/dev/null || true)
      if [ -n "${pid:-}" ]; then
        kill -9 -"$pid" 2>/dev/null || true
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
  fi
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

# A parent dispatch may export these; this suite must not inherit them.
unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID ORACFIT_WORKDIR
unset DB_PATH CAPABILITIES_FILE DISPATCH_ARTEFATO ORACFIT_NTFY_TOPIC
unset LEDGER_DIR ORACFIT_USAGE_DIR ORACFIT_USO_DIR

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

write_spec() {
  cat >"$1" <<'EOF'
# Task: mark the target

Do not invent numbers, dates or sources beyond those listed.
Never use declare const as a workaround — import for real.

## Verified data
- alvo.txt exists in the workdir (verified)

## Verification
VERIFICATION: grep -q done alvo.txt

## Oracle
- command: grep -q done alvo.txt
- expected exit: 0
EOF
}

setup_wd() {
  local dest="$1"
  mkdir -p "$dest/logs" "$dest/pids" "$dest/ledger" "$dest/usage" "$dest/uso"
  printf '%s\n' "not yet" >"$dest/alvo.txt"
  write_spec "$dest/spec.md"
  ( cd "$dest" && git init -q . \
    && git config user.email events@test.dev \
    && git config user.name EventsTest ) >/dev/null
}

write_ok_runner() {
  cat >"$1" <<'EOF'
#!/bin/bash
printf '%s\n' "done" > alvo.txt
exit 0
EOF
  chmod +x "$1"
}

write_fail_runner() {
  cat >"$1" <<'EOF'
#!/bin/bash
exit 1
EOF
  chmod +x "$1"
}

run_dispatch() {
  local dest="$1"
  local model="$2"
  local task="$3"
  local runner="$4"
  ( cd "$dest" && env -u DB_PATH -u ORACFIT_EVENTS_FILE -u ORACFIT_RUN_ID \
      -u ORACFIT_WORKDIR -u CAPABILITIES_FILE -u DISPATCH_ARTEFATO \
      -u ORACFIT_NTFY_TOPIC \
      DISPATCH_RUNNER="$runner" \
      LOG_DIR="$dest/logs" \
      PID_DIR="$dest/pids" \
      LEDGER_DIR="$dest/ledger" \
      ORACFIT_USAGE_DIR="$dest/usage" \
      ORACFIT_USO_DIR="$dest/uso" \
      DISPATCH_USAGE_FEEDBACK=0 \
      DISPATCH_TIMEOUT=60 \
      DISPATCH_SILENT_LIMIT=45 \
      bash "$DISPATCH" "$model" "$dest/spec.md" "$task" )
}

wait_for_file() {
  local path="$1"
  local deadline=$((SECONDS + ${2:-30}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -s "$path" ]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_for_started() {
  local path="$1"
  local deadline=$((SECONDS + ${2:-15}))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if [ -f "$path" ] && grep -q '"type": "run_started"' "$path"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

events_jsonl() {
  printf '%s\n' "$1/.dispatch/logs/events.jsonl"
}

echo "=== test-dispatch-events ==="

# ── 1. the simple dispatch announces the run ────────────────────────────────
echo "== 1. the simple dispatch announces the run"
P1="$WORKDIR/p1"
setup_wd "$P1"
write_ok_runner "$P1/runner.sh"
P1_RC=0
run_dispatch "$P1" fake-model announce-run "$P1/runner.sh" \
  >"$P1/dispatch.out" 2>"$P1/dispatch.err" || P1_RC=$?
P1_EV="$(events_jsonl "$P1")"
wait_for_started "$P1_EV" 15 || true
if [ "$P1_RC" -eq 0 ] && python3 - "$P1_EV" announce-run fake-model <<'PY'
import json, sys
path, task, model = sys.argv[1:4]
raw = open(path, encoding="utf-8").read().splitlines()
started = [json.loads(l) for l in raw if json.loads(l).get("type") == "run_started"]
assert started, "no run_started"
ev = started[0]
assert ev.get("task") == task, ev
assert ev.get("model_id") == model, ev
assert ev.get("run_id") == task, ev
PY
then
  ok "the simple dispatch announces the run"
else
  not "the simple dispatch announces the run (rc=$P1_RC events=$(cat "$P1_EV" 2>/dev/null) err=$(head -c 400 "$P1/dispatch.err" 2>/dev/null))"
fi
wait_for_file "$P1/ledger/ledger.jsonl" 30 || true

# ── 2. the run closes with a finished event ─────────────────────────────────
echo "== 2. the run closes with a finished event"
P2="$WORKDIR/p2"
setup_wd "$P2"
write_ok_runner "$P2/runner.sh"
P2_RC=0
run_dispatch "$P2" fake-model close-run "$P2/runner.sh" \
  >"$P2/dispatch.out" 2>"$P2/dispatch.err" || P2_RC=$?
P2_EV="$(events_jsonl "$P2")"
wait_for_file "$P2/ledger/ledger.jsonl" 30 || true
# The finished event is written after the ledger row; give it a brief moment.
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$P2_EV" ] && grep -q '"type": "run_finished"' "$P2_EV"; then
    break
  fi
  sleep 0.1
done
if [ "$P2_RC" -eq 0 ] && python3 - "$P2_EV" close-run <<'PY'
import json, sys
path, task = sys.argv[1:3]
raw = open(path, encoding="utf-8").read().splitlines()
events = [json.loads(l) for l in raw]
started = [e for e in events if e.get("type") == "run_started"]
finished = [e for e in events if e.get("type") == "run_finished"]
assert started, "no run_started"
assert finished, "no run_finished"
assert len(finished) == 1, finished
assert started[0].get("run_id") == task, started[0]
assert finished[0].get("run_id") == started[0].get("run_id"), (started[0], finished[0])
assert finished[0].get("status") == "pass", finished[0]
PY
then
  ok "the run closes with a finished event"
else
  not "the run closes with a finished event (rc=$P2_RC events=$(cat "$P2_EV" 2>/dev/null) err=$(head -c 400 "$P2/dispatch.err" 2>/dev/null))"
fi

# ── 3. a failed run closes as fail ──────────────────────────────────────────
echo "== 3. a failed run closes as fail"
P3="$WORKDIR/p3"
setup_wd "$P3"
write_fail_runner "$P3/runner.sh"
P3_RC=0
run_dispatch "$P3" fake-model fail-run "$P3/runner.sh" \
  >"$P3/dispatch.out" 2>"$P3/dispatch.err" || P3_RC=$?
P3_EV="$(events_jsonl "$P3")"
wait_for_file "$P3/ledger/ledger.jsonl" 30 || true
deadline=$((SECONDS + 10))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -f "$P3_EV" ] && grep -q '"type": "run_finished"' "$P3_EV"; then
    break
  fi
  sleep 0.1
done
if [ "$P3_RC" -eq 0 ] && python3 - "$P3_EV" <<'PY'
import json, sys, re
path = sys.argv[1]
raw = open(path, encoding="utf-8").read().splitlines()
finished = [json.loads(l) for l in raw if json.loads(l).get("type") == "run_finished"]
assert finished, "no run_finished"
ev = finished[0]
assert ev.get("status") == "fail", ev
reason = ev.get("reason") or ""
assert reason, ev
assert re.fullmatch(r"[A-Za-z0-9_]+", reason), ev
PY
then
  ok "a failed run closes as fail"
else
  not "a failed run closes as fail (rc=$P3_RC events=$(cat "$P3_EV" 2>/dev/null) err=$(head -c 400 "$P3/dispatch.err" 2>/dev/null))"
fi

# ── 4. the run is alive while the runner works ──────────────────────────────
echo "== 4. the run is alive while the runner works"
P4="$WORKDIR/p4"
setup_wd "$P4"
HOLD="$P4/hold"
touch "$HOLD"
cat >"$P4/runner.sh" <<EOF
#!/bin/bash
while [ -f "$HOLD" ]; do
  sleep 0.1
done
printf '%s\n' "done" > alvo.txt
exit 0
EOF
chmod +x "$P4/runner.sh"
P4_RC=0
run_dispatch "$P4" fake-model alive-run "$P4/runner.sh" \
  >"$P4/dispatch.out" 2>"$P4/dispatch.err" || P4_RC=$?
P4_EV="$(events_jsonl "$P4")"
wait_for_started "$P4_EV" 15 || true
P4_PID=""
if [ -f "$P4/pids/dispatch-alive-run.pid" ]; then
  P4_PID=$(cat "$P4/pids/dispatch-alive-run.pid" 2>/dev/null || true)
fi
P4_ALIVE=0
if [ -n "$P4_PID" ] && kill -0 "$P4_PID" 2>/dev/null; then
  P4_ALIVE=1
fi
if [ "$P4_RC" -eq 0 ] && [ "$P4_ALIVE" -eq 1 ] && python3 - "$P4_EV" <<'PY'
import json, sys
path = sys.argv[1]
raw = open(path, encoding="utf-8").read().splitlines()
events = [json.loads(l) for l in raw]
started = [e for e in events if e.get("type") == "run_started"]
finished = [e for e in events if e.get("type") == "run_finished"]
assert started, "no run_started"
assert not finished, "run_finished arrived while the runner still works"
PY
then
  ok "the run is alive while the runner works"
else
  not "the run is alive while the runner works (rc=$P4_RC alive=$P4_ALIVE pid=$P4_PID events=$(cat "$P4_EV" 2>/dev/null) err=$(head -c 400 "$P4/dispatch.err" 2>/dev/null))"
fi
rm -f "$HOLD"
wait_for_file "$P4/ledger/ledger.jsonl" 30 || true

# ── 5. the event never breaks the run ───────────────────────────────────────
echo "== 5. the event never breaks the run"
P5="$WORKDIR/p5"
setup_wd "$P5"
write_ok_runner "$P5/runner.sh"
mkdir -p "$P5/.dispatch/logs/events.jsonl"
P5_RC=0
run_dispatch "$P5" fake-model unbreakable-run "$P5/runner.sh" \
  >"$P5/dispatch.out" 2>"$P5/dispatch.err" || P5_RC=$?
wait_for_file "$P5/ledger/ledger.jsonl" 30 || true
if [ "$P5_RC" -eq 0 ] && [ -s "$P5/ledger/ledger.jsonl" ]; then
  ok "the event never breaks the run"
else
  not "the event never breaks the run (rc=$P5_RC ledger=$(ls -l "$P5/ledger/ledger.jsonl" 2>/dev/null || true) err=$(head -c 400 "$P5/dispatch.err" 2>/dev/null))"
fi

echo
echo "test-dispatch-events: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
