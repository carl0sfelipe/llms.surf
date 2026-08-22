#!/bin/bash
# test-oracfit-vision-gauntlet.sh — offline unit tests for P2 (no API calls)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VG="$SCRIPT_DIR/vision-gauntlet-loop.py"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-oracfit-vision-gauntlet ==="
tmpdir=$(mktemp -d /tmp/oracfit-vision-g-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

ours="$tmpdir/ours"
bar="$tmpdir/bar"
mkdir -p "$ours" "$bar"
# Empty image-ish files (pairing only needs names)
printf 'x' >"$ours/pdp.png"
printf 'x' >"$ours/catalog.png"
printf 'x' >"$bar/pdp.png"
printf 'x' >"$bar/other.png"  # no pair

echo "--- pair basenames ---"
pairs=$(python3 "$VG" pair "$ours" "$bar")
if echo "$pairs" | grep -q 'pdp.png' && ! echo "$pairs" | grep -q 'catalog.png'; then
  ok "pairs only shared basenames"
else
  not "pair output unexpected: $pairs"
fi

echo "--- rollup severity ---"
findings="$tmpdir/findings.jsonl"
cat >"$findings" <<'EOF'
{"arquivo":"pdp.png","overall_severity":"minor","summary_pt":"okish"}
{"arquivo":"catalog.png","overall_severity":"critical","summary_pt":"broken img"}
EOF
sev=$(python3 "$VG" rollup "$findings")
if [ "$sev" = "critical" ]; then ok "rollup picks worst=critical"; else not "sev=$sev"; fi

echo "--- revise brief from report ---"
report="$tmpdir/report.json"
cat >"$report" <<'EOF'
{
  "verdict": "REVISIONS_REQUIRED",
  "ceiling": 4,
  "pairs": [
    {
      "name": "pdp.png",
      "map_severity": "critical",
      "pick": "bar",
      "biggest_gap": "Product image is a gray placeholder",
      "rounds": [{"round":1,"pick":"bar","biggest_gap":"Product image is a gray placeholder"}]
    }
  ]
}
EOF
brief="$tmpdir/revise.md"
python3 "$VG" brief "$findings" "$report" "$brief" >/dev/null
if grep -q 'Product image is a gray placeholder' "$brief" && grep -q 'REVISIONS_REQUIRED' "$brief"; then
  ok "brief contains verdict + biggest_gap"
else
  not "brief missing content"
fi

echo "--- dispatch-vision-ui-qa help / arg guard ---"
rc=0
bash "$SCRIPT_DIR/dispatch-vision-ui-qa.sh" --help >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "help exits 0"; else not "help rc=$rc"; fi
rc=0
bash "$SCRIPT_DIR/dispatch-vision-ui-qa.sh" "$ours" "$tmpdir/out.jsonl" --gauntlet >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "--gauntlet without --bar → exit 2"; else not "expected 2 got $rc"; fi

echo "--- ui_visual_qa mode still validates ---"
rc=0
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$SCRIPT_DIR/../core/modes/ui_visual_qa.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "ui_visual_qa.yaml validates"; else not "validate rc=$rc"; fi

echo ""
echo "=== RESULTS: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then exit 1; fi
echo "ALL TESTS PASSED"
exit 0
