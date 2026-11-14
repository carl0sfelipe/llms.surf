#!/bin/bash
# test-supervisor-escalate.sh — an ESCALATE order pauses the run and hands
# the decision to the owner. Hermetic: temp workdir, temp ORACFIT_ROOT,
# stub runner, no network, no model call, never writes the real checkout.
set -uo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$REAL_ROOT/bin/dispatch-mode.sh"
USAGE_PY="$REAL_ROOT/bin/oracfit-usage-json.py"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-escalate.XXXXXX")"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"

export ORACFIT_ROOT="$SCRATCH/oracfit-root"
mkdir -p "$ORACFIT_ROOT"
ln -s "$REAL_ROOT/bin" "$ORACFIT_ROOT/bin"

export DISPATCH_USAGE_FEEDBACK=0
unset DISPATCH_ROOT
unset DISPATCH_MODEL_REF
unset ORACFIT_WORKDIR
unset ORACFIT_EVENTS_FILE
unset ORACFIT_NTFY_TOPIC
unset ORACFIT_RUN_ID
unset ORACFIT_SUPERVISOR_DECISION

# A git hook or an outer dispatch may export GIT_DIR; the scratch repos must
# not inherit them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
printf '[user]\n\tuseConfigOnly = true\n[init]\n\tdefaultBranch = main\n' \
  >"$GIT_CONFIG_GLOBAL"

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

run_id_of() {
  python3 -c '
import json, sys
try:
    fh = open(sys.argv[1])
except OSError:
    raise SystemExit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    rid = obj.get("run_id") or ""
    if rid:
        print(rid)
        raise SystemExit(0)
' "$1/.dispatch/logs/events.jsonl"
}

PERGUNTA="which watchdog should cover this long-running job?"
SE1="se keep it outside dispatch -> leave it running and ask after one attempt"
SE2="se bring it under dispatch -> stop the orphan and relaunch through dispatch.sh"

SPEC="$SCRATCH/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Supervisor escalate fixture

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
- nome: supervisor escalate fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$SCRATCH/fake-runner.sh"
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
  cat >"$1/core/modes/supervisor-escalate-fixture.yaml" <<'YAML'
id: supervisor-escalate-fixture
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

init_workdir() {
  local wd="$1"
  mkdir -p "$wd"
  write_mode "$wd"
  cp "$SPEC" "$wd/spec.md"
  printf '.dispatch/\n' >"$wd/.gitignore"
  git -C "$wd" init -q
  git -C "$wd" -c user.name=test -c user.email=test@localhost add -A
  git -C "$wd" -c user.name=test -c user.email=test@localhost commit -q -m init
}

run_dispatch() {
  local wd="$1"
  local decision="${2:-}"
  local usage_flag="${3:-0}"
  init_workdir "$wd"
  unset ORACFIT_SUPERVISOR_DECISION
  if [ -n "$decision" ]; then
    export ORACFIT_SUPERVISOR_DECISION="$decision"
  fi
  local rc=0
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    DISPATCH_USAGE_FEEDBACK="$usage_flag" \
    ORACFIT_USAGE_DIR="$wd/usage" \
    ORACFIT_USO_DIR="$wd/uso" \
    LOG_DIR="$wd/.dispatch/logs" \
    "$MODE" supervisor-escalate-fixture "$wd/spec.md" "sup-$(basename "$wd")" \
    --workdir "$wd" >"$wd/dispatch.out" 2>"$wd/dispatch.err" || rc=$?
  unset ORACFIT_SUPERVISOR_DECISION
  printf '%s' "$rc"
}

question_file_of() {
  local wd="$1"
  local rid="$2"
  printf '%s' "$wd/.dispatch/logs/inbox/${rid}.question.md"
}

ESC_JSON="$SCRATCH/escalate.json"
write_decision "$ESC_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "$PERGUNTA",
    "se": [
      "$SE1",
      "$SE2"
    ]
  }
}
JSON

NOFORK_JSON="$SCRATCH/escalate-no-fork.json"
write_decision "$NOFORK_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate without fork",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "$PERGUNTA",
    "se": [
      "$SE1"
    ]
  }
}
JSON

NOSE_JSON="$SCRATCH/escalate-no-se.json"
write_decision "$NOSE_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate without consequences",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "$PERGUNTA"
  }
}
JSON

NOQ_JSON="$SCRATCH/escalate-no-question.json"
write_decision "$NOQ_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate without question",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "se": [
      "$SE1",
      "$SE2"
    ]
  }
}
JSON

# ── baseline: a run without an order ────────────────────────────────────
BASE="$SCRATCH/base"
base_rc="$(run_dispatch "$BASE")"

# ── 1–4. applied ESCALATE ───────────────────────────────────────────────
ESC_WD="$SCRATCH/escalate"
esc_rc="$(run_dispatch "$ESC_WD" "$ESC_JSON" 1)"
ESC_RUN_ID="$(run_id_of "$ESC_WD")"
ESC_Q="$(question_file_of "$ESC_WD" "$ESC_RUN_ID")"
ESC_LEDGER="$ESC_WD/.dispatch/ledger/mode.jsonl"
ESC_USAGE="$ESC_WD/usage/usage.jsonl"

if [ "$esc_rc" -eq 7 ] && grep -q "status: owner_question" "$ESC_WD/dispatch.out"; then
  ok "an ESCALATE order pauses the run"
