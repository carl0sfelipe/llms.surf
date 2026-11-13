#!/usr/bin/env bash
# tests/test-usage-jsonl.sh — usage.jsonl origin fix, hardened writer and repair.
# Hermetic: work files live under $TMPDIR. No network, no model, no writes to
# this checkout's .dispatch/ or incidents/uso/.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PY="$ROOT/bin/oracfit-usage-json.py"
ESCALATE="$ROOT/bin/dispatch-escalate.sh"
WRITER="$ROOT/bin/emit-usage-feedback.sh"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/usage-jsonl.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

# A parent dispatch may export these; this suite must not inherit them.
unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID ORACFIT_WORKDIR
export DISPATCH_USAGE_FEEDBACK=1
export TMPDIR="$WORKDIR/tmp"
mkdir -p "$TMPDIR"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

USAGE_A="$WORKDIR/usage-a"
USO_A="$WORKDIR/uso-a"
LOG_A="$WORKDIR/logs-a"
mkdir -p "$USAGE_A" "$USO_A" "$LOG_A" "$WORKDIR/wd"

emit() {
  LOG_DIR="$LOG_A" \
  ORACFIT_USAGE_DIR="$USAGE_A" \
  ORACFIT_USO_DIR="$USO_A" \
  bash "$WRITER" --source test --task usage-jsonl --result ok "$@"
}

row_count() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo 0
    return
  fi
  wc -l < "$f" | tr -d ' '
}

every_row_parses() {
  local f="$1"
  python3 - "$f" <<'PY'
import json, sys
path = sys.argv[1]
for i, line in enumerate(open(path, encoding="utf-8"), 1):
    if not line.strip():
        raise SystemExit(f"blank line {i}")
    value = json.loads(line)
    if not isinstance(value, dict):
        raise SystemExit(f"line {i} is not an object")
PY
}

echo "== 1. the escalate already-passing row parses"
SPEC="$WORKDIR/already-passing.md"
printf '%s\n' '# already-passing' '- command: true' >"$SPEC"
ESC_USAGE="$WORKDIR/usage-esc"
ESC_USO="$WORKDIR/uso-esc"
ESC_LOG="$WORKDIR/logs-esc"
ESC_WD="$WORKDIR/wd-esc"
mkdir -p "$ESC_USAGE" "$ESC_USO" "$ESC_LOG" "$ESC_WD"
LOG_DIR="$ESC_LOG" \
ORACFIT_USAGE_DIR="$ESC_USAGE" \
ORACFIT_USO_DIR="$ESC_USO" \
bash "$ESCALATE" "$SPEC" already-passing-task --workdir "$ESC_WD" \
  >"$WORKDIR/esc.out" 2>"$WORKDIR/esc.err"
ESC_RC=$?
if [ "$ESC_RC" -eq 0 ] \
  && [ -f "$ESC_USAGE/usage.jsonl" ] \
  && python3 - "$ESC_USAGE/usage.jsonl" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert len(raw) == 1, raw
row = json.loads(raw[0])
assert row["extra"] == {"tiers_used": 0}, row.get("extra")
assert raw[0].count("}") == raw[0].count("{")
PY
then
  ok "the escalate already-passing row parses"
else
  not "the escalate already-passing row parses (rc=$ESC_RC usage=$(ls -l "$ESC_USAGE" 2>/dev/null || true) err=$(head -c 400 "$WORKDIR/esc.err"))"
fi

