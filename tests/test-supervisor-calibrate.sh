#!/bin/bash
# tests/test-supervisor-calibrate.sh — a scored ring calibrates the policy.
# Hermetic: temp target and ORACFIT_ROOT. No model, no network, no writes to
# the real checkout.
set -euo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CALIBRATE="$REAL_ROOT/bin/oracfit-calibrate.py"
ENGINE="$REAL_ROOT/bin/oracfit-policy.py"
RING="$REAL_ROOT/bin/oracfit-ring.sh"
SHIPPED="$REAL_ROOT/core/supervisor/policy.json"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-calibrate.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"

export ORACFIT_ROOT="$SCRATCH/oracfit-root"
mkdir -p "$ORACFIT_ROOT/ledger"
ln -s "$REAL_ROOT/bin" "$ORACFIT_ROOT/bin"
export ORACFIT_CENTRAL_LEDGER="$ORACFIT_ROOT/ledger/ledger.jsonl"
: >"$ORACFIT_CENTRAL_LEDGER"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

rc_of() {
  set +e
  "$@" >"$SCRATCH/last.out" 2>"$SCRATCH/last.err"
  echo $?
  set -e
}

Q_CHOICE="r01-orchestrator-writes-bulk"
HINT="put the prescription in the next attempt spec"
RING_ID="RING-1"
CAL_LINE="CALIBRATION RING-1: predicted=4.8 real=4.0 delta=-0.8"
OWNER_ABOVE="0.6"

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

