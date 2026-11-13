#!/bin/bash
# test-supervisor-runtime.sh — the runtime executes the supervisor order
# at the attempt boundary. Hermetic: temp workdir, stub runner, no network,
# no model call, never writes the real .dispatch/ of this checkout.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$ROOT/bin/dispatch-mode.sh"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-runtime.XXXXXX")"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

export ORACFIT_ROOT="$ROOT"
export DISPATCH_USAGE_FEEDBACK=0
unset DISPATCH_ROOT
unset DISPATCH_MODEL_REF
unset ORACFIT_WORKDIR
unset ORACFIT_EVENTS_FILE
unset ORACFIT_NTFY_TOPIC
unset ORACFIT_RUN_ID
unset ORACFIT_SUPERVISOR_DECISION

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

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

HINT="SUPERVISOR_HINT_MARKER put the prescription in the next attempt spec"
RESET_HINT="SUPERVISOR_HINT_MARKER should not appear after a RESET"

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Supervisor runtime fixture

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
- nome: supervisor runtime fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
wd="${ORACFIT_WORKDIR:-$PWD}"
count_file="$wd/attempt-count"
count=0
if [ -f "$count_file" ]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ -n "${2:-}" ] && [ -f "$2" ]; then
  cp "$2" "$wd/received-spec-${count}.md"
fi
if [ "$count" -ge 2 ]; then
  printf 'work done\n' >"$wd/marker.txt"
fi
exit 0
EOF
chmod +x "$FAKE_RUNNER"

write_mode() {
  mkdir -p "$1/core/modes"
  cat >"$1/core/modes/supervisor-runtime-fixture.yaml" <<'YAML'
id: supervisor-runtime-fixture
version: "1"
max_attempts: 2
stages:
  - role: run
    model_ref: fixture-model
    max_attempts: 2
gauntlet:
  enabled: false
  inject_feedback: false
  until_approved: false
on_fail: halt
YAML
}

write_decision() {
  python3 -c '
import json, sys
path = sys.argv[1]
doc = json.load(sys.stdin)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
' "$1"
}

accum_of() {
  local wd="$1"
  local f=""
  f="$(ls -1 "$wd"/.dispatch/logs/inbox/*.gauntlet/feedback.md 2>/dev/null | head -1)"
  printf '%s' "$f"
}

accum_body() {
  local f
  f="$(accum_of "$1")"
  if [ -n "$f" ] && [ -f "$f" ]; then
    cat "$f"
  fi
}

workdir_tree() {
  (cd "$1" && find . -not -path './.dispatch/*' -not -path './.dispatch' | sort)
}

run_dispatch() {
  local wd="$1"
  local decision="${2:-}"
  local usage_flag="${3:-0}"
  mkdir -p "$wd"
  write_mode "$wd"
  cp "$SPEC" "$wd/spec.md"
  unset ORACFIT_SUPERVISOR_DECISION
  if [ -n "$decision" ]; then
    export ORACFIT_SUPERVISOR_DECISION="$decision"
  fi
  local rc=0
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    DISPATCH_USAGE_FEEDBACK="$usage_flag" \
    ORACFIT_USAGE_DIR="$wd/usage" \
    ORACFIT_USO_DIR="$wd/uso" \
    "$MODE" supervisor-runtime-fixture "$wd/spec.md" "sup-$(basename "$wd")" \
    --workdir "$wd" >"$wd/dispatch.out" 2>"$wd/dispatch.err" || rc=$?
  unset ORACFIT_SUPERVISOR_DECISION
  printf '%s' "$rc"
}

# ── 1. a run without a decision record behaves exactly as before ────────
BASE="$TMPDIR/base"
base_rc="$(run_dispatch "$BASE")"
BASE_EVENTS="$BASE/.dispatch/logs/events.jsonl"
BASE_ACCUM="$(accum_body "$BASE")"
BASE_TREE="$(workdir_tree "$BASE")"
n_applied="$(count_jsonl "$BASE_EVENTS" type=supervisor_order result=applied)"
if [ "$base_rc" -eq 0 ] && [ "$n_applied" -eq 0 ] \
  && ! printf '%s' "$BASE_ACCUM" | grep -q "SUPERVISOR ORDER"; then
  ok "a run without a decision record behaves exactly as before"
else
  not "a run without a decision record behaves exactly as before (rc=$base_rc applied=$n_applied accum=$(printf '%s' "$BASE_ACCUM" | head -c 200) err=$(head -c 300 "$BASE/dispatch.err"))"
fi

