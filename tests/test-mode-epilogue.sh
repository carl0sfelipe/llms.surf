#!/bin/bash
# test-mode-epilogue.sh — the single-stage runtime must close its own evidence
# when it dies. Hermetic: temp workdir, fake runner, no network, no model call,
# never touches the real .dispatch/ of this checkout.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$ROOT/bin/dispatch-mode.sh"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-mode-epilogue.XXXXXX")"
cleanup() {
  if [ -n "${KILL_PID:-}" ]; then
    kill -TERM "$KILL_PID" 2>/dev/null || true
    wait "$KILL_PID" 2>/dev/null || true
  fi
  if [ -n "${RUNNER_PID_FILE:-}" ] && [ -f "$RUNNER_PID_FILE" ]; then
    kill "$(cat "$RUNNER_PID_FILE")" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

export ORACFIT_ROOT="$ROOT"
export DISPATCH_USAGE_FEEDBACK=0
unset DISPATCH_MODEL_REF
unset ORACFIT_WORKDIR
unset ORACFIT_EVENTS_FILE
unset ORACFIT_NTFY_TOPIC
unset ORACFIT_RUN_ID

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Count JSONL rows matching key=val filters (python3, not a prose grep).
count_jsonl() {
  python3 -c '
import json, sys
path = sys.argv[1]
filters = {}
for arg in sys.argv[2:]:
    k, v = arg.split("=", 1)
    filters[k] = v
n = 0
try:
    fh = open(path)
except OSError:
    print(0)
    raise SystemExit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    if all(str(obj.get(k, "")) == v for k, v in filters.items()):
        n += 1
print(n)
' "$@"
}

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Mode epilogue fixture

## Objetivo
Nao invente numero, prazo, citacao ou fonte alem dos listados.

## Dados verificados
O fixture nao precisa de fatos numericos.

## Verificacao
test -f marker.txt && grep -q "work done" marker.txt

## Oraculo
- comando: test -f marker.txt && grep -q "work done" marker.txt
- exit esperado: 0

## Barra
- nome: mode epilogue fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
wd="${ORACFIT_WORKDIR:-$PWD}"
printf '%s\n' "$$" >"$wd/runner.pid"
if [ -f "$wd/block" ]; then
  # stdout must not be the pipe to thinking-tee: a child sleep that inherits
  # that fd keeps the pipeline open after this runner is killed, and bash
  # defers the dispatcher TERM trap until the pipeline ends.
  sleep 8 >/dev/null 2>&1
  exit 0
fi
printf 'work done\n' >"$wd/marker.txt"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

write_mode() {
  mkdir -p "$1/core/modes"
  cat >"$1/core/modes/epilogue-fixture.yaml" <<'YAML'
id: epilogue-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    max_attempts: 1
on_fail: halt
YAML
}

# ── happy path: exactly one run_finished pass, exactly one ledger row ────────
HAPPY="$TMPDIR/happy"
mkdir -p "$HAPPY"
write_mode "$HAPPY"
cp "$SPEC" "$HAPPY/spec.md"
happy_rc=0
HAPPY_OUT="$(
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" epilogue-fixture "$HAPPY/spec.md" epilogue-happy \
    --workdir "$HAPPY" 2>&1
)" || happy_rc=$?
HAPPY_EVENTS="$HAPPY/.dispatch/logs/events.jsonl"
HAPPY_LEDGER="$HAPPY/.dispatch/ledger/mode.jsonl"

n_finished=$(count_jsonl "$HAPPY_EVENTS" type=run_finished)
n_pass=$(count_jsonl "$HAPPY_EVENTS" type=run_finished status=pass)
n_abn=$(count_jsonl "$HAPPY_EVENTS" type=run_finished reason=abnormal_exit)
n_ledger=$(count_jsonl "$HAPPY_LEDGER")
if [ "$happy_rc" -eq 0 ] && [ "$n_finished" -eq 1 ] && [ "$n_pass" -eq 1 ]; then
  ok "happy path emits exactly one run_finished with status=pass"
else
  not "happy path run_finished (rc=$happy_rc n_finished=$n_finished n_pass=$n_pass): $HAPPY_OUT"
fi
if [ "$n_ledger" -eq 1 ]; then
  ok "happy path leaves exactly one ledger row"
else
  not "happy path ledger rows=$n_ledger (expected 1)"
fi
if [ "$n_finished" -eq 1 ] && [ "$n_abn" -eq 0 ]; then
  ok "happy path does not add a second run_finished from the epilogue"
else
  not "happy path duplicate/abnormal run_finished (n_finished=$n_finished n_abn=$n_abn)"
fi

# ── preflight reject: no ledger row and no run_finished ─────────────────────
# Oracle `true` already passes, so oracfit_preflight returns 1 (already-passes)
# and the dispatcher exits before the run starts. The epilogue traps must not
# be armed yet — otherwise EXIT writes a ghost ledger row (T2 of
# tests/test-tuned-measure.sh).
PF="$TMPDIR/preflight-fail"
mkdir -p "$PF"
write_mode "$PF"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$PF/spec.md" <<'EOF'
# Mode epilogue preflight fixture

## Objetivo
Nao invente numero, prazo, citacao ou fonte alem dos listados.

## Dados verificados
O fixture nao precisa de fatos numericos.

## Verificacao
test -f marker.txt && grep -q "work done" marker.txt

