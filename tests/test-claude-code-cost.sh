#!/bin/bash
# tests/test-claude-code-cost.sh — real executor cost in the ledger + a denied write stops the run at once.
#
# Closes: incidents/2026-10-02-claude-code-runner-sai-0-com-escrita-negada.md
# Design: docs/delegation-check.md §4 (the ledger used to record estimated_cost="0").
# Pattern: tests/test-model-override.sh (mktemp, counters, exit 1 on failure).
# No real model: CLAUDE_BIN points to a fake claude.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/adapters/claude-code/runner.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-cc-cost.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Fake claude: prints the JSON in $FAKE_JSON (or plain text) and creates $FAKE_TOUCH if set.
FAKE="$TMPDIR/claude"
cat >"$FAKE" <<'EOF'
#!/bin/bash
echo "some warning on stderr" >&2
[ -n "${FAKE_TOUCH:-}" ] && touch "$FAKE_TOUCH"
cat "$FAKE_JSON"
EOF
chmod +x "$FAKE"

json() { # $1 = cost, $2 = JSON list of permission_denials
  printf '{"type":"result","subtype":"success","is_error":false,"result":"done","total_cost_usd":%s,"usage":{"input_tokens":120,"cache_read_input_tokens":8000,"cache_creation_input_tokens":900,"output_tokens":310},"permission_denials":%s}\n' "$1" "$2"
}

SPEC="$TMPDIR/spec.md"
printf 'do the task\n' >"$SPEC"
export CLAUDE_BIN="$FAKE" DISPATCH_RUNNER_FORMAT_JSON=1

echo "== 1. runner: success records the cost and exits 0"
json 0.41 '[]' >"$TMPDIR/ok.json"
export ORACFIT_COST_FILE="$TMPDIR/cost1.jsonl"
if FAKE_JSON="$TMPDIR/ok.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi
python3 - "$ORACFIT_COST_FILE" <<'PY' && ok "cost and tokens in the file" || not "cost and tokens in the file"
import json, sys
d = json.loads(open(sys.argv[1]).read().strip())
assert d["cost_usd"] == 0.41 and d["in_tok"] == 120 and d["cache_read_tok"] == 8000 and d["out_tok"] == 310, d
assert d["denied_writes"] == 0, d
PY

echo "== 2. runner: denied Write exits 3 with instructions"
json 0.05 '[{"tool_name":"Write","tool_use_id":"t1","tool_input":{}},{"tool_name":"Bash","tool_use_id":"t2","tool_input":{}}]' >"$TMPDIR/neg.json"
export ORACFIT_COST_FILE="$TMPDIR/cost2.jsonl"
set +e
err="$(FAKE_JSON="$TMPDIR/neg.json" "$RUNNER" claude-sonnet-5 "$SPEC" 2>&1 >/dev/null)"; rc=$?
set -e
[ "$rc" -eq 3 ] && ok "exit 3" || not "exit 3 (got $rc)"
printf '%s' "$err" | grep -q "DISPATCH_ALLOWED_TOOLS" && ok "message names DISPATCH_ALLOWED_TOOLS" || not "message names DISPATCH_ALLOWED_TOOLS"
[ -s "$ORACFIT_COST_FILE" ] && ok "cost recorded even when denied" || not "cost recorded even when denied"

echo "== 3. runner: only Bash denied (not a write) does not fail the run"
json 0.02 '[{"tool_name":"Bash","tool_use_id":"t3","tool_input":{}}]' >"$TMPDIR/bash.json"
if FAKE_JSON="$TMPDIR/bash.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi

echo "== 4. runner: output without JSON behaves as before"
printf 'plain text\n' >"$TMPDIR/txt.json"
export ORACFIT_COST_FILE="$TMPDIR/cost4.jsonl"; : >"$ORACFIT_COST_FILE"
if FAKE_JSON="$TMPDIR/txt.json" "$RUNNER" claude-sonnet-5 "$SPEC" >/dev/null 2>&1; then ok "exit 0"; else not "exit 0"; fi
[ ! -s "$ORACFIT_COST_FILE" ] && ok "no invented cost" || not "no invented cost"
unset ORACFIT_COST_FILE

echo "== 5. dispatch-mode end to end"
spec_e2e() { # $1 = file the oracle checks for. Headings and the no-invention clause stay in Portuguese: check-spec only accepts those today.
  cat <<EOF
# claude-code cost fixture

## Objetivo
Create the file $1. Não invente números além dos dados verificados.

## Dados verificados
No numeric facts.

## Oráculo
- comando: test -f $1
- exit esperado: 0

## Barra
- nome: cost fixture

NUNCA use declare const como workaround.
EOF
}
run_e2e() { # $1 = dir, $2 = fake JSON, $3 = FAKE_TOUCH ("" = writes nothing)
  mkdir -p "$1"
  spec_e2e marker >"$1/spec.md"
  ( cd "$1" && FAKE_JSON="$2" FAKE_TOUCH="$3" ORACFIT_WORKDIR="$1" DISPATCH_RUNNER="$RUNNER" \
      DISPATCH_MODEL_REF=claude-sonnet-5 "$ROOT/bin/dispatch-mode.sh" normal spec.md fixture-cost >"$1/out.log" 2>&1 ) || true
}
last_ledger_row() { tail -1 "$1/.dispatch/ledger/mode.jsonl"; }

E1="$TMPDIR/e2e-ok"
run_e2e "$E1" "$TMPDIR/ok.json" "$E1/marker"
python3 - "$(last_ledger_row "$E1")" <<'PY' && ok "ledger: pass with cost 0.41 and tokens" || { not "ledger: pass with cost 0.41 and tokens"; tail -20 "$E1/out.log"; }
import json, sys
d = json.loads(sys.argv[1])
assert d["status"] == "pass", d
assert abs(float(d["estimated_cost"]) - 0.41) < 1e-9, d
assert int(d["executor_in_tok"]) == 120 + 8000 + 900 and int(d["executor_out_tok"]) == 310, d
PY

E2="$TMPDIR/e2e-denied"
run_e2e "$E2" "$TMPDIR/neg.json" ""
python3 - "$(last_ledger_row "$E2")" <<'PY' && ok "ledger: fail on attempt 1 (gauntlet not burned)" || { not "ledger: fail on attempt 1"; tail -20 "$E2/out.log"; }
import json, sys
d = json.loads(sys.argv[1])
assert d["status"] == "fail" and str(d["attempt"]) == "1", d
PY
grep -q '"runner_usage_error"' "$E2/.dispatch/logs/events.jsonl" && ok "runner_usage_error event in the panel" || not "runner_usage_error event in the panel"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
