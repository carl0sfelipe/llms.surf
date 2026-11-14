#!/bin/bash
# test-supervisor-reset.sh — a RESET order snapshots the dirty tree, restores
# the changed tracked files from HEAD, and carries the scar to the next
# attempt. Hermetic: temp workdir, temp ORACFIT_ROOT, stub runner, no network,
# no model call, never writes the real checkout.
set -uo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$REAL_ROOT/bin/dispatch-mode.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-reset.XXXXXX")"
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

HINT="RESET_HINT_MARKER do not repeat the approach that degraded the tree"
TRACKED_CLEAN="tracked clean"
TRACKED_DIRTY="tracked dirty"
OTHER_CLEAN="other clean"
OTHER_DIRTY="other dirty"
UNTRACKED="agent-new.txt"
UNTRACKED_BODY="agent created this"

SPEC="$SCRATCH/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Supervisor reset fixture

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
- nome: supervisor reset fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$SCRATCH/fake-runner.sh"
cat >"$FAKE_RUNNER" <<EOF
#!/bin/bash
set -euo pipefail
wd="\${ORACFIT_WORKDIR:-\$PWD}"
count_file="\$wd/attempt-count"
count=0
if [ -f "\$count_file" ]; then
  count="\$(cat "\$count_file")"
fi
count=\$((count + 1))
printf '%s\n' "\$count" >"\$count_file"
if [ -n "\${2:-}" ] && [ -f "\$2" ]; then
  cp "\$2" "\$wd/received-spec-\${count}.md"
fi
if [ "\$count" -ge 2 ]; then
  printf 'work done\n' >"\$wd/marker.txt"
  exit 0
fi
printf '%s\n' "$TRACKED_DIRTY" >"\$wd/tracked.txt"
printf '%s\n' "$OTHER_DIRTY" >"\$wd/other.txt"
printf '%s\n' "$UNTRACKED_BODY" >"\$wd/$UNTRACKED"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

write_mode() {
  mkdir -p "$1/core/modes"
  cat >"$1/core/modes/supervisor-reset-fixture.yaml" <<'YAML'
id: supervisor-reset-fixture
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

init_workdir() {
  local wd="$1"
  local protected="${2:-}"
  mkdir -p "$wd"
  write_mode "$wd"
  cp "$SPEC" "$wd/spec.md"
  printf '%s\n' "$TRACKED_CLEAN" >"$wd/tracked.txt"
  printf '%s\n' "$OTHER_CLEAN" >"$wd/other.txt"
  printf '.dispatch/\n' >"$wd/.gitignore"
  if [ -n "$protected" ]; then
    printf '%s\n' "$protected" >"$wd/.oracfit-protected"
  fi
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
    "$MODE" supervisor-reset-fixture "$wd/spec.md" "sup-$(basename "$wd")" \
    --workdir "$wd" >"$wd/dispatch.out" 2>"$wd/dispatch.err" || rc=$?
  unset ORACFIT_SUPERVISOR_DECISION
  printf '%s' "$rc"
}

RESET_JSON="$SCRATCH/reset.json"
write_decision "$RESET_JSON" <<JSON
{
  "decision": "RESET",
  "reason": "fixture reset",
  "order": {
    "action": "RESET",
    "question_id": "r16-recurring-failure-becomes-a-rule",
    "value": 0.9,
    "hint": "$HINT"
  }
}
JSON

NOHINT_JSON="$SCRATCH/reset-no-hint.json"
write_decision "$NOHINT_JSON" <<'JSON'
{
  "decision": "RESET",
  "reason": "fixture reset without hint",
  "order": {
    "action": "RESET",
    "question_id": "r16-recurring-failure-becomes-a-rule",
    "value": 0.9
  }
}
JSON

# ── 1–4. applied RESET ──────────────────────────────────────────────────
RESET_WD="$SCRATCH/reset"
reset_rc="$(run_dispatch "$RESET_WD" "$RESET_JSON")"
RESET_RUN_ID="$(run_id_of "$RESET_WD")"
RESET_REF="refs/llms-surf/wip/${RESET_RUN_ID}/iter-1"
RESET_SPEC2="$RESET_WD/received-spec-2.md"
n_reset_applied="$(count_jsonl "$RESET_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied action=RESET)"

if [ "$reset_rc" -eq 0 ] && [ "$(cat "$RESET_WD/tracked.txt")" = "$TRACKED_CLEAN" ]; then
  ok "a RESET order restores the changed tracked files"
else
  not "a RESET order restores the changed tracked files (rc=$reset_rc tracked=$(cat "$RESET_WD/tracked.txt" 2>/dev/null) err=$(head -c 400 "$RESET_WD/dispatch.err"))"
fi

if [ -n "$RESET_RUN_ID" ] \
  && git -C "$RESET_WD" rev-parse -q --verify "$RESET_REF" >/dev/null \
  && [ "$(git -C "$RESET_WD" show "$RESET_REF:tracked.txt" 2>/dev/null)" = "$TRACKED_DIRTY" ]; then
  ok "the reset keeps the evidence"
