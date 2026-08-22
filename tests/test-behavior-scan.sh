#!/bin/bash
# tests/test-behavior-scan.sh — Tier-0 behavior scanner (ADR-0006 F1)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCANNER="$ROOT/bin/oracfit-behavior-scan.py"
FIX="$ROOT/tests/fixtures/behavior"

PASS=0
FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

assert_contains() {
  local label="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -q "$needle"; then
    ok "$label contains $needle"
  else
    bad "$label missing $needle (output: $(echo "$haystack" | head -c 200))"
  fi
}

assert_exit() {
  local label="$1" expected="$2"
  shift 2
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$expected" ]; then
    ok "$label exit $expected"
  else
    bad "$label expected exit $expected got $rc"
  fi
}

# --- restore-loop: B1 + exit 2 ---
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/restore-loop.jsonl" 2>/dev/null)" || RC=$?
assert_contains "restore-loop" "$OUT" '"id": "B1"'
assert_exit "restore-loop high severity" 2 python3 "$SCANNER" "$FIX/restore-loop.jsonl"

# B2 is likely on restore-loop (same failing python heredoc >=3x)
if echo "$OUT" | grep -q '"id": "B2"'; then
  ok "restore-loop also flags B2 (expected)"
else
  ok "restore-loop B2 absent (acceptable — B1 suffices)"
fi

# --- t3-empty-gap: B4 + exit 2 ---
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/t3-empty-gap.jsonl" 2>/dev/null)" || RC=$?
assert_contains "t3-empty-gap" "$OUT" '"id": "B4"'
assert_exit "t3-empty-gap high severity" 2 python3 "$SCANNER" "$FIX/t3-empty-gap.jsonl"

# --- healthy-run: no flags + exit 0 ---
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/healthy-run.jsonl" 2>/dev/null)" || RC=$?
if [ -z "$OUT" ]; then
  ok "healthy-run produces no flags"
else
  bad "healthy-run should be clean (got: $(echo "$OUT" | head -c 200))"
fi
assert_exit "healthy-run clean" 0 python3 "$SCANNER" "$FIX/healthy-run.jsonl"

# --- --run-id: filtra runs históricos do mesmo events.jsonl ---
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/restore-loop.jsonl" --run-id tripstory-restore 2>/dev/null)" || RC=$?
if echo "$OUT" | grep -q '"B1"'; then
  ok "--run-id correto ainda flaga B1"
else
  bad "--run-id correto deveria flagar B1"
fi
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/restore-loop.jsonl" --run-id outro-run-qualquer 2>/dev/null)" || RC=$?
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then
  ok "--run-id de outro run filtra tudo (sem flags, exit 0)"
else
  bad "--run-id alheio deveria zerar flags (rc=$RC out='$(echo "$OUT" | head -c 120)')"
fi

# --- missing events file: exit 0 silent ---
MISSING="$FIX/does-not-exist-events.jsonl"
RC=0
ERR=""
ERR="$(python3 "$SCANNER" "$MISSING" 2>&1)" || RC=$?
if [ "$RC" -eq 0 ] && [ -z "$ERR" ]; then
  ok "missing events.jsonl fail-open exit 0 silent"
else
  bad "missing file should exit 0 silent (rc=$RC err='$ERR')"
fi

# --- mechanical run 100% mecânico (zero tool_call): B7 não deve flagar ---
OUT=""
RC=0
OUT="$(python3 "$SCANNER" "$FIX/mechanical-run-no-tools.jsonl" 2>/dev/null)" || RC=$?
if [ -z "$OUT" ] && [ "$RC" -eq 0 ]; then
  ok "mechanical-run-no-tools sem B7 (zero tool_call events)"
else
  bad "mechanical-run-no-tools não deveria flagar B7 (rc=$RC out='$(echo "$OUT" | head -c 200)')"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
