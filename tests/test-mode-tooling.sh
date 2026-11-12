#!/bin/bash
# tests/test-mode-tooling.sh — the custom-mode flywheel, as a stranger walks it:
# start with no env, write a spec in English, run paddle and tow, create a mode (scaffold and
# --from), share it and install it somewhere else. Stub runner only: no network, no model.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L="$ROOT/bin/llms-surf"
W="$(mktemp -d /tmp/oracfit-mode-tooling.XXXXXX)"
trap 'rm -rf "$W"' EXIT
export DISPATCH_USAGE_FEEDBACK=0
unset ORACFIT_ROOT DISPATCH_RUNNER ORACFIT_WORKDIR

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
workdir() { # $1=name
  mkdir -p "$W/$1" && cd "$W/$1" && git init -q . && git config user.email gates@test.dev \
    && git config user.name T && echo x >README && git add -A && git commit -qm init
}
stub_oracle() { # $1=spec: point the template's oracle at what the stub writes
  sed -i.bak -e 's|^- command: .*|- command: test -f .dispatch/stub-proof \&\& grep -q stub_ok .dispatch/stub-proof|' \
    -e 's|^VERIFICATION: .*|VERIFICATION: grep -q stub_ok .dispatch/stub-proof|' "$1"
}
status_of() { "$L" status --task "$1" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])'; }

workdir one

echo "== 1. start works on a fresh clone with no env (stub, no API key)"
"$L" start >"$W/start.log" 2>&1 && grep -q '^status: pass' "$W/start.log" && ok "start: pass" || { not "start"; tail -5 "$W/start.log"; }
grep -q "using the stub runner" "$W/start.log" && ok "says it fell back to the stub" || not "no stub notice"

export ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"

echo "== 2. spec init writes a spec in English that passes the gate"
"$L" spec init task.md >/dev/null && ok "spec init" || not "spec init"
"$L" spec check task.md >/dev/null 2>&1 && ok "template passes check-spec" || not "template fails check-spec"
"$L" spec init task.md >/dev/null 2>&1; [ $? -eq 3 ] && ok "refuses to overwrite" || not "overwrote a spec"
python3 "$ROOT/bin/check-oracle.py" task.md . --quiet >/dev/null 2>&1 && ok "template oracle fails for the right reason before the work" \
  || not "template oracle is not a clean red"
sed 's/^- command: \(.*\)$/- command: `\1`/' task.md >ticks.md
"$L" spec check ticks.md >/dev/null 2>&1 && not "backticks around the command accepted" || ok "backticks around the command refused"
stub_oracle task.md

echo "== 3. paddle and tow run the English spec"
rm -f .dispatch/stub-proof
"$L" run paddle task.md t-paddle >"$W/paddle.log" 2>&1 && [ "$(status_of t-paddle)" = pass ] && ok "paddle: pass" || { not "paddle"; tail -5 "$W/paddle.log"; }
rm -f .dispatch/stub-proof
"$L" run tow task.md t-tow >"$W/tow.log" 2>&1 && [ "$(status_of t-tow)" = pass ] && ok "tow: pass" || { not "tow"; tail -5 "$W/tow.log"; }
grep -c '^── stage' "$W/tow.log" | grep -qx 3 && ok "tow ran its 3 stages" || not "tow stage count"

echo "== 4. mode init: scaffold validates, lints and runs"
"$L" mode init my_break >/dev/null && "$L" mode validate my_break >/dev/null && "$L" mode lint my_break >/dev/null \
  && ok "init + validate + lint" || not "init/validate/lint"
grep -q 'safety_ceiling' core/modes/my_break.yaml && ok "scaffold has the gauntlet block" || not "scaffold without gauntlet"
rm -f .dispatch/stub-proof
"$L" run my_break task.md t-custom >"$W/custom.log" 2>&1 && [ "$(status_of t-custom)" = pass ] && ok "custom mode: pass" || { not "custom run"; tail -5 "$W/custom.log"; }
"$L" mode init my_break >/dev/null 2>&1; [ $? -eq 3 ] && ok "refuses an existing id" || not "overwrote a mode"
"$L" mode init Bad-Id >/dev/null 2>&1; [ $? -eq 2 ] && ok "refuses an invalid id" || not "invalid id accepted"