## Oraculo
- comando: true
- exit esperado: 0

## Barra
- nome: mode epilogue preflight fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end
pf_rc=0
PF_OUT="$(
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" epilogue-fixture "$PF/spec.md" epilogue-preflight \
    --workdir "$PF" 2>&1
)" || pf_rc=$?
PF_EVENTS="$PF/.dispatch/logs/events.jsonl"
PF_LEDGER="$PF/.dispatch/ledger/mode.jsonl"
n_pf_finished=$(count_jsonl "$PF_EVENTS" type=run_finished)
n_pf_ledger=$(count_jsonl "$PF_LEDGER")
if [ "$pf_rc" -ne 0 ] && [ "$n_pf_finished" -eq 0 ]; then
  ok "preflight reject emits no run_finished"
else
  not "preflight reject run_finished (rc=$pf_rc n_finished=$n_pf_finished): $PF_OUT"
fi
if [ "$n_pf_ledger" -eq 0 ]; then
  ok "preflight reject leaves no ledger row"
else
  not "preflight reject ledger rows=$n_pf_ledger (expected 0)"
fi

# ── abnormal exit: SIGTERM mid-runner ───────────────────────────────────────
KILL_DIR="$TMPDIR/kill"
mkdir -p "$KILL_DIR"
write_mode "$KILL_DIR"
cp "$SPEC" "$KILL_DIR/spec.md"
: >"$KILL_DIR/block"
KILL_EVENTS="$KILL_DIR/.dispatch/logs/events.jsonl"
KILL_LEDGER="$KILL_DIR/.dispatch/ledger/mode.jsonl"
DISPATCH_RUNNER="$FAKE_RUNNER" \
  "$MODE" epilogue-fixture "$KILL_DIR/spec.md" epilogue-kill \
  --workdir "$KILL_DIR" >"$KILL_DIR/out.log" 2>"$KILL_DIR/err.log" &
KILL_PID=$!
RUNNER_PID_FILE="$KILL_DIR/runner.pid"
ready=0
for _ in $(seq 1 80); do
  if [ -f "$RUNNER_PID_FILE" ]; then
    ready=1
    break
  fi
  sleep 0.1
done
if [ "$ready" -ne 1 ]; then
  not "abnormal exit: dispatcher never started the fake runner (out=$(cat "$KILL_DIR/out.log" 2>/dev/null) err=$(cat "$KILL_DIR/err.log" 2>/dev/null))"
else
  # Bash defers a TERM trap until the foreground pipeline ends. SIGTERM the
  # dispatcher (the trap stays pending) and stop the fake runner so that
  # pipeline can finish and the trap can run.
  rpid=""
  [ -f "$RUNNER_PID_FILE" ] && rpid="$(cat "$RUNNER_PID_FILE")"
  kill -TERM "$KILL_PID" 2>/dev/null || true
  if [ -n "$rpid" ]; then
    kill -TERM "$rpid" 2>/dev/null || true
    # Sleep child of the fake runner, if it is still alive.
    for c in $(ps -eo pid=,ppid= 2>/dev/null | awk -v p="$rpid" '$2==p {print $1}'); do
      kill -TERM "$c" 2>/dev/null || true
    done
  fi
  kill_rc=0
  wait "$KILL_PID" || kill_rc=$?
  KILL_PID=""
  if [ -n "$rpid" ]; then
    kill -TERM "$rpid" 2>/dev/null || true
  fi
  n_fail=$(count_jsonl "$KILL_EVENTS" type=run_finished status=fail reason=abnormal_exit)
  n_kill_finished=$(count_jsonl "$KILL_EVENTS" type=run_finished)
  n_kill_ledger=$(count_jsonl "$KILL_LEDGER")
  n_kill_ledger_fail=$(count_jsonl "$KILL_LEDGER" status=fail)
  if [ "$n_kill_finished" -eq 1 ] && [ "$n_fail" -eq 1 ]; then
    ok "abnormal exit emits exactly one run_finished status=fail reason=abnormal_exit"
  else
    not "abnormal exit events (rc=$kill_rc n_finished=$n_kill_finished n_fail=$n_fail): $(cat "$KILL_DIR/out.log" 2>/dev/null) $(cat "$KILL_DIR/err.log" 2>/dev/null)"
  fi
  if [ "$n_kill_ledger" -eq 1 ] && [ "$n_kill_ledger_fail" -eq 1 ]; then
    ok "abnormal exit leaves exactly one ledger row with status=fail"
  else
    not "abnormal exit ledger rows=$n_kill_ledger fail_rows=$n_kill_ledger_fail"
  fi

  # ── lock released: a second dispatch in the same workdir is not exit 6 ──
  rm -f "$KILL_DIR/block" "$KILL_DIR/marker.txt" "$KILL_DIR/runner.pid"
  second_rc=0
  SECOND_OUT="$(
    DISPATCH_RUNNER="$FAKE_RUNNER" \
      "$MODE" epilogue-fixture "$KILL_DIR/spec.md" epilogue-second \
      --workdir "$KILL_DIR" 2>&1
  )" || second_rc=$?
  if [ "$second_rc" -ne 6 ]; then
    ok "after abnormal exit a second dispatch is not refused with exit 6 (rc=$second_rc)"
  else
    not "lock was not released: second dispatch exited 6: $SECOND_OUT"
  fi
fi

echo "test-mode-epilogue: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
