#!/usr/bin/env bash
# tests/test-priority-modes.sh — the two modes the flywheel stands on.
#
# The custom-mode flywheel has two poles: the mechanical one (normal, surf
# alias paddle) and the elevating one (unlock_plan, surf alias tow). A mode
# that changes shape — one cheap stage becoming two, the owner question
# disappearing, the alias pointing somewhere else — changes the product
# silently. Nothing pinned the shape of either, so this does.
#
#  T1  normal is one cheap stage, oracle-gated, with the gauntlet that injects
#      the oracle's complaint into the next attempt
#  T2  unlock_plan is unlock(expensive) -> plan(mid) -> run(cheap), the plan
#      reads the previous stage, the unlock may ask the owner one question
#  T3  both halt on failure: a red stage never starts the next one
#  T4  the surf aliases paddle and tow resolve to those two ids
#  T5  the two modes are legal files: validate and lint both accept them

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/bin/lib-oracfit-mode-loader.py"
L="$REPO_ROOT/bin/llms-surf"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

field() { # field <mode> <python expression over `d`>
  python3 - "$LOADER" "$REPO_ROOT/core/modes/$1.yaml" "$2" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("mode_loader", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
d = mod._load_yaml(open(sys.argv[2], encoding="utf-8").read())
print(eval(sys.argv[3]))
PY
}

echo "== T1. normal is one cheap stage with the feedback gauntlet"
[ "$(field normal 'len(d["stages"])')" = 1 ] && ok "normal has one stage" || not "normal does not have one stage"
[ "$(field normal 'd["stages"][0]["role"]')" = run ] && ok "the stage is a run" || not "the stage is not a run"
[ "$(field normal 'd["stages"][0]["model_ref"]')" = tier:cheap ] && ok "the stage runs on tier:cheap" || not "the stage does not run on tier:cheap"
[ "$(field normal 'd["stages"][0].get("oracle")')" = True ] && ok "the stage is oracle-gated" || not "the stage is not oracle-gated"
[ "$(field normal 'd["gauntlet"]["inject_feedback"]')" = True ] && ok "the gauntlet injects the oracle feedback" || not "the gauntlet does not inject feedback"
[ "$(field normal 'd["gauntlet"]["until_approved"]')" = True ] && ok "the gauntlet runs until approved" || not "the gauntlet does not run until approved"
[ "$(field normal 'd["gauntlet"]["safety_ceiling"]')" -ge 1 ] && ok "the gauntlet has a safety ceiling" || not "the gauntlet has no safety ceiling"

echo "== T2. unlock_plan is unlock -> plan -> run"
[ "$(field unlock_plan '[s["role"] for s in d["stages"]]')" = "['unlock', 'plan', 'run']" ] \
  && ok "the three roles in order" || not "the roles are not unlock, plan, run"
[ "$(field unlock_plan 'd["stages"][0]["model_ref"]')" = tier:expensive ] && ok "the unlock is expensive" || not "the unlock is not expensive"
[ "$(field unlock_plan 'd["stages"][1]["model_ref"]')" = tier:mid ] && ok "the plan is mid" || not "the plan is not mid"
[ "$(field unlock_plan 'd["stages"][2]["model_ref"]')" = tier:cheap ] && ok "the run is cheap" || not "the run is not cheap"
[ "$(field unlock_plan 'd["stages"][1].get("input")')" = prev_stage ] && ok "the plan reads the unlock" || not "the plan does not read the unlock"
[ "$(field unlock_plan 'd["stages"][0].get("owner_question")')" = once ] && ok "the unlock may ask the owner once" || not "the unlock cannot ask the owner"

echo "== T3. both modes halt on a red stage"
[ "$(field normal 'd.get("on_fail")')" = halt ] && ok "normal halts" || not "normal does not halt"
[ "$(field unlock_plan 'd.get("on_fail")')" = halt ] && ok "unlock_plan halts" || not "unlock_plan does not halt"

echo "== T4. the surf aliases point at those two modes"
alias_of() { # alias_of <alias> -> the canonical id it resolves to
  "$L" modes 2>/dev/null | grep -E "^[[:space:]]*$1[[:space:]]" | head -1 | awk '{print $1}'
}
grep -q 'paddle=normal' "$REPO_ROOT/bin/oracfit" && ok "paddle maps to normal" || not "paddle does not map to normal"
grep -q 'tow=unlock_plan' "$REPO_ROOT/bin/oracfit" && ok "tow maps to unlock_plan" || not "tow does not map to unlock_plan"
"$L" mode validate paddle >/dev/null 2>&1 && ok "paddle validates" || not "paddle does not validate"
"$L" mode validate tow >/dev/null 2>&1 && ok "tow validates" || not "tow does not validate"

echo "== T5. both files are legal"
for mode in normal unlock_plan; do
  python3 "$LOADER" validate "$REPO_ROOT/core/modes/$mode.yaml" >/dev/null 2>&1 \
    && ok "$mode validates" || not "$mode does not validate"
  python3 "$LOADER" lint "$REPO_ROOT/core/modes/$mode.yaml" >/dev/null 2>&1 \
    && ok "$mode lints" || not "$mode does not lint"
done

echo ""
echo "priority modes: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
