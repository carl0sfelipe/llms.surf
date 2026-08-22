#!/bin/bash
# Test: dispatch-mode.sh resolve custom mode from workdir overlay before
# falling back to ORACFIT_ROOT (AD-16, v1-modes-catalog.md §4).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-oracfit-workdir-overlay ==="

tmpworkdir=$(mktemp -d /tmp/oracfit-workdir-test-XXXXXX)
mkdir -p "$tmpworkdir/core/modes"
cat > "$tmpworkdir/core/modes/only_in_workdir.yaml" <<'EOF'
id: only_in_workdir
version: "1"
stages:
  - role: run
    model_ref: test
    oracle: true
max_attempts: 1
EOF

echo "--- mode that exists ONLY in workdir overlay is found (not just ROOT) ---"
rc=0
ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  "$SCRIPT_DIR/dispatch-mode.sh" --workdir "$tmpworkdir" --dry-run only_in_workdir "$SCRIPT_DIR/dispatch-mode.sh" smoke 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "dry-run finds workdir-only mode"; else not "dry-run should exit 0, got $rc"; fi

echo "--- workdir overlay wins over ROOT when both define the same id ---"
cat > "$tmpworkdir/core/modes/normal.yaml" <<'EOF'
id: normal
version: "1"
name: overlay-normal-marker
stages:
  - role: run
    model_ref: test
    oracle: true
max_attempts: 1
EOF
rc=0
resolved=$(python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$tmpworkdir/core/modes/normal.yaml" 2>&1) || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "workdir overlay normal.yaml validates independently of ROOT's normal.yaml"
else
  not "workdir overlay normal.yaml should validate (rc=$rc): $resolved"
fi

echo "--- no overlay: falls back to ROOT/core/modes (existing behavior unchanged) ---"
tmpworkdir2=$(mktemp -d /tmp/oracfit-workdir-test-XXXXXX)
rc=0
ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  "$SCRIPT_DIR/dispatch-mode.sh" --workdir "$tmpworkdir2" --dry-run normal "$SCRIPT_DIR/dispatch-mode.sh" smoke 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "falls back to ROOT/core/modes/normal.yaml when no overlay"; else not "should exit 0, got $rc"; fi

echo "--- unknown mode in both workdir and ROOT -> clear error naming both paths ---"
tmpworkdir3=$(mktemp -d /tmp/oracfit-workdir-test-XXXXXX)
rc=0
out=$(ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  "$SCRIPT_DIR/dispatch-mode.sh" --workdir "$tmpworkdir3" nonexistent_mode_xyz "$SCRIPT_DIR/dispatch-mode.sh" smoke 2>&1) || rc=$?
if [ "$rc" -eq 3 ] && echo "$out" | grep -q "$tmpworkdir3/core/modes/nonexistent_mode_xyz.yaml" && echo "$out" | grep -q "$ROOT/core/modes/nonexistent_mode_xyz.yaml"; then
  ok "unknown mode error names both tried paths"
else
  not "unknown mode error should name both paths, rc=$rc: $out"
fi

echo "--- oracfit mode validate: finds workdir-only mode via CLI (not just dispatch-mode.sh) ---"
rc=0
out=$(ORACFIT_ROOT="$ROOT" ORACFIT_WORKDIR="$tmpworkdir" "$SCRIPT_DIR/oracfit" mode validate only_in_workdir 2>&1) || rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "OK $tmpworkdir/core/modes/only_in_workdir.yaml"; then
  ok "oracfit mode validate resolves workdir-only mode"
else
  not "oracfit mode validate should find workdir-only mode, rc=$rc: $out"
fi

echo "--- oracfit modes: lists workdir overlay first, marks ROOT shadow ---"
rc=0
out=$(ORACFIT_ROOT="$ROOT" ORACFIT_WORKDIR="$tmpworkdir" "$SCRIPT_DIR/oracfit" modes 2>&1) || rc=$?
if [ "$rc" -eq 0 ] \
  && echo "$out" | grep -q "only_in_workdir" \
  && echo "$out" | grep -q "normal (shadowed by workdir overlay)"; then
  ok "oracfit modes lists overlay + marks shadowed ROOT mode"
else
  not "oracfit modes should list overlay and mark shadow, rc=$rc: $out"
fi

rm -rf "$tmpworkdir" "$tmpworkdir2" "$tmpworkdir3"

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