echo "== 2. every row the writer appends parses"
: >"$USAGE_A/usage.jsonl"
accent=$(python3 -c 'print("caf\u00e9")')
calls=0
emit_one() {
  emit "$@" >/dev/null 2>"$WORKDIR/writer.err" || true
  calls=$((calls + 1))
  n=$(row_count "$USAGE_A/usage.jsonl")
  if [ "$n" -eq "$calls" ] && every_row_parses "$USAGE_A/usage.jsonl"; then
    return 0
  fi
  echo "after call $calls: lines=$n expected=$calls err=$(cat "$WORKDIR/writer.err")" >&2
  return 1
}
writer_ok=1
emit_one --extra-json '{"a":1}' --mode 2 --exit-code 0 || writer_ok=0
emit_one --extra-json 'not-json' --mode 1 --exit-code 1 || writer_ok=0
emit_one --extra-json '[1,2]' --mode 0 --exit-code 0 || writer_ok=0
emit_one --extra-json "" --mode 3 --exit-code 2 || writer_ok=0
emit_one --extra-json 'say "hi"' --mode 2 --exit-code 0 || writer_ok=0
emit_one --extra-json "$accent" --mode 2 --exit-code 0 || writer_ok=0
emit_one --extra-json '{"ok":true}' --mode 2 --exit-code 0 || writer_ok=0
emit_one --extra-json '{"ok":true}' --mode abc --exit-code xyz || writer_ok=0
if [ "$writer_ok" -eq 1 ]; then
  ok "every row the writer appends parses"
else
  not "every row the writer appends parses"
fi

echo "== 3. a non-object extra payload is coerced"
COERCE_DIR="$WORKDIR/coerce"
mkdir -p "$COERCE_DIR" "$WORKDIR/uso-c" "$WORKDIR/log-c"
LOG_DIR="$WORKDIR/log-c" \
ORACFIT_USAGE_DIR="$COERCE_DIR" \
ORACFIT_USO_DIR="$WORKDIR/uso-c" \
bash "$WRITER" --source test --task coerce --result ok --extra-json 'not-json' \
  >/dev/null 2>"$WORKDIR/coerce.err" || true
if python3 - "$COERCE_DIR/usage.jsonl" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert row["extra"] == {"raw": "not-json"}, row.get("extra")
PY
then
  ok "a non-object extra payload is coerced"
else
  not "a non-object extra payload is coerced"
fi

echo "== 4. a non-numeric mode does not break the row"
MODE_DIR="$WORKDIR/mode"
mkdir -p "$MODE_DIR" "$WORKDIR/uso-m" "$WORKDIR/log-m"
LOG_DIR="$WORKDIR/log-m" \
ORACFIT_USAGE_DIR="$MODE_DIR" \
ORACFIT_USO_DIR="$WORKDIR/uso-m" \
bash "$WRITER" --source test --task mode-null --result ok \
  --mode nope --exit-code also-nope \
  >/dev/null 2>"$WORKDIR/mode.err" || true
if python3 - "$MODE_DIR/usage.jsonl" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
assert row["mode"] is None, row.get("mode")
assert row["exit_code"] is None, row.get("exit_code")
PY
then
  ok "a non-numeric mode does not break the row"
else
  not "a non-numeric mode does not break the row"
fi

echo "== 5. the repair recovers a trailing-brace row"
TRAIL_DIR="$WORKDIR/trail"
mkdir -p "$TRAIL_DIR" "$WORKDIR/uso-t" "$WORKDIR/log-t"
LOG_DIR="$WORKDIR/log-t" \
ORACFIT_USAGE_DIR="$TRAIL_DIR" \
ORACFIT_USO_DIR="$WORKDIR/uso-t" \
bash "$WRITER" --source escalate --task trail --result already-passing \
  --mode 2 --exit-code 0 --extra-json '{"tiers_used":0}' \
  >/dev/null 2>"$WORKDIR/trail.err" || true
BROKEN="$WORKDIR/broken.jsonl"
python3 - "$TRAIL_DIR/usage.jsonl" "$BROKEN" <<'PY'
import sys
src, dest = sys.argv[1], sys.argv[2]
line = open(src, encoding="utf-8").readline()
open(dest, "w", encoding="utf-8").write(line.rstrip("\n") + "}\n")
PY
python3 "$PY" repair "$BROKEN" --out "$WORKDIR/broken.repaired" \
  >"$WORKDIR/repair-trail.report"