echo "== 5. mode init --from: a copy of tow, by alias, renamed"
"$L" mode init big_day --from tow >/dev/null && ok "init --from tow" || not "init --from tow"
grep -q '^id: big_day$' core/modes/big_day.yaml && ! grep -q '^id: unlock_plan' core/modes/big_day.yaml && ok "id renamed" || not "id not renamed"
[ "$(grep -c 'role:' core/modes/big_day.yaml)" = "$(grep -c 'role:' "$ROOT/core/modes/unlock_plan.yaml")" ] && ok "stages kept" || not "stages changed"
"$L" mode validate big_day >/dev/null && "$L" mode lint big_day >/dev/null && ok "copy validates and lints" || not "copy does not validate"
rm -f .dispatch/stub-proof
"$L" run big_day task.md t-big >"$W/big.log" 2>&1 && [ "$(status_of t-big)" = pass ] && ok "copy runs: pass" || { not "copy run"; tail -5 "$W/big.log"; }
"$L" mode init nope --from no_such_mode >/dev/null 2>&1; [ $? -eq 3 ] && [ ! -e core/modes/nope.yaml ] && ok "unknown source refused, nothing written" || not "unknown source"

echo "== 6. share -> add round trip, whatever the file is called"
"$L" mode share my_break >"$W/pasted-from-an-issue.txt" && ok "share" || not "share"
workdir two
"$L" mode add "$W/pasted-from-an-issue.txt" >/dev/null 2>"$W/add.err" && [ -f core/modes/my_break.yaml ] && ok "add installs by id" || { not "add"; cat "$W/add.err"; }
"$L" mode add "$W/pasted-from-an-issue.txt" >/dev/null 2>&1 && ok "adding the same file again is fine" || not "identical re-add refused"
sed 's/max_attempts: 3/max_attempts: 9/' "$W/pasted-from-an-issue.txt" >"$W/other.yaml"
"$L" mode add "$W/other.yaml" >/dev/null 2>&1; [ $? -eq 3 ] && ok "different content under the same id refused" || not "silent overwrite"
printf 'id: broken\nstages: nope\n' >"$W/broken.yaml"
"$L" mode add "$W/broken.yaml" >/dev/null 2>&1 && not "invalid yaml installed" || ok "invalid yaml refused"
[ ! -e core/modes/broken.yaml ] && ok "nothing written for the invalid one" || not "invalid file landed"
for example in glassy outside_set; do
  "$L" mode add "$ROOT/examples/$example.yaml" >/dev/null 2>&1 && ok "example $example installs" || not "example $example"
done

echo "== 7. a mechanical stage runs its command, it does not call a model"
# A stage with `command:` and no model_ref is mechanical. With one stage it used
# to go through dispatch-mode.sh, which knows only models: the mode called an
# LLM where the author asked for a script.
workdir three
"$L" spec init task.md >/dev/null
stub_oracle task.md
mkdir -p core/modes
cat >core/modes/mech_one.yaml <<'MECH'
id: mech_one
version: "1"
name: mech one
description: one mechanical stage, no model at all
stages:
  - role: run
    command: bash -c 'mkdir -p .dispatch && echo stub_ok > .dispatch/stub-proof'
    oracle: true
    max_attempts: 1
gauntlet:
  enabled: true
on_fail: halt
MECH
rm -f .dispatch/stub-proof
"$L" run mech_one task.md t-mech >"$W/mech.log" 2>&1
grep -q "mechanical stage run: running command" "$W/mech.log" && ok "the command ran" || { not "mechanical stage"; tail -5 "$W/mech.log"; }
grep -q "stub runner: wrote" "$W/mech.log" && not "a model was called for a mechanical stage" || ok "no model called for a mechanical stage"
[ "$(status_of t-mech)" = pass ] && ok "mechanical mode: pass" || not "mechanical mode did not pass"

echo "== 8. a mechanical stage that fails does not report a pass"
cat >core/modes/mech_fail.yaml <<'MECH'
id: mech_fail
version: "1"
name: mech fail
description: a mechanical stage whose command fails
stages:
  - role: run
    command: bash -c 'exit 3'
    oracle: true
    max_attempts: 1
gauntlet:
  enabled: true
on_fail: halt
MECH
rm -f .dispatch/stub-proof
"$L" run mech_fail task.md t-mech-fail >"$W/mech-fail.log" 2>&1
[ "$(status_of t-mech-fail)" != pass ] && ok "a failing command is not a pass" || not "failing command reported as pass"
grep -q "mechanical stage run: running command" "$W/mech-fail.log" && ok "the failing command did run" || { not "the failing command never ran"; tail -8 "$W/mech-fail.log"; }

echo ""
echo "mode tooling: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
