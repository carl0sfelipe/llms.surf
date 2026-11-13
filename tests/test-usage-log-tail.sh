#!/usr/bin/env bash
# tests/test-usage-log-tail.sh — usage row carries the tail of the newest log.
# Hermetic: LOG_DIR, ORACFIT_USAGE_DIR and ORACFIT_USO_DIR live under $TMPDIR.
# No network, no model, no writes to this checkout.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WRITER="$ROOT/bin/emit-usage-feedback.sh"
PY="$ROOT/bin/oracfit-usage-json.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/usage-log-tail.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID ORACFIT_WORKDIR
export DISPATCH_USAGE_FEEDBACK=1
export TMPDIR="$WORKDIR/tmp"
mkdir -p "$TMPDIR"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# stamp_mtime <file> <YYYYMMDDhhmm>
stamp_mtime() {
  touch -t "$2" "$1"
}

run_writer() {
  local logs="$1" usage="$2" uso="$3" task="$4"
  shift 4
  mkdir -p "$logs" "$usage" "$uso"
  LOG_DIR="$logs" \
  ORACFIT_USAGE_DIR="$usage" \
  ORACFIT_USO_DIR="$uso" \
  bash "$WRITER" --source test --task "$task" --result ok --mode 1 --exit-code 0 "$@"
}

row_has_tail() {
  python3 - "$1" "$2" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
tail = row.get("log_tail") or ""
assert tail, row
assert sys.argv[2] in tail, tail
PY
}

newest_wins() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" "$7" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
logs = row.get("logs") or ""
old, new = sys.argv[2], sys.argv[3]
old_sz, new_sz = sys.argv[4], sys.argv[5]
old_line, new_line = sys.argv[6], sys.argv[7]
assert f"{old}|{old_sz};" in logs, logs
assert f"{new}|{new_sz};" in logs, logs
tail = row.get("log_tail") or ""
assert new_line in tail, tail
assert old_line not in tail, tail
PY
}

row_lists() {
  python3 - "$1" "$2" <<'PY'
import json, sys
row = json.loads(open(sys.argv[1], encoding="utf-8").readline())
logs = row.get("logs") or ""
assert sys.argv[2] in logs, logs
PY
}

echo "== 1. the usage row carries the log tail"
T1_LOG="$WORKDIR/t1/logs"
T1_USAGE="$WORKDIR/t1/usage"
T1_USO="$WORKDIR/t1/uso"
T1_TASK="log-tail-carry"
mkdir -p "$T1_LOG"
T1_MARKER="oracfit-known-last-line-log-tail"
T1_FILE="$T1_LOG/dispatch-${T1_TASK}.log"
printf '%s\n' "dispatch start" "noise" "$T1_MARKER" >"$T1_FILE"
run_writer "$T1_LOG" "$T1_USAGE" "$T1_USO" "$T1_TASK" \
  >/dev/null 2>"$WORKDIR/t1.err"
T1_RC=$?
if [ "$T1_RC" -eq 0 ] \
  && [ -f "$T1_USAGE/usage.jsonl" ] \
  && row_has_tail "$T1_USAGE/usage.jsonl" "$T1_MARKER"
then
  ok "the usage row carries the log tail"
else
  not "the usage row carries the log tail (rc=$T1_RC err=$(head -c 400 "$WORKDIR/t1.err") row=$(head -c 400 "$T1_USAGE/usage.jsonl" 2>/dev/null))"
fi

echo "== 2. the newest log wins"
T2_LOG="$WORKDIR/t2/logs"
T2_USAGE="$WORKDIR/t2/usage"
T2_USO="$WORKDIR/t2/uso"
T2_TASK="log-tail-newest"
mkdir -p "$T2_LOG"
T2_OLD="$T2_LOG/${T2_TASK}-old.log"
T2_NEW="$T2_LOG/${T2_TASK}-new.log"
T2_OLD_LINE="from-older-log-body"
T2_NEW_LINE="from-newer-log-body"
printf '%s\n' "$T2_OLD_LINE" >"$T2_OLD"
printf '%s\n' "$T2_NEW_LINE" >"$T2_NEW"
stamp_mtime "$T2_OLD" 202001011200
stamp_mtime "$T2_NEW" 202611131200
T2_OLD_SZ=$(wc -c < "$T2_OLD" | tr -d ' ')
T2_NEW_SZ=$(wc -c < "$T2_NEW" | tr -d ' ')
run_writer "$T2_LOG" "$T2_USAGE" "$T2_USO" "$T2_TASK" \
  >/dev/null 2>"$WORKDIR/t2.err"
