#!/bin/bash
# tests/test-supervisor-policy.sh — supervisor policy: answers to one order.
# Hermetic: work files live under $TMPDIR. No network, no model, no writes to
# the workdir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENGINE="$ROOT/bin/oracfit-policy.py"
SHIPPED="$ROOT/core/supervisor/policy.json"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/supervisor-policy.XXXXXX")"
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
Q_NOUL="r16-recurring-failure-becomes-a-rule"
Q_ESC="r42-long-job-outside-dispatch-is-orphan"
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

write_answers() {
  python3 -c '
import json, sys
path = sys.argv[1]
answers = json.load(sys.stdin)
record = {
    "endpoint": "http://127.0.0.1/v1/systemone",
    "requested_at": "2026-11-13T12:00:00Z",
    "questions": list(answers),
    "answers": answers,
    "usage": {"input_tokens": 0, "output_tokens": 0},
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(record, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
' "$1"
}

calibrated() {
  python3 -c '
import json, sys
path = sys.argv[1]
rules = json.load(sys.stdin)
doc = {
    "version": 1,
    "calibration": {
        "ring": "test-ring",
        "line": "copied calibration line from ring test-ring",
    },
    "thresholds": {"act_above": 0.8},
    "rules": rules,
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
' "$1"
}

echo "== 1. an uncalibrated policy always continues"
write_json "$WORKDIR/uncalibrated.json" <<JSON
{
  "version": 1,
  "calibration": {"ring": "", "line": ""},
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"},
    "$Q_ESC": {
      "action": "ESCALATE",
      "pergunta": "$PERGUNTA",
      "se": ["$SE1", "$SE2"]
    }
  }
}
JSON
write_answers "$WORKDIR/high.json" <<JSON
{
  "$Q_CHOICE": {"type": "choice", "probabilities": {"a": 0.99}, "choice": "a", "confidence": 0.99},
  "$Q_NOUL": {"type": "noul", "noul": 0.99},
  "$Q_ESC": {"type": "noul", "noul": 0.99}
}
JSON
rc="$(rc_of python3 "$ENGINE" decide --answers "$WORKDIR/high.json" --policy "$WORKDIR/uncalibrated.json" --out "$WORKDIR/uncalibrated.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$WORKDIR/uncalibrated.out.json" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
assert rec["decision"] == "CONTINUE", rec
assert rec["reason"] == "not calibrated", rec
assert rec["order"]["action"] == "CONTINUE", rec
assert rec["order"]["question_id"] == "", rec
PY
then
  ok "an uncalibrated policy always continues"
else
  not "an uncalibrated policy always continues (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 2. a calibrated policy fires the mapped action"
calibrated "$WORKDIR/inject.json" <<JSON
{
  "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"}
}
JSON
write_answers "$WORKDIR/choice-high.json" <<JSON
{
  "$Q_CHOICE": {"type": "choice", "probabilities": {"a": 0.91}, "choice": "a", "confidence": 0.91}
}
JSON
write_json "$WORKDIR/state.json" <<'JSON'
{"please": "ESCALATE", "ignored": true}
JSON
rc="$(rc_of python3 "$ENGINE" decide \
  --answers "$WORKDIR/choice-high.json" \
  --policy "$WORKDIR/inject.json" \
  --state "$WORKDIR/state.json" \
  --out "$WORKDIR/inject.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$WORKDIR/inject.out.json" "$Q_CHOICE" "$HINT" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
qid, hint = sys.argv[2], sys.argv[3]
assert rec["decision"] == "INJECT_HINT", rec
assert rec["order"]["action"] == "INJECT_HINT", rec
assert rec["order"]["question_id"] == qid, rec
assert rec["order"]["hint"] == hint, rec
assert rec["order"]["value"] == 0.91, rec
assert qid in rec["reason"] and "0.91" in rec["reason"], rec["reason"]
PY
then
  ok "a calibrated policy fires the mapped action"
else
  not "a calibrated policy fires the mapped action (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 3. abstention below the threshold continues"
calibrated "$WORKDIR/noul-rule.json" <<JSON
{
  "$Q_NOUL": {"action": "INJECT_HINT", "hint": "$HINT"}
}
JSON
write_answers "$WORKDIR/noul-low.json" <<JSON
{
  "$Q_NOUL": {"type": "noul", "noul": 0.2}
}
JSON
rc="$(rc_of python3 "$ENGINE" decide --answers "$WORKDIR/noul-low.json" --policy "$WORKDIR/noul-rule.json" --out "$WORKDIR/noul-low.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$WORKDIR/noul-low.out.json" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
assert rec["decision"] == "CONTINUE", rec
assert rec["reason"] == "no rule fired", rec
PY
then
  ok "abstention below the threshold continues"
else
  not "abstention below the threshold continues (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 4. the strongest action wins"
calibrated "$WORKDIR/two-rules.json" <<JSON
{
  "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"},
  "$Q_ESC": {
    "action": "ESCALATE",
    "pergunta": "$PERGUNTA",
    "se": ["$SE1", "$SE2"]
  }
}
JSON
write_answers "$WORKDIR/two-fired.json" <<JSON
{
  "$Q_CHOICE": {"type": "choice", "probabilities": {"a": 0.95}, "choice": "a", "confidence": 0.95},
  "$Q_ESC": {"type": "noul", "noul": 0.91}
}
JSON
rc="$(rc_of python3 "$ENGINE" decide --answers "$WORKDIR/two-fired.json" --policy "$WORKDIR/two-rules.json" --out "$WORKDIR/strongest.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$WORKDIR/strongest.out.json" "$Q_ESC" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
qid = sys.argv[2]
assert rec["decision"] == "ESCALATE", rec
assert rec["order"]["action"] == "ESCALATE", rec
assert rec["order"]["question_id"] == qid, rec
PY
then
  ok "the strongest action wins"
