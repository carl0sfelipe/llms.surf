#!/bin/bash
# tests/test-delegation-check.sh — is it worth delegating this task to this executor?
# Design: docs/delegation-check.md §2. Pattern: tests/test-verify.sh.
# Fixtures are three real specs from 2026-10-02 (Portuguese headings, which the check still accepts).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/bin/delegation-check.py"
OF="$ROOT/bin/oracfit"
FIX="$ROOT/tests/fixtures/delegacao"
TR13="$FIX/tr-1-3-catalogo-plano.md"
TR67="$FIX/tr-6-7-demanda-politica.md"
TEL="$FIX/tel-1-telemetria-backup.md"
TMPDIR="$(mktemp -d /tmp/oracfit-delegation-check.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$TMPDIR/last.log" 2>"$TMPDIR/last.err"; echo $?; set -e; }
json_assert() { python3 -c "import json,sys; d=json.load(open('$TMPDIR/last.log')); $1"; }

W="$TMPDIR/w"; mkdir -p "$W"; cd "$W"
RUN=(python3 "$CHECK")

echo "== 1. tr-1-3 to Sonnet → DIRECT; output_tok 1920; spec_tok measured from the file"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor claude-sonnet-5)" -eq 10 ] && ok "exit 10" || not "exit 10"
grep -q '^DIRECT' "$TMPDIR/last.log" && ok "line starts with DIRECT" || not "line starts with DIRECT"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor claude-sonnet-5 --json)" -eq 10 ] || not "json exit 10"
python3 - "$TMPDIR/last.log" "$TR13" <<'PY' && ok "output_tok 1920 and spec_tok = ceil(len/4)" || not "output_tok/spec_tok"
import json, math, sys
d = json.loads(open(sys.argv[1]).read())
assert d["output_tok"] == 1920, d
assert d["spec_tok"] == math.ceil(len(open(sys.argv[2], encoding="utf-8").read()) / 4), d
PY

echo "== 2. tr-6-7 → output_tok 1800 (the Objective section's budgets are not counted twice)"
[ "$(rc_of "${RUN[@]}" "$TR67" --executor claude-sonnet-5 --json)" -eq 10 ] && ok "exit 10" || not "exit 10"
json_assert 'assert d["output_tok"] == 1800, d' && ok "output_tok 1800" || not "output_tok 1800"

echo "== 3. placa (no per-token cost) → DELEGATE"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor qwen-3.8-27b)" -eq 0 ] && grep -q DELEGATE "$TMPDIR/last.log" && ok "tr-1-3" || not "tr-1-3"
[ "$(rc_of "${RUN[@]}" "$TR67" --executor qwen-3.8-27b)" -eq 0 ] && grep -q DELEGATE "$TMPDIR/last.log" && ok "tr-6-7" || not "tr-6-7"

echo "== 4. spec without a line budget → exit 3"
[ "$(rc_of "${RUN[@]}" "$TEL" --executor claude-sonnet-5)" -eq 3 ] && ok "exit 3" || not "exit 3"
grep -q "line budget" "$TMPDIR/last.err" && ok "message names the line budget" || not "message names the line budget"

echo "== 5. unknown price → exit 4"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor grok-4.6-xhigh-fast)" -eq 4 ] && ok "exit 4" || not "exit 4"
grep -q "core/prices.json" "$TMPDIR/last.err" && ok "message names core/prices.json" || not "message names core/prices.json"

echo "== 6. --parallel → DELEGATE"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor claude-sonnet-5 --parallel)" -eq 0 ] && ok "exit 0" || not "exit 0"
grep -q parallel "$TMPDIR/last.log" && ok "reason names parallel work" || not "reason names parallel work"

echo "== 7. ledger with >= 3 rows → mean attempts from the ledger"
mkdir -p "$W/led/.dispatch/ledger"
printf '%s\n' '{"model_id":"claude-sonnet-5","attempt":3,"status":"pass"}'{,,} >"$W/led/.dispatch/ledger/mode.jsonl"
echo '{"model_id":"claude-sonnet-5","attempt":"x","status":"pass"}' >>"$W/led/.dispatch/ledger/mode.jsonl"
[ "$(rc_of "${RUN[@]}" "$TR13" --executor claude-sonnet-5 --json --workdir "$W/led")" -eq 10 ] || not "ledger rc"
json_assert 'assert d["attempts"] == 3, d' && ok "attempts 3 (malformed row ignored)" || not "attempts 3"

echo "== 8. short spec, 400 lines: no context → DIRECT (rule 5); 200 kB context → DELEGATE (rule 4)"
cat >s.md <<'EOF'
# s

## Verified data
- `big.bin`

## DELIVERABLES
- x.py (<= 400 lines)
EOF
[ "$(rc_of "${RUN[@]}" s.md --executor claude-sonnet-5)" -eq 10 ] && grep -q 'delegating costs' "$TMPDIR/last.log" \
  && ok "rule 5 DIRECT" || not "rule 5 DIRECT"
head -c 200000 /dev/zero >big.bin
[ "$(rc_of "${RUN[@]}" s.md --executor claude-sonnet-5 --json)" -eq 0 ] || not "rule 4 rc"
json_assert 'assert d["verdict"] == "DELEGATE" and d["context_tok"] == 50000 and "delegating costs" in d["reason"], d' \
  && ok "rule 4 DELEGATE with 50000 context tokens" || not "rule 4"

echo "== 9. oracfit delegation-check = the script"
[ "$(rc_of "$OF" delegation-check "$TR13" --executor claude-sonnet-5 --workdir "$W")" -eq 10 ] \
  && grep -q '^DIRECT' "$TMPDIR/last.log" && ok "oracfit DIRECT" || not "oracfit DIRECT"

echo "== 10. before the spec exists (--deliverable-lines): decide without spending the spec"
V="$TMPDIR/v"; mkdir -p "$V"; head -c 200000 /dev/zero | tr '\0' x >"$V/ctx.txt"
[ "$(rc_of "${RUN[@]}" --deliverable-lines 160 --executor claude-sonnet-5 --workdir "$V")" -eq 10 ] \
  && ok "160 lines, no context → DIRECT" || not "160 lines → DIRECT"
[ "$(rc_of "${RUN[@]}" --deliverable-lines 160 --context ctx.txt --executor claude-sonnet-5 --workdir "$V")" -eq 0 ] \
  && ok "50k-token context → DELEGATE" || not "context → DELEGATE"
[ "$(rc_of "${RUN[@]}" --deliverable-lines 160 --executor qwen-3.8-27b --workdir "$V")" -eq 0 ] \
  && ok "placa → DELEGATE" || not "placa → DELEGATE"
[ "$(rc_of "${RUN[@]}" --executor claude-sonnet-5 --workdir "$V")" -eq 3 ] \
  && ok "no spec and no --deliverable-lines → usage error" || not "usage error"
[ "$(rc_of "${RUN[@]}" --deliverable-lines 160 --executor claude-sonnet-5 --workdir "$V" --json)" -eq 10 ] || not "json rc"
json_assert 'assert d["mode"] == "before-spec" and d["spec_tok"] == 1805 and d["output_tok"] == 1920, d' \
  && ok "estimated spec: 0.94 × 1920 = 1805 tok" || not "estimated spec"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