T2_RC=$?
if [ "$T2_RC" -eq 0 ] \
  && newest_wins "$T2_USAGE/usage.jsonl" "$T2_OLD" "$T2_NEW" "$T2_OLD_SZ" "$T2_NEW_SZ" "$T2_OLD_LINE" "$T2_NEW_LINE"
then
  ok "the newest log wins"
else
  not "the newest log wins (rc=$T2_RC err=$(head -c 400 "$WORKDIR/t2.err") row=$(head -c 400 "$T2_USAGE/usage.jsonl" 2>/dev/null))"
fi

echo "== 3. the mtime is read as an integer"
T3_LOG="$WORKDIR/t3/logs"
T3_USAGE="$WORKDIR/t3/usage"
T3_USO="$WORKDIR/t3/uso"
T3_TASK="log-tail-mtime"
mkdir -p "$T3_LOG"
printf '%s\n' "mtime-integer-probe" >"$T3_LOG/dispatch-${T3_TASK}.log"
run_writer "$T3_LOG" "$T3_USAGE" "$T3_USO" "$T3_TASK" \
  >/dev/null 2>"$WORKDIR/t3.err"
T3_RC=$?
T3_CHECK=1
if [ -f "$T3_USAGE/usage.jsonl" ]; then
  python3 "$PY" check <"$T3_USAGE/usage.jsonl" \
    >/dev/null 2>"$WORKDIR/t3.check.err"
  T3_CHECK=$?
fi
if [ "$T3_RC" -eq 0 ] \
  && [ "$T3_CHECK" -eq 0 ] \
  && ! grep -E 'integer( expression)? expected' "$WORKDIR/t3.err" >/dev/null
then
  ok "the mtime is read as an integer"
else
  not "the mtime is read as an integer (rc=$T3_RC check=$T3_CHECK err=$(head -c 400 "$WORKDIR/t3.err"))"
fi

echo "== 4. the incident points at the newest log"
T4_MD=$(find "$T2_USO" -maxdepth 1 -name '*.md' -type f | head -1)
if [ -n "$T4_MD" ] \
  && grep -F "| latest_log |" "$T4_MD" >/dev/null \
  && grep -F "$T2_NEW" "$T4_MD" >/dev/null \
  && ! grep -E '\| latest_log \| `—`' "$T4_MD" >/dev/null
then
  ok "the incident points at the newest log"
else
  not "the incident points at the newest log (md=$T4_MD latest=$(grep -F 'latest_log' "$T4_MD" 2>/dev/null))"
fi

echo "== 5. a log without a readable mtime is still listed"
T5_LOG="$WORKDIR/t5/logs"
T5_USAGE="$WORKDIR/t5/usage"
T5_USO="$WORKDIR/t5/uso"
T5_TASK="log-tail-ghost"
mkdir -p "$T5_LOG"
T5_GHOST="$T5_LOG/${T5_TASK}-ghost.log"
mkdir "$T5_GHOST"
run_writer "$T5_LOG" "$T5_USAGE" "$T5_USO" "$T5_TASK" \
  >/dev/null 2>"$WORKDIR/t5.err"
T5_RC=$?
if [ "$T5_RC" -eq 0 ] \
  && [ -f "$T5_USAGE/usage.jsonl" ] \
  && row_lists "$T5_USAGE/usage.jsonl" "$T5_GHOST"
then
  ok "a log without a readable mtime is still listed"
else
  not "a log without a readable mtime is still listed (rc=$T5_RC err=$(head -c 400 "$WORKDIR/t5.err") row=$(head -c 400 "$T5_USAGE/usage.jsonl" 2>/dev/null))"
fi

echo
echo "test-usage-log-tail: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