else
  not "the strongest action wins (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 5. an escalate order carries the owner-question contract"
if python3 - "$WORKDIR/strongest.out.json" <<'PY'
import json, re, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
order = rec["order"]
pergunta = order.get("pergunta")
assert isinstance(pergunta, str) and pergunta.strip(), order
se = order.get("se")
assert isinstance(se, list) and len(se) >= 2, se
pat = re.compile(r"^se .+ -> .+$")
for item in se:
    assert isinstance(item, str) and pat.match(item), item
PY
then
  ok "an escalate order carries the owner-question contract"
else
  not "an escalate order carries the owner-question contract"
fi

echo "== 6. the decision is an order, not a verdict"
FAKE_WD="$WORKDIR/fake-workdir"
mkdir -p "$FAKE_WD"
before="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
rc="$(
  set +e
  (
    cd "$FAKE_WD"
    python3 "$ENGINE" decide \
      --answers "$WORKDIR/choice-high.json" \
      --policy "$WORKDIR/inject.json"
  ) >"$WORKDIR/order.out" 2>"$WORKDIR/order.err"
  echo $?
  set -e
)"
after="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
if [ "$rc" -eq 0 ] && [ "$before" -eq 0 ] && [ "$after" -eq 0 ] && python3 - "$WORKDIR/order.out" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
assert set(rec) == {"decision", "reason", "order"}, rec.keys()

banned = ("verdict", "correct", "decision_score")

def walk(obj):
    if isinstance(obj, dict):
        for key, val in obj.items():
            for token in banned:
                assert token not in key, key
            walk(val)
    elif isinstance(obj, list):
        for item in obj:
            walk(item)

walk(rec)
PY
then
  ok "the decision is an order, not a verdict"
else
  not "the decision is an order, not a verdict (rc=$rc before=$before after=$after err=$(head -c 200 "$WORKDIR/order.err"))"
fi