source_policy() {
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

unscored_ledger() {
  local target="$1"
  mkdir -p "$target/ring"
  python3 - "$target/ring/ledger.jsonl" "$RING_ID" <<'PY'
import json, sys
path, ring = sys.argv[1], sys.argv[2]
event = {"schema": "ring-v1", "ring": ring, "event": "close", "owner_score_pred": 4.8}
with open(path, "w", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
}

scored_ledger() {
  local target="$1"
  mkdir -p "$target/ring"
  python3 - "$target/ring/ledger.jsonl" "$RING_ID" "$CAL_LINE" <<'PY'
import json, sys
path, ring, line = sys.argv[1], sys.argv[2], sys.argv[3]
events = [
    {"schema": "ring-v1", "ring": ring, "event": "close", "owner_score_pred": 4.8},
    {
        "schema": "ring-v1",
        "ring": ring,
        "event": "owner_score",
        "pred": 4.8,
        "real": 4.0,
        "delta": -0.8,
        "calibration_line": line,
    },
]
with open(path, "w", encoding="utf-8") as fh:
    for event in events:
        fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
}

echo "== 1. a ring without a score is refused"
T1="$SCRATCH/t1"
mkdir -p "$T1"
unscored_ledger "$T1"
source_policy "$SCRATCH/t1-source.json"
OUT1="$SCRATCH/t1-out.json"
rc="$(rc_of python3 "$CALIBRATE" --ring "$RING_ID" --target "$T1" \
  --policy "$SCRATCH/t1-source.json" --act-above "$OWNER_ABOVE" --out "$OUT1")"
if [ "$rc" -ne 0 ] && [ ! -f "$OUT1" ] && [ -s "$SCRATCH/last.err" ]; then
  ok "a ring without a score is refused"
else
  not "a ring without a score is refused (rc=$rc out=$(head -c 200 "$SCRATCH/last.out") err=$(head -c 240 "$SCRATCH/last.err"))"
fi

echo "== 2. a scored ring calibrates the policy"
T2="$SCRATCH/t2"
mkdir -p "$T2"
scored_ledger "$T2"
source_policy "$SCRATCH/t2-source.json"
OUT2="$SCRATCH/t2-out.json"
rc="$(rc_of python3 "$CALIBRATE" --ring "$RING_ID" --target "$T2" \
  --policy "$SCRATCH/t2-source.json" --act-above "$OWNER_ABOVE" --out "$OUT2")"
if [ "$rc" -eq 0 ] && [ -f "$OUT2" ] && python3 - "$OUT2" "$RING_ID" "$CAL_LINE" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
ring, line = sys.argv[2], sys.argv[3]
assert doc["calibration"]["ring"] == ring, doc["calibration"]
assert doc["calibration"]["line"] == line, doc["calibration"]
PY
then
  ok "a scored ring calibrates the policy"
else
  not "a scored ring calibrates the policy (rc=$rc out=$(head -c 200 "$SCRATCH/last.out") err=$(head -c 240 "$SCRATCH/last.err"))"
fi

echo "== 3. the calibrated policy stops saying not calibrated"
write_json "$SCRATCH/answers.json" <<JSON
{
  "endpoint": "http://127.0.0.1/v1/systemone",
  "requested_at": "2026-11-13T12:00:00Z",
  "questions": ["$Q_CHOICE"],
  "answers": {
    "$Q_CHOICE": {
      "type": "choice",
      "probabilities": {"a": 0.91},
      "choice": "a",
      "confidence": 0.91
    }
  },
  "usage": {"input_tokens": 0, "output_tokens": 0}
}
JSON
rc="$(rc_of python3 "$ENGINE" decide --answers "$SCRATCH/answers.json" \
  --policy "$OUT2" --out "$SCRATCH/decision.json")"
if [ "$rc" -eq 0 ] && python3 - "$SCRATCH/decision.json" "$Q_CHOICE" "$HINT" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
qid, hint = sys.argv[2], sys.argv[3]
assert rec["decision"] != "CONTINUE" or rec["reason"] != "not calibrated", rec
assert rec["decision"] == "INJECT_HINT", rec
assert rec["order"]["action"] == "INJECT_HINT", rec
assert rec["order"]["question_id"] == qid, rec
assert rec["order"]["hint"] == hint, rec
PY
then
  ok "the calibrated policy stops saying not calibrated"
else
  not "the calibrated policy stops saying not calibrated (rc=$rc out=$(head -c 300 "$SCRATCH/last.out") err=$(head -c 200 "$SCRATCH/last.err"))"
fi

echo "== 4. the threshold is the number the owner gave"
T4="$SCRATCH/t4"
mkdir -p "$T4"
scored_ledger "$T4"
source_policy "$SCRATCH/t4-source.json"
OUT4="$SCRATCH/t4-out.json"
BAD4="$SCRATCH/t4-bad.json"
rc="$(rc_of python3 "$CALIBRATE" --ring "$RING_ID" --target "$T4" \
  --policy "$SCRATCH/t4-source.json" --act-above "$OWNER_ABOVE" --out "$OUT4")"
rc_bad="$(rc_of python3 "$CALIBRATE" --ring "$RING_ID" --target "$T4" \
  --policy "$SCRATCH/t4-source.json" --act-above 1.5 --out "$BAD4")"
if [ "$rc" -eq 0 ] && [ "$rc_bad" -ne 0 ] && [ ! -f "$BAD4" ] \
  && python3 - "$OUT4" "$OWNER_ABOVE" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
assert doc["thresholds"]["act_above"] == float(sys.argv[2]), doc["thresholds"]
PY
then
  ok "the threshold is the number the owner gave"
else
  not "the threshold is the number the owner gave (rc=$rc rc_bad=$rc_bad err=$(head -c 240 "$SCRATCH/last.err"))"
fi

echo "== 5. the rules of the source policy are preserved"
if python3 - "$SCRATCH/t2-source.json" "$OUT2" "$Q_CHOICE" "$HINT" <<'PY'
import json, sys
source = json.load(open(sys.argv[1], encoding="utf-8"))
calibrated = json.load(open(sys.argv[2], encoding="utf-8"))
qid, hint = sys.argv[3], sys.argv[4]
assert calibrated["rules"] == source["rules"], calibrated.get("rules")
assert calibrated["rules"][qid]["action"] == "INJECT_HINT"
assert calibrated["rules"][qid]["hint"] == hint
PY
then
  ok "the rules of the source policy are preserved"
else
  not "the rules of the source policy are preserved"
fi

echo "== 6. the source policy is never written"
T6="$SCRATCH/t6"
mkdir -p "$T6"
scored_ledger "$T6"
source_policy "$SCRATCH/t6-source.json"
cp "$SCRATCH/t6-source.json" "$SCRATCH/t6-source.before.json"
OUT6="$SCRATCH/t6-out.json"
rc="$(rc_of python3 "$CALIBRATE" --ring "$RING_ID" --target "$T6" \
  --policy "$SCRATCH/t6-source.json" --act-above "$OWNER_ABOVE" --out "$OUT6")"
if [ "$rc" -eq 0 ] && python3 - "$SCRATCH/t6-source.json" "$SCRATCH/t6-source.before.json" "$SHIPPED" <<'PY'
import json, sys
after = json.load(open(sys.argv[1], encoding="utf-8"))
before = json.load(open(sys.argv[2], encoding="utf-8"))
shipped = json.load(open(sys.argv[3], encoding="utf-8"))
assert after == before, after
assert after["calibration"]["ring"] == "", after["calibration"]
assert after["calibration"]["line"] == "", after["calibration"]
assert shipped["calibration"]["ring"] == "", shipped["calibration"]
assert shipped["calibration"]["line"] == "", shipped["calibration"]
PY
then
  ok "the source policy is never written"
else
  not "the source policy is never written (rc=$rc err=$(head -c 240 "$SCRATCH/last.err"))"
fi

echo "== 7. the ring stores the calibration line"
T7="$SCRATCH/t7"
mkdir -p "$T7/ring"
write_json "$T7/ring/state.json" <<'JSON'
{
  "schema": "ring-state-v1",
  "mode": "smoketest",
  "run": "calibrate-run",
  "score_field": "owner_score_pred"
}
JSON
python3 - "$T7/ring/ledger.jsonl" <<'PY'
import json, sys
event = {
    "schema": "ring-v1",
    "run": "calibrate-run",
    "ring": "RING-1",
    "event": "close",
    "owner_score_pred": 4.8,
}
with open(sys.argv[1], "w", encoding="utf-8") as fh:
    fh.write(json.dumps(event, ensure_ascii=False) + "\n")
PY
rc="$(rc_of bash "$RING" score RING-1 --real 4.0 --target "$T7")"
if [ "$rc" -eq 0 ] && grep -q "CALIBRATION" "$SCRATCH/last.out" \
  && python3 - "$T7/ring/ledger.jsonl" "$SCRATCH/last.out" <<'PY'
import json, sys
ledger, printed_path = sys.argv[1], sys.argv[2]
event = None
for raw in open(ledger, encoding="utf-8"):
    raw = raw.strip()
    if not raw:
        continue
    obj = json.loads(raw)
    if obj.get("event") == "owner_score":
        event = obj
assert event is not None, "missing owner_score"
line = event.get("calibration_line")
assert isinstance(line, str) and line.strip(), event
assert "CALIBRATION" in line, line
printed = open(printed_path, encoding="utf-8").read()
assert line in printed, printed
assert "CALIBRATION" in printed, printed
PY
then
  ok "the ring stores the calibration line"
else
  not "the ring stores the calibration line (rc=$rc out=$(head -c 300 "$SCRATCH/last.out") err=$(head -c 240 "$SCRATCH/last.err"))"
fi

echo
echo "test-supervisor-calibrate: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