# ── 2. an INJECT_HINT order reaches the next attempt ────────────────────
HINT_JSON="$TMPDIR/inject.json"
write_decision "$HINT_JSON" <<JSON
{
  "decision": "INJECT_HINT",
  "reason": "fixture hint",
  "order": {
    "action": "INJECT_HINT",
    "question_id": "r01-orchestrator-writes-bulk",
    "value": 0.9,
    "hint": "$HINT"
  }
}
JSON
INJECT="$TMPDIR/inject"
inject_rc="$(run_dispatch "$INJECT" "$HINT_JSON")"
INJECT_EVENTS="$INJECT/.dispatch/logs/events.jsonl"
SPEC1="$INJECT/received-spec-1.md"
SPEC2="$INJECT/received-spec-2.md"
n_inj_applied="$(count_jsonl "$INJECT_EVENTS" type=supervisor_order result=applied)"
if [ "$inject_rc" -eq 0 ] && [ -f "$SPEC1" ] && [ -f "$SPEC2" ] \
  && ! grep -q "$HINT" "$SPEC1" \
  && grep -q "$HINT" "$SPEC2" \
  && grep -q "SUPERVISOR ORDER (attempt 1)" "$(accum_of "$INJECT")" \
  && [ "$n_inj_applied" -eq 1 ] \
  && ! grep -q "GAUNTLET FEEDBACK" "$SPEC2"; then
  ok "an INJECT_HINT order reaches the next attempt"
else
  not "an INJECT_HINT order reaches the next attempt (rc=$inject_rc spec1=$( [ -f "$SPEC1" ] && echo yes || echo missing) spec2=$( [ -f "$SPEC2" ] && head -c 400 "$SPEC2" || echo missing) err=$(head -c 400 "$INJECT/dispatch.err"))"
fi

# ── 3. a CONTINUE order changes nothing ─────────────────────────────────
CONT_JSON="$TMPDIR/continue.json"
write_decision "$CONT_JSON" <<'JSON'
{
  "decision": "CONTINUE",
  "reason": "no rule fired",
  "order": {
    "action": "CONTINUE",
    "question_id": "",
    "value": 0.0
  }
}
JSON
CONT="$TMPDIR/continue"
cont_rc="$(run_dispatch "$CONT" "$CONT_JSON")"
CONT_ACCUM="$(accum_body "$CONT")"
CONT_SPEC2="$CONT/received-spec-2.md"
if [ "$cont_rc" -eq "$base_rc" ] \
  && [ -f "$CONT_SPEC2" ] && ! grep -q "$HINT" "$CONT_SPEC2" \
  && ! printf '%s' "$CONT_ACCUM" | grep -q "SUPERVISOR ORDER" \
  && [ "$(printf '%s' "$CONT_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ]; then
  ok "a CONTINUE order changes nothing"
else
  not "a CONTINUE order changes nothing (rc=$cont_rc accum=$(printf '%s' "$CONT_ACCUM" | head -c 200) spec2=$( [ -f "$CONT_SPEC2" ] && head -c 200 "$CONT_SPEC2" || echo missing))"
fi

# ── 4. a malformed decision record is refused ───────────────────────────
NOTJSON="$TMPDIR/not-json.txt"
printf 'this is not JSON\n' >"$NOTJSON"
MALFORMED_JSON="$TMPDIR/no-decision.json"
write_decision "$MALFORMED_JSON" <<'JSON'
{
  "reason": "no action here",
  "order": {}
}
JSON
BAD1="$TMPDIR/bad-not-json"
BAD2="$TMPDIR/bad-no-decision"
bad1_rc="$(run_dispatch "$BAD1" "$NOTJSON")"
bad2_rc="$(run_dispatch "$BAD2" "$MALFORMED_JSON")"
BAD1_ACCUM="$(accum_body "$BAD1")"
BAD2_ACCUM="$(accum_body "$BAD2")"
n_bad1_applied="$(count_jsonl "$BAD1/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_bad2_applied="$(count_jsonl "$BAD2/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_bad1_refused="$(count_jsonl "$BAD1/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
n_bad2_refused="$(count_jsonl "$BAD2/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
if [ "$bad1_rc" -eq "$base_rc" ] && [ "$bad2_rc" -eq "$base_rc" ] \
  && [ "$n_bad1_applied" -eq 0 ] && [ "$n_bad2_applied" -eq 0 ] \
  && [ "$n_bad1_refused" -ge 1 ] && [ "$n_bad2_refused" -ge 1 ] \
  && [ "$(printf '%s' "$BAD1_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ] \
  && [ "$(printf '%s' "$BAD2_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ]; then
  ok "a malformed decision record is refused"
else
  not "a malformed decision record is refused (rc1=$bad1_rc rc2=$bad2_rc applied=$n_bad1_applied/$n_bad2_applied refused=$n_bad1_refused/$n_bad2_refused)"
fi

