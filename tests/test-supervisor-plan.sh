#!/bin/bash
# tests/test-supervisor-plan.sh — supervisor plan: see the mapping without an endpoint.
# Hermetic: work files live under $TMPDIR. No network, no model, no writes to
# the workdir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/bin/oracfit-policy.py"
PLAN="$ROOT/bin/oracfit-supervisor-plan.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/supervisor-plan.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$ROOT"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() {
  set +e
  "$@" >"$WORKDIR/last.out" 2>"$WORKDIR/last.err"
  echo $?
  set -e
}

Q_CHOICE="r01-orchestrator-writes-bulk"
Q_ESC="r42-long-job-outside-dispatch-is-orphan"
Q_UNKNOWN="r99-not-in-the-set"
Q_TEXT="Is the work in front of this run a judgment call, or a deterministic transform that should not go to a model?"
HINT="put the prescription in the next attempt spec"
PERGUNTA="which watchdog should cover this long-running job?"
SE1="se keep it outside dispatch -> leave it running and ask after one attempt"
SE2="se bring it under dispatch -> stop the orphan and relaunch through dispatch.sh"

write_json() {
  python3 -c '
import json, sys
path = sys.argv[1]
doc = json.load(sys.stdin)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
' "$1"
}

write_questions() {
  write_json "$1" <<JSON
{
  "version": 1,
  "questions": [
    {
      "id": "$Q_CHOICE",
      "rule": 1,
      "type": "choice",
      "instructions": "$Q_TEXT",
      "criteria": {
        "judgment": "the input is open and the work needs reasoning",
        "mechanical": "the input is known and the transform is deterministic"
      },
      "evidence": ["spec", "workdir"],
      "cost": {"model_calls": 1, "state": "short"},
      "asked": true
    },
    {
      "id": "$Q_ESC",
      "rule": 42,
      "type": "noul",
      "instructions": "Is a long-running job alive outside dispatch.sh with no watchdog?",
      "evidence": ["log_size", "events.jsonl", "stderr"],
      "cost": {"model_calls": 1, "state": "full"},
      "asked": true
    }
  ]
}
JSON
}

write_questions "$WORKDIR/questions.json"

mapped_calibrated() {
  write_json "$1" <<JSON
{
  "version": 1,
  "calibration": {
    "ring": "test-ring",
    "line": "copied calibration line from ring test-ring"
  },
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"}
  }
}
JSON
}

mapped_uncalibrated() {
  write_json "$1" <<JSON
{
  "version": 1,
  "calibration": {"ring": "", "line": ""},
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"}
  }
}
JSON
}

echo "== 1. the engine validates a policy without answers"
mapped_calibrated "$WORKDIR/valid.json"
write_json "$WORKDIR/invalid.json" <<JSON
{
  "version": 1,
  "calibration": {
    "ring": "test-ring",
    "line": "copied calibration line from ring test-ring"
  },
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_ESC": {
      "action": "ESCALATE",
      "pergunta": "$PERGUNTA",
      "se": ["$SE1"]
    }
  }
}
JSON
rm -f "$WORKDIR/valid.out.json" "$WORKDIR/invalid-should-not-exist.json"
rc_ok="$(rc_of python3 "$ENGINE" validate --policy "$WORKDIR/valid.json" --out "$WORKDIR/valid.out.json")"
valid_json=0
if python3 - "$WORKDIR/last.out" "$WORKDIR/valid.out.json" <<'PY'
import json, sys
stdout = json.load(open(sys.argv[1], encoding="utf-8"))
written = json.load(open(sys.argv[2], encoding="utf-8"))
for rec in (stdout, written):
    assert "version" in rec, rec
    assert "calibration" in rec, rec
    assert "thresholds" in rec, rec
    assert "rules" in rec, rec
assert stdout == written
PY
then
  valid_json=1
fi
rc_bad="$(
  set +e
  python3 "$ENGINE" validate \
    --policy "$WORKDIR/invalid.json" \
    --out "$WORKDIR/invalid-should-not-exist.json" \
    >"$WORKDIR/invalid.out" 2>"$WORKDIR/invalid.err"
  echo $?
  set -e
)"
if [ "$rc_ok" -eq 0 ] && [ "$valid_json" -eq 1 ] \
  && [ "$rc_bad" -eq 1 ] && [ -s "$WORKDIR/invalid.err" ] \
  && [ ! -f "$WORKDIR/invalid-should-not-exist.json" ]
then
  ok "the engine validates a policy without answers"
else
  not "the engine validates a policy without answers (rc_ok=$rc_ok rc_bad=$rc_bad err=$(head -c 240 "$WORKDIR/invalid.err"))"
fi

echo "== 2. the plan lists the mapped question and its action"
mapped_calibrated "$WORKDIR/mapped.json"
rc="$(rc_of python3 "$PLAN" --policy "$WORKDIR/mapped.json" --questions "$WORKDIR/questions.json")"
if [ "$rc" -eq 0 ] \
  && grep -q "$Q_CHOICE" "$WORKDIR/last.out" \
  && grep -q "$Q_TEXT" "$WORKDIR/last.out" \
  && grep -q "INJECT_HINT" "$WORKDIR/last.out" \
  && grep -q "$HINT" "$WORKDIR/last.out"
then
  ok "the plan lists the mapped question and its action"
else
  not "the plan lists the mapped question and its action (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 3. the plan refuses a rule with an unknown question id"