else
  not "an ESCALATE order pauses the run (rc=$esc_rc status=$(grep -E '^status:' "$ESC_WD/dispatch.out" | head -1) err=$(head -c 400 "$ESC_WD/dispatch.err"))"
fi

if [ -n "$ESC_RUN_ID" ] && [ -f "$ESC_Q" ] \
  && grep -q "^pergunta:" "$ESC_Q" \
  && [ "$(grep -cE '^se .+ -> ' "$ESC_Q")" -ge 2 ] \
  && grep -q "$PERGUNTA" "$ESC_Q"; then
  ok "the question lands in the inbox with the owner contract"
else
  not "the question lands in the inbox with the owner contract (run_id=$ESC_RUN_ID file=$( [ -f "$ESC_Q" ] && echo yes || echo missing) body=$( [ -f "$ESC_Q" ] && head -c 400 "$ESC_Q" || true))"
fi

n_ledger_oq="$(count_jsonl "$ESC_LEDGER" status=owner_question oracle_exit=7)"
if [ "$n_ledger_oq" -ge 1 ]; then
  ok "the ledger row says owner_question"
else
  not "the ledger row says owner_question (n=$n_ledger_oq row=$(head -c 400 "$ESC_LEDGER" 2>/dev/null))"
fi

usage_parses=1
usage_result=""
if [ -f "$ESC_USAGE" ]; then
  if python3 "$USAGE_PY" check <"$ESC_USAGE"; then
    usage_parses=0
  fi
  usage_result="$(python3 -c '
import json, sys
try:
    print(json.loads(open(sys.argv[1], encoding="utf-8").readline()).get("result", ""))
except (OSError, ValueError):
    pass
' "$ESC_USAGE")"
fi
if [ "$usage_parses" -eq 0 ] && [ "$usage_result" = "owner_question" ]; then
  ok "the usage row records the escalation"
else
  not "the usage row records the escalation (parses=$usage_parses result=$usage_result row=$(head -c 400 "$ESC_USAGE" 2>/dev/null))"
fi

# ── 5. an ESCALATE without the fork is refused ──────────────────────────
NOFORK_WD="$SCRATCH/no-fork"
NOSE_WD="$SCRATCH/no-se"
nofork_rc="$(run_dispatch "$NOFORK_WD" "$NOFORK_JSON")"
nose_rc="$(run_dispatch "$NOSE_WD" "$NOSE_JSON")"
NOFORK_RUN_ID="$(run_id_of "$NOFORK_WD")"
NOSE_RUN_ID="$(run_id_of "$NOSE_WD")"
NOFORK_Q="$(question_file_of "$NOFORK_WD" "$NOFORK_RUN_ID")"
NOSE_Q="$(question_file_of "$NOSE_WD" "$NOSE_RUN_ID")"
n_nofork_applied="$(count_jsonl "$NOFORK_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_nose_applied="$(count_jsonl "$NOSE_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
if [ "$nofork_rc" -eq "$base_rc" ] && [ "$nose_rc" -eq "$base_rc" ] \
  && [ "$n_nofork_applied" -eq 0 ] && [ "$n_nose_applied" -eq 0 ] \
  && [ ! -f "$NOFORK_Q" ] && [ ! -f "$NOSE_Q" ]; then
  ok "an ESCALATE without the fork is refused"
else
  not "an ESCALATE without the fork is refused (rc=$nofork_rc/$nose_rc base=$base_rc applied=$n_nofork_applied/$n_nose_applied q=$( [ -f "$NOFORK_Q" ] && echo yes || echo no)/$( [ -f "$NOSE_Q" ] && echo yes || echo no))"
fi

# ── 6. an ESCALATE without a question is refused ────────────────────────
NOQ_WD="$SCRATCH/no-question"
noq_rc="$(run_dispatch "$NOQ_WD" "$NOQ_JSON")"
NOQ_RUN_ID="$(run_id_of "$NOQ_WD")"
NOQ_Q="$(question_file_of "$NOQ_WD" "$NOQ_RUN_ID")"
n_noq_applied="$(count_jsonl "$NOQ_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
if [ "$noq_rc" -eq "$base_rc" ] \
  && [ "$n_noq_applied" -eq 0 ] \
  && [ ! -f "$NOQ_Q" ]; then
  ok "an ESCALATE without a question is refused"
else
  not "an ESCALATE without a question is refused (rc=$noq_rc base=$base_rc applied=$n_noq_applied q=$( [ -f "$NOQ_Q" ] && echo yes || echo no) err=$(head -c 300 "$NOQ_WD/dispatch.err"))"
fi

# ── 7. the escalation never fails the run ───────────────────────────────
NOFORK_LEDGER="$NOFORK_WD/.dispatch/ledger/mode.jsonl"
n_nofork_events="$(count_jsonl "$NOFORK_WD/.dispatch/logs/events.jsonl")"
n_nofork_ledger="$(count_jsonl "$NOFORK_LEDGER")"
n_nofork_refused="$(count_jsonl "$NOFORK_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
if [ "$nofork_rc" -eq "$base_rc" ] \
  && [ "$n_nofork_events" -ge 1 ] \
  && [ "$n_nofork_ledger" -ge 1 ] \
  && [ "$n_nofork_refused" -ge 1 ]; then
  ok "the escalation never fails the run"
else
  not "the escalation never fails the run (rc=$nofork_rc events=$n_nofork_events ledger=$n_nofork_ledger refused=$n_nofork_refused err=$(head -c 300 "$NOFORK_WD/dispatch.err"))"
fi

echo "test-supervisor-escalate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