# ── 5. an INJECT_HINT without a hint is refused ─────────────────────────
NOHINT_JSON="$TMPDIR/inject-no-hint.json"
write_decision "$NOHINT_JSON" <<'JSON'
{
  "decision": "INJECT_HINT",
  "reason": "fixture without hint",
  "order": {
    "action": "INJECT_HINT",
    "question_id": "r01-orchestrator-writes-bulk",
    "value": 0.9
  }
}
JSON
NOHINT="$TMPDIR/no-hint"
nohint_rc="$(run_dispatch "$NOHINT" "$NOHINT_JSON")"
NOHINT_ACCUM="$(accum_body "$NOHINT")"
n_nohint_applied="$(count_jsonl "$NOHINT/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_nohint_refused="$(count_jsonl "$NOHINT/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
if [ "$nohint_rc" -eq "$base_rc" ] \
  && [ "$n_nohint_applied" -eq 0 ] && [ "$n_nohint_refused" -ge 1 ] \
  && ! printf '%s' "$NOHINT_ACCUM" | grep -q "SUPERVISOR ORDER" \
  && [ "$(printf '%s' "$NOHINT_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ]; then
  ok "an INJECT_HINT without a hint is refused"
else
  not "an INJECT_HINT without a hint is refused (rc=$nohint_rc applied=$n_nohint_applied refused=$n_nohint_refused accum=$(printf '%s' "$NOHINT_ACCUM" | head -c 200))"
fi

# ── 6. an order this rung cannot execute is refused ─────────────────────
RESET_JSON="$TMPDIR/reset.json"
write_decision "$RESET_JSON" <<JSON
{
  "decision": "RESET",
  "reason": "fixture reset",
  "order": {
    "action": "RESET",
    "question_id": "r16-recurring-failure-becomes-a-rule",
    "value": 0.9,
    "hint": "$RESET_HINT"
  }
}
JSON
ESC_JSON="$TMPDIR/escalate.json"
write_decision "$ESC_JSON" <<'JSON'
{
  "decision": "ESCALATE",
  "reason": "fixture escalate",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "which watchdog should cover this long-running job?",
    "se": [
      "se keep it outside dispatch -> leave it running and ask after one attempt",
      "se bring it under dispatch -> stop the orphan and relaunch through dispatch.sh"
    ]
  }
}
JSON
RESET_WD="$TMPDIR/reset"
ESC_WD="$TMPDIR/escalate"
reset_rc="$(run_dispatch "$RESET_WD" "$RESET_JSON")"
esc_rc="$(run_dispatch "$ESC_WD" "$ESC_JSON")"
RESET_ACCUM="$(accum_body "$RESET_WD")"
ESC_ACCUM="$(accum_body "$ESC_WD")"
RESET_TREE="$(workdir_tree "$RESET_WD")"
n_reset_applied="$(count_jsonl "$RESET_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_esc_applied="$(count_jsonl "$ESC_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_reset_refused="$(count_jsonl "$RESET_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
n_esc_refused="$(count_jsonl "$ESC_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
if [ "$reset_rc" -eq "$base_rc" ] && [ "$esc_rc" -eq "$base_rc" ] \
  && [ "$n_reset_applied" -eq 0 ] && [ "$n_esc_applied" -eq 0 ] \
  && [ "$n_reset_refused" -ge 1 ] && [ "$n_esc_refused" -ge 1 ] \
  && ! printf '%s' "$RESET_ACCUM" | grep -q "$RESET_HINT" \
  && ! printf '%s' "$RESET_ACCUM" | grep -q "SUPERVISOR ORDER" \
  && ! printf '%s' "$ESC_ACCUM" | grep -q "SUPERVISOR ORDER" \
  && [ "$RESET_TREE" = "$BASE_TREE" ]; then
  ok "an order this rung cannot execute is refused"
else
  not "an order this rung cannot execute is refused (reset_rc=$reset_rc esc_rc=$esc_rc applied=$n_reset_applied/$n_esc_applied refused=$n_reset_refused/$n_esc_refused tree=$( [ "$RESET_TREE" = "$BASE_TREE" ] && echo match || echo differ))"
fi

# ── 7. the supervisor never fails the run ───────────────────────────────
NEVER="$TMPDIR/never-fail"
never_rc="$(run_dispatch "$NEVER" "$NOTJSON" 1)"
NEVER_LEDGER="$NEVER/.dispatch/ledger/mode.jsonl"
NEVER_USAGE="$NEVER/usage/usage.jsonl"
n_ledger="$(count_jsonl "$NEVER_LEDGER")"
n_usage=0
if [ -f "$NEVER_USAGE" ]; then
  n_usage="$(count_jsonl "$NEVER_USAGE")"
fi
if [ "$never_rc" -eq "$base_rc" ] && [ "$n_ledger" -ge 1 ] && [ "$n_usage" -ge 1 ]; then
  ok "the supervisor never fails the run"
else
  not "the supervisor never fails the run (rc=$never_rc ledger=$n_ledger usage=$n_usage err=$(head -c 400 "$NEVER/dispatch.err") out=$(head -c 200 "$NEVER/dispatch.out"))"
fi

echo "test-supervisor-runtime: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
