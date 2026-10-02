#!/bin/bash
# tests/test-verify.sh — `oracfit verify`: direct mode that still shows in the ledger and the panel.
# Design: docs/delegation-check.md §3. Pattern: tests/test-model-override.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OF="$ROOT/bin/oracfit"
TMPDIR="$(mktemp -d /tmp/oracfit-verify.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$TMPDIR/last.log" 2>&1; echo $?; set -e; }
last_ledger_row() { python3 -c "import json,sys; d=json.loads(open('$W/.dispatch/ledger/mode.jsonl').read().splitlines()[-1]); $1"; }

W="$TMPDIR/w"; mkdir -p "$W"; cd "$W"
# english-ok-begin: check-spec reads Portuguese headings today.
cat >spec.md <<'EOF'
# verify fixture

## Oráculo
- comando: test -f delivered
EOF
# english-ok-end
export ORACFIT_WORKDIR="$W"

echo "== 1. closing a run that was never opened → usage error"
[ "$(rc_of "$OF" verify spec.md t1)" -eq 3 ] && ok "exit 3" || not "exit 3"

echo "== 2. oracle already green on --before → refused"
touch delivered
[ "$(rc_of "$OF" verify spec.md t2 --before)" -eq 2 ] && ok "exit 2" || not "exit 2"
grep -q "stricter" "$TMPDIR/last.log" && ok "explains why" || not "explains why"
rm -f delivered

echo "== 3. red → implement → green: pass in the ledger as the orchestrator"
[ "$(rc_of "$OF" verify spec.md t3 --before)" -eq 0 ] && ok "--before opens the run" || not "--before opens the run"
touch delivered
[ "$(rc_of "$OF" verify spec.md t3)" -eq 0 ] && ok "closes with pass" || not "closes with pass"
last_ledger_row 'assert d["task"] == "t3" and d["status"] == "pass" and d["model_id"] == "orchestrator" and d["mode_id"] == "direct", d' \
  && ok "ledger: pass, orchestrator, direct mode" || not "ledger: pass, orchestrator, direct mode"
last_ledger_row 'assert d["cost_source"] == "orchestrator-unmeasured", d' \
  && ok "ledger: cost marked as unmeasured, not free" || not "ledger: cost marked as unmeasured"
grep -q '"run_finished"' "$W/.dispatch/logs/events.jsonl" && ok "run_finished in the panel" || not "run_finished in the panel"
[ ! -f "$W/.dispatch/verify/t3.json" ] && ok "run closed (state removed)" || not "run closed (state removed)"
rm -f delivered

echo "== 4. wrong implementation → fail in the ledger, oracle output shown"
[ "$(rc_of "$OF" verify spec.md t4 --before)" -eq 0 ] || not "--before t4"
[ "$(rc_of "$OF" verify spec.md t4)" -eq 1 ] && ok "exit 1" || not "exit 1"
last_ledger_row 'assert d["task"] == "t4" and d["status"] == "fail", d' && ok "ledger: fail" || not "ledger: fail"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
