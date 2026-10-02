#!/bin/bash
# tests/test-roi.sh — cost and hit rate per executor, from the ledgers.
# Design: docs/delegation-check.md §4. Pattern: tests/test-verify.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROI="$ROOT/bin/oracfit-roi.py"
OF="$ROOT/bin/oracfit"
TMPDIR="$(mktemp -d /tmp/oracfit-roi.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$TMPDIR/last.log" 2>&1; echo $?; set -e; }
json_assert() { python3 -c "import json,sys; d=json.load(open('$TMPDIR/last.log')); $1"; }

write_ledger() {
  mkdir -p "$1/.dispatch/ledger"
  cat >"$1/.dispatch/ledger/mode.jsonl" <<'EOF'
{"ts":"2026-09-01T10:00:00Z","model_id":"claude-sonnet-5","task":"a","status":"pass","attempt":"1","estimated_cost":"0.4","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-02T10:00:00Z","model_id":"claude-sonnet-5","task":"b","status":"pass","attempt":"1","estimated_cost":"0.5","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-03T10:00:00Z","model_id":"claude-sonnet-5","task":"c","status":"pass","attempt":"1","estimated_cost":"0.6","flash_work_s":"10","executor_out_tok":"100"}
{"ts":"2026-09-04T10:00:00Z","model_id":"claude-sonnet-5","task":"d","status":"fail","attempt":"5","estimated_cost":"0","flash_work_s":"10"}
{"ts":"2026-09-05T10:00:00Z","model_id":"orchestrator","task":"e","status":"pass","attempt":"1","estimated_cost":"0","flash_work_s":"10","cost_source":"orchestrator-unmeasured"}
{"ts":"2026-09-06T10:00:00Z","model_id":"orchestrator","task":"f","status":"pass","attempt":"1","estimated_cost":"0","flash_work_s":"10","cost_source":"orchestrator-unmeasured"}
this is not json
EOF
}

W="$TMPDIR/w"; write_ledger "$W"

echo "== 1. --json: Sonnet and the orchestrator"
[ "$(rc_of python3 "$ROI" --workdir "$W" --json)" -eq 0 ] && ok "exit 0" || not "exit 0"
python3 - "$TMPDIR/last.log" <<'PY' && ok "json fields" || not "json fields"
import json, sys
d = json.loads(open(sys.argv[1]).read())
s = d["models"]["claude-sonnet-5"]
assert s["runs"] == 4 and s["pass"] == 3 and s["first_try_pct"] == 75, s
assert abs(s["measured_cost_usd"] - 1.5) < 1e-9 and s["runs_with_cost"] == 3, s
assert abs(s["cost_per_pass_usd"] - 0.5) < 1e-9, s
o = d["models"]["orchestrator"]
assert o["measured_cost_usd"] == 0 and o["runs_with_cost"] == 0 and o["cost_per_pass_usd"] == "n/a", o
assert d["ignored_lines"] == 1, d
PY

echo "== 2. the table shows n/a for unmeasured cost, never 0"
[ "$(rc_of python3 "$ROI" --workdir "$W")" -eq 0 ] || not "table rc"
grep "^orchestrator" "$TMPDIR/last.log" | grep -q "measured_cost_usd=n/a" && ok "table n/a" || not "table n/a"

echo "== 3. --since after every row → no models"
[ "$(rc_of python3 "$ROI" --workdir "$W" --since 2099-01-01 --json)" -eq 0 ] || not "since rc"
json_assert 'assert d["models"] == {}, d' && ok "since filters everything" || not "since filters everything"

echo "== 4. two --workdir add up"
W2="$TMPDIR/w2"; write_ledger "$W2"
[ "$(rc_of python3 "$ROI" --workdir "$W" --workdir "$W2" --json)" -eq 0 ] || not "sum rc"
json_assert 's=d["models"]["claude-sonnet-5"]; assert s["runs"] == 8 and s["pass"] == 6 and abs(s["measured_cost_usd"]-3.0) < 1e-9 and d["ignored_lines"] == 2, d' \
  && ok "two workdirs add up" || not "two workdirs add up"

echo "== 5. workdir without a ledger → exit 3"
E="$TMPDIR/empty"; mkdir -p "$E"
[ "$(rc_of python3 "$ROI" --workdir "$E")" -eq 3 ] && ok "exit 3" || not "exit 3"
grep -q ".dispatch/ledger/mode.jsonl" "$TMPDIR/last.log" && ok "names the path it looked for" || not "names the path"

echo "== 6. oracfit roi --json = the script"
[ "$(rc_of python3 "$ROI" --workdir "$W" --json)" -eq 0 ] || not "script json"
cp "$TMPDIR/last.log" "$TMPDIR/script.json"
[ "$(rc_of "$OF" roi --workdir "$W" --json)" -eq 0 ] || not "oracfit roi rc"
diff -q "$TMPDIR/script.json" "$TMPDIR/last.log" >/dev/null && ok "oracfit roi matches" || not "oracfit roi matches"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