write_json "$WORKDIR/unknown-id.json" <<JSON
{
  "version": 1,
  "calibration": {
    "ring": "test-ring",
    "line": "copied calibration line from ring test-ring"
  },
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_UNKNOWN": {"action": "INJECT_HINT", "hint": "$HINT"}
  }
}
JSON
rc="$(rc_of python3 "$PLAN" --policy "$WORKDIR/unknown-id.json" --questions "$WORKDIR/questions.json")"
if [ "$rc" -eq 1 ] && grep -q "$Q_UNKNOWN" "$WORKDIR/last.err"
then
  ok "the plan refuses a rule with an unknown question id"
else
  not "the plan refuses a rule with an unknown question id (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 4. the plan refuses an invalid policy"
write_json "$WORKDIR/escalate-no-fork.json" <<JSON
{
  "version": 1,
  "calibration": {
    "ring": "test-ring",
    "line": "copied calibration line from ring test-ring"
  },
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_ESC": {
      "action": "ESCALATE",
      "pergunta": "$PERGUNTA",
      "se": ["$SE1"]
    }
  }
}
JSON
rc="$(rc_of python3 "$PLAN" --policy "$WORKDIR/escalate-no-fork.json" --questions "$WORKDIR/questions.json")"
if [ "$rc" -eq 1 ] && grep -q "se" "$WORKDIR/last.err"
then
  ok "the plan refuses an invalid policy"
else
  not "the plan refuses an invalid policy (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 5. the plan warns when the policy is not calibrated"
mapped_uncalibrated "$WORKDIR/uncalibrated.json"
rc="$(rc_of python3 "$PLAN" --policy "$WORKDIR/uncalibrated.json" --questions "$WORKDIR/questions.json")"
if [ "$rc" -eq 0 ] \
  && grep -q "CONTINUE" "$WORKDIR/last.out" \
  && grep -qi "not calibrated" "$WORKDIR/last.out"
then
  ok "the plan warns when the policy is not calibrated"
else
  not "the plan warns when the policy is not calibrated (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 6. the plan needs no endpoint and writes nothing"
FAKE_WD="$WORKDIR/fake-workdir"
mkdir -p "$FAKE_WD"
mapped_calibrated "$WORKDIR/endpoint.json"
rc_base="$(rc_of python3 "$PLAN" --policy "$WORKDIR/endpoint.json" --questions "$WORKDIR/questions.json")"
cp "$WORKDIR/last.out" "$WORKDIR/plan-without-endpoint.txt"
before="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
rc_env="$(
  set +e
  (
    cd "$FAKE_WD"
    ORACFIT_SUPERVISOR_ENDPOINT="http://127.0.0.1:1/not-a-real-endpoint" \
      python3 "$PLAN" --policy "$WORKDIR/endpoint.json" --questions "$WORKDIR/questions.json"
  ) >"$WORKDIR/plan-with-endpoint.out" 2>"$WORKDIR/plan-with-endpoint.err"
  echo $?
  set -e
)"
after="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
if [ "$rc_base" -eq 0 ] && [ "$rc_env" -eq 0 ] \
  && [ "$before" -eq 0 ] && [ "$after" -eq 0 ] \
  && cmp -s "$WORKDIR/plan-without-endpoint.txt" "$WORKDIR/plan-with-endpoint.out"
then
  ok "the plan needs no endpoint and writes nothing"
else
  not "the plan needs no endpoint and writes nothing (rc_base=$rc_base rc_env=$rc_env before=$before after=$after err=$(head -c 200 "$WORKDIR/plan-with-endpoint.err"))"
fi

echo "== 7. the engine reports the calibration state"
mapped_uncalibrated "$WORKDIR/engine-uncalibrated.json"
mapped_calibrated "$WORKDIR/engine-calibrated.json"
rc_uncal="$(
  set +e
  python3 "$ENGINE" validate \
    --policy "$WORKDIR/engine-uncalibrated.json" \
    --out "$WORKDIR/engine-uncalibrated.out.json" \
    >"$WORKDIR/engine-uncalibrated.stdout" 2>"$WORKDIR/engine-uncalibrated.err"
  echo $?
  set -e
)"
rc_cal="$(
  set +e
  python3 "$ENGINE" validate \
    --policy "$WORKDIR/engine-calibrated.json" \
    --out "$WORKDIR/engine-calibrated.out.json" \
    >"$WORKDIR/engine-calibrated.stdout" 2>"$WORKDIR/engine-calibrated.err"
  echo $?
  set -e
)"
state_ok=0
if python3 - \
  "$WORKDIR/engine-uncalibrated.stdout" \
  "$WORKDIR/engine-calibrated.stdout" \
  <<'PY'
import json, sys
uncal = json.load(open(sys.argv[1], encoding="utf-8"))
cal = json.load(open(sys.argv[2], encoding="utf-8"))
assert uncal.get("calibrated") is False, uncal
assert cal.get("calibrated") is True, cal
PY
then
  state_ok=1
fi
if [ "$rc_uncal" -eq 0 ] && [ "$rc_cal" -eq 0 ] && [ "$state_ok" -eq 1 ]
then
  ok "the engine reports the calibration state"
else
  not "the engine reports the calibration state (rc_uncal=$rc_uncal rc_cal=$rc_cal err=$(head -c 200 "$WORKDIR/engine-uncalibrated.err"; echo; head -c 200 "$WORKDIR/engine-calibrated.err"))"
fi

echo
echo "test-supervisor-plan: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