echo "== 7. an invalid policy is refused"
write_json "$WORKDIR/bad-action.json" <<JSON
{
  "version": 1,
  "calibration": {"ring": "test-ring", "line": "copied calibration line from ring test-ring"},
  "thresholds": {"act_above": 0.8},
  "rules": {
    "$Q_CHOICE": {"action": "PANIC", "hint": "$HINT"}
  }
}
JSON
write_json "$WORKDIR/bad-threshold.json" <<'JSON'
{
  "version": 1,
  "calibration": {"ring": "test-ring", "line": "copied calibration line from ring test-ring"},
  "thresholds": {"act_above": 1.5},
  "rules": {}
}
JSON
write_json "$WORKDIR/bad-escalate.json" <<JSON
{
  "version": 1,
  "calibration": {"ring": "test-ring", "line": "copied calibration line from ring test-ring"},
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
invalid_ok=1
for kind in bad-action bad-threshold bad-escalate; do
  rm -f "$WORKDIR/should-not-exist.json"
  rc="$(rc_of python3 "$ENGINE" decide \
    --answers "$WORKDIR/high.json" \
    --policy "$WORKDIR/${kind}.json" \
    --out "$WORKDIR/should-not-exist.json")"
  if [ "$rc" -eq 1 ] && [ ! -f "$WORKDIR/should-not-exist.json" ]; then
    if python3 - "$WORKDIR/last.out" <<'PY'
import json, sys
text = open(sys.argv[1], encoding="utf-8").read().strip()
if not text:
    raise SystemExit(0)
try:
    rec = json.loads(text)
except json.JSONDecodeError:
    raise SystemExit(0)
if isinstance(rec, dict) and "decision" in rec:
    raise SystemExit(1)
PY
    then
      :
    else
      invalid_ok=0
    fi
  else
    invalid_ok=0
  fi
done
if [ "$invalid_ok" -eq 1 ]; then
  ok "an invalid policy is refused"
else
  not "an invalid policy is refused (rc=$rc out=$(head -c 200 "$WORKDIR/last.out") err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 8. an answer without a rule changes nothing"
calibrated "$WORKDIR/one-rule.json" <<JSON
{
  "$Q_CHOICE": {"action": "INJECT_HINT", "hint": "$HINT"}
}
JSON
write_answers "$WORKDIR/unmapped.json" <<JSON
{
  "$Q_ESC": {"type": "noul", "noul": 0.99}
}
JSON
rc="$(rc_of python3 "$ENGINE" decide --answers "$WORKDIR/unmapped.json" --policy "$WORKDIR/one-rule.json" --out "$WORKDIR/unmapped.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$WORKDIR/unmapped.out.json" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
assert rec["decision"] == "CONTINUE", rec
assert rec["reason"] == "no rule fired", rec
PY
then
  ok "an answer without a rule changes nothing"
else
  not "an answer without a rule changes nothing (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo "== 9. the shipped policy is not calibrated"
rc="$(rc_of python3 "$ENGINE" decide --answers "$WORKDIR/high.json" --policy "$SHIPPED" --out "$WORKDIR/shipped.out.json")"
if [ "$rc" -eq 0 ] && python3 - "$SHIPPED" "$WORKDIR/shipped.out.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
cal = doc["calibration"]
assert cal.get("ring", "") == "", cal
assert cal.get("line", "") == "", cal
assert doc.get("rules") == {}, doc.get("rules")
assert doc["version"] == 1
assert doc["thresholds"]["act_above"] == 0.8
rec = json.load(open(sys.argv[2], encoding="utf-8"))
assert rec["decision"] == "CONTINUE", rec
assert rec["reason"] == "not calibrated", rec
PY
then
  ok "the shipped policy is not calibrated"
else
  not "the shipped policy is not calibrated (rc=$rc out=$(head -c 300 "$WORKDIR/last.out") err=$(head -c 200 "$WORKDIR/last.err"))"
fi

echo
echo "test-supervisor-policy: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