if python3 - "$WORKDIR/broken.repaired" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read().splitlines()
assert len(raw) == 1, raw
row = json.loads(raw[0])
assert row["extra"] == {"tiers_used": 0}, row.get("extra")
PY
then
  ok "the repair recovers a trailing-brace row"
else
  not "the repair recovers a trailing-brace row (report=$(cat "$WORKDIR/repair-trail.report"))"
fi

echo "== 6. the repair quarantines an unrecoverable row"
TRUNC="$WORKDIR/trunc.jsonl"
printf '%s\n' '{"ts":"2026-01-01T00:00:00Z","source":"escalate"' >"$TRUNC"
python3 "$PY" repair "$TRUNC" --out "$WORKDIR/trunc.repaired" \
  >"$WORKDIR/repair-trunc.report"
if [ -f "$TRUNC.unrecoverable" ] \
  && grep -q 'unrecoverable=1' "$WORKDIR/repair-trunc.report" \
  && python3 - "$TRUNC" "$TRUNC.unrecoverable" "$WORKDIR/repair-trunc.report" <<'PY'
import sys
orig = open(sys.argv[1], encoding="utf-8").read()
unrec = open(sys.argv[2], encoding="utf-8").read()
report = open(sys.argv[3], encoding="utf-8").read()
assert orig.strip() == unrec.strip(), (orig, unrec)
assert "unrecoverable=1" in report
assert "repaired=0" in report
PY
then
  ok "the repair quarantines an unrecoverable row"
else
  not "the repair quarantines an unrecoverable row (report=$(cat "$WORKDIR/repair-trunc.report" 2>/dev/null) files=$(ls -l "$WORKDIR"/trunc* 2>/dev/null))"
fi

echo "== 7. the repair is idempotent"
python3 "$PY" repair "$WORKDIR/broken.repaired" --out "$WORKDIR/broken.repaired2" \
  >"$WORKDIR/repair-idemp.report"
if cmp -s "$WORKDIR/broken.repaired" "$WORKDIR/broken.repaired2" \
  && grep -q 'repaired=0' "$WORKDIR/repair-idemp.report"
then
  ok "the repair is idempotent"
else
  not "the repair is idempotent"
fi

echo "== 8. the repair keeps a backup before writing in place"
INPLACE="$WORKDIR/inplace.jsonl"
cp "$BROKEN" "$INPLACE"
ORIG_COPY="$WORKDIR/inplace.orig"
cp "$INPLACE" "$ORIG_COPY"
python3 "$PY" repair "$INPLACE" --in-place >"$WORKDIR/repair-inplace.report"
if [ -f "$INPLACE.bak" ] \
  && cmp -s "$ORIG_COPY" "$INPLACE.bak" \
  && python3 - "$INPLACE" <<'PY'
import json, sys
json.loads(open(sys.argv[1], encoding="utf-8").readline())
PY
then
  ok "the repair keeps a backup before writing in place"
else
  not "the repair keeps a backup before writing in place"
fi

echo "== 9. the checker rejects a line that does not parse"
GOOD_LINE=$(head -1 "$TRAIL_DIR/usage.jsonl")
BAD_LINE=$(head -1 "$BROKEN")
check_good=0
printf '%s\n' "$GOOD_LINE" | python3 "$PY" check >/dev/null 2>"$WORKDIR/check-good.err" || check_good=$?
check_bad=0
printf '%s\n' "$BAD_LINE" | python3 "$PY" check >/dev/null 2>"$WORKDIR/check-bad.err" || check_bad=$?
if [ "$check_good" -eq 0 ] && [ "$check_bad" -eq 2 ]; then
  ok "the checker rejects a line that does not parse"
else
  not "the checker rejects a line that does not parse (good=$check_good bad=$check_bad)"
fi

echo
echo "test-usage-jsonl: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