else
  not "the reset keeps the evidence (run_id=$RESET_RUN_ID ref=$(git -C "$RESET_WD" for-each-ref --format='%(refname)' refs/llms-surf/ 2>/dev/null) shown=$(git -C "$RESET_WD" show "$RESET_REF:tracked.txt" 2>/dev/null))"
fi

if [ -f "$RESET_SPEC2" ] \
  && grep -q "$RESET_REF" "$RESET_SPEC2" \
  && grep -q "\[SUPERVISOR\]:" "$RESET_SPEC2" \
  && grep -q "$HINT" "$RESET_SPEC2" \
  && [ "$n_reset_applied" -eq 1 ]; then
  ok "the scar reaches the next attempt"
else
  not "the scar reaches the next attempt (spec2=$( [ -f "$RESET_SPEC2" ] && head -c 500 "$RESET_SPEC2" || echo missing) applied=$n_reset_applied)"
fi

if [ -f "$RESET_WD/$UNTRACKED" ] && [ "$(cat "$RESET_WD/$UNTRACKED")" = "$UNTRACKED_BODY" ]; then
  ok "an untracked file is never deleted"
else
  not "an untracked file is never deleted (exists=$( [ -f "$RESET_WD/$UNTRACKED" ] && echo yes || echo no))"
fi

# ── 5. a protected path is skipped; the rest of the target restores ─────
PROT_WD="$SCRATCH/protected"
init_workdir "$PROT_WD"
printf 'other.txt\n' >"$PROT_WD/.oracfit-protected"
git -C "$PROT_WD" -c user.name=test -c user.email=test@localhost add .oracfit-protected
git -C "$PROT_WD" -c user.name=test -c user.email=test@localhost commit -q -m "protect other.txt"
prot_rc=0
DISPATCH_RUNNER="$FAKE_RUNNER" \
  DISPATCH_USAGE_FEEDBACK=0 \
  ORACFIT_USAGE_DIR="$PROT_WD/usage" \
  ORACFIT_USO_DIR="$PROT_WD/uso" \
  LOG_DIR="$PROT_WD/.dispatch/logs" \
  ORACFIT_SUPERVISOR_DECISION="$RESET_JSON" \
  "$MODE" supervisor-reset-fixture "$PROT_WD/spec.md" "sup-$(basename "$PROT_WD")" \
  --workdir "$PROT_WD" >"$PROT_WD/dispatch.out" 2>"$PROT_WD/dispatch.err" || prot_rc=$?
unset ORACFIT_SUPERVISOR_DECISION
if [ "$prot_rc" -eq 0 ] \
  && [ "$(cat "$PROT_WD/tracked.txt")" = "$TRACKED_CLEAN" ] \
  && [ "$(cat "$PROT_WD/other.txt")" = "$OTHER_DIRTY" ]; then
  ok "a protected path is never restored"
else
  not "a protected path is never restored (rc=$prot_rc tracked=$(cat "$PROT_WD/tracked.txt" 2>/dev/null) other=$(cat "$PROT_WD/other.txt" 2>/dev/null) err=$(head -c 400 "$PROT_WD/dispatch.err"))"
fi

# ── 6–7. a RESET without a hint is refused; the run still closes ────────
NOHINT_WD="$SCRATCH/no-hint"
nohint_rc="$(run_dispatch "$NOHINT_WD" "$NOHINT_JSON" 1)"
NOHINT_LEDGER="$NOHINT_WD/.dispatch/ledger/mode.jsonl"
NOHINT_USAGE="$NOHINT_WD/usage/usage.jsonl"
n_nohint_applied="$(count_jsonl "$NOHINT_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_nohint_refused="$(count_jsonl "$NOHINT_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused)"
n_ledger="$(count_jsonl "$NOHINT_LEDGER")"
n_usage=0
if [ -f "$NOHINT_USAGE" ]; then
  n_usage="$(count_jsonl "$NOHINT_USAGE")"
fi

if [ "$nohint_rc" -eq 0 ] \
  && [ "$(cat "$NOHINT_WD/tracked.txt")" = "$TRACKED_DIRTY" ] \
  && [ "$n_nohint_applied" -eq 0 ] && [ "$n_nohint_refused" -ge 1 ]; then
  ok "a RESET order without a hint is refused"
else
  not "a RESET order without a hint is refused (rc=$nohint_rc tracked=$(cat "$NOHINT_WD/tracked.txt" 2>/dev/null) applied=$n_nohint_applied refused=$n_nohint_refused)"
fi

if [ "$nohint_rc" -eq 0 ] && [ "$n_ledger" -ge 1 ] && [ "$n_usage" -ge 1 ]; then
  ok "the reset never fails the run"
else
  not "the reset never fails the run (rc=$nohint_rc ledger=$n_ledger usage=$n_usage err=$(head -c 400 "$NOHINT_WD/dispatch.err"))"
fi

echo "test-supervisor-reset: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
