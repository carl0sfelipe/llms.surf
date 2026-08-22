#!/bin/bash
# test-oracfit-gauntlet.sh — unit smoke for lib-oracfit-gauntlet.sh (no model).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/lib-oracfit-gauntlet.sh"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-oracfit-gauntlet ==="

tmpdir=$(mktemp -d /tmp/oracfit-gauntlet-test-XXXXXX)
trap 'rm -rf "$tmpdir"' EXIT

echo "--- compose injects feedback ---"
base="$tmpdir/base.md"
accum="$tmpdir/feedback.md"
out="$tmpdir/out.md"
echo "# Spec" >"$base"
echo "do the thing" >>"$base"
printf 'FAIL: missing file X\n' >"$tmpdir/oracle.log"
oracfit_gauntlet_append_feedback "$accum" 1 1 "$tmpdir/oracle.log" >/dev/null
oracfit_gauntlet_compose_spec "$base" "$accum" "$out"
if grep -q 'GAUNTLET FEEDBACK' "$out" && grep -q 'FAIL: missing file X' "$out" && grep -q '# Spec' "$out"; then
  ok "compose includes base + GAUNTLET FEEDBACK + oracle log"
else
  not "compose missing feedback content"
fi

echo "--- biggest_gap prefers FAIL line ---"
gap="$(oracfit_gauntlet_biggest_gap "$tmpdir/oracle.log" 1)"
if echo "$gap" | grep -qi 'FAIL'; then
  ok "biggest_gap extracted FAIL line"
else
  not "biggest_gap=$gap"
fi

echo "--- normal.yaml gauntlet cfg ---"
en="$(oracfit_gauntlet_cfg "$ROOT/core/modes/normal.yaml" enabled)"
inj="$(oracfit_gauntlet_cfg "$ROOT/core/modes/normal.yaml" inject_feedback)"
ceil="$(oracfit_gauntlet_cfg "$ROOT/core/modes/normal.yaml" safety_ceiling)"
resolved="$(oracfit_gauntlet_resolve_max_attempts "$ROOT/core/modes/normal.yaml" 3)"
if [ "$en" = "true" ] && [ "$inj" = "true" ] && [ "$resolved" = "5" ]; then
  ok "normal.yaml enabled+inject; ceiling raises 3→5 (got ceil=$ceil resolved=$resolved)"
else
  not "normal cfg en=$en inj=$inj ceil=$ceil resolved=$resolved"
fi

echo "--- mode without gauntlet block keeps max_attempts ---"
noblock="$tmpdir/noblock.yaml"
cat >"$noblock" <<'EOF'
id: noblock
version: "1"
stages:
  - role: run
    model_ref: x
    oracle: true
max_attempts: 3
EOF
resolved2="$(oracfit_gauntlet_resolve_max_attempts "$noblock" 3)"
if [ "$resolved2" = "3" ]; then
  ok "no gauntlet block → max_attempts unchanged"
else
  not "expected 3 got $resolved2"
fi

echo "--- validate modes with gauntlet key ---"
rc=0
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$ROOT/core/modes/normal.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "normal.yaml validates with gauntlet"; else not "normal validate rc=$rc"; fi
rc=0
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$ROOT/core/modes/content_factory.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "content_factory.yaml validates"; else not "content_factory validate rc=$rc"; fi

echo "--- unknown gauntlet key fails ---"
bad="$tmpdir/bad.yaml"
cat >"$bad" <<'EOF'
id: bad
version: "1"
stages:
  - role: run
    model_ref: x
gauntlet:
  enabled: true
  weird_key: 1
EOF
rc=0
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$bad" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "unknown gauntlet key → exit 2"; else not "expected exit 2 got $rc"; fi

echo "--- extract ## Barra ---"
barra_spec="$tmpdir/barra.md"
cat >"$barra_spec" <<'EOF'
# Task
## Barra
- nome: Stripe pricing
- como fetchar: https://stripe.com/pricing
## Oraculo
- comando: true
EOF
barra="$(oracfit_gauntlet_extract_barra "$barra_spec")"
if echo "$barra" | grep -q 'Stripe pricing'; then
  ok "extract_barra finds named bar"
else
  not "extract_barra failed: $barra"
fi
empty="$(oracfit_gauntlet_extract_barra "$tmpdir/base.md" || true)"
if [ -z "$empty" ]; then ok "extract_barra empty without section"; else not "expected empty got=$empty"; fi

echo "--- escalate compose from ORIGINAL (no double-append) ---"
orig="$tmpdir/orig.md"
accum2="$tmpdir/accum2.md"
esc="$tmpdir/orig.md.escalate"
echo "# Orig" >"$orig"
printf 'oracle_exit=1\nFAIL: missing Y\n' >"$tmpdir/o2.log"
: >"$accum2"
oracfit_gauntlet_append_feedback "$accum2" 1 1 "$tmpdir/o2.log" >/dev/null
oracfit_gauntlet_append_feedback "$accum2" 2 1 "$tmpdir/o2.log" >/dev/null
oracfit_gauntlet_compose_spec "$orig" "$accum2" "$esc"
# Exactly one base header; two feedback rounds
bases=$(grep -c '^# Orig' "$esc" || true)
rounds=$(grep -c 'GAUNTLET FEEDBACK' "$esc" || true)
if [ "$bases" = "1" ] && [ "$rounds" = "2" ]; then
  ok "compose from original keeps 1 base + 2 feedback rounds"
else
  not "bases=$bases rounds=$rounds"
fi

echo "--- P3 critic JSON parse ---"
raw='{"biggest_gap":"UTM missing on CTA","must_fix":["Add UTM","Fix price"],"pick":"oracle"}'
parsed="$(oracfit_gauntlet_parse_critic_json "$raw")"
if echo "$parsed" | grep -q 'UTM missing' && echo "$parsed" | grep -q 'Add UTM'; then
  ok "parse_critic_json structured"
else
  not "parse failed: $parsed"
fi

echo "--- P4 ground-truth compose ---"
gt_spec="$tmpdir/gt.md"
cat >"$gt_spec" <<'EOF'
# X
## Dados verificados
- preco R$ 4.290
- 24GB RAM
## Oraculo
- comando: true
EOF
gt_out="$tmpdir/gt-extract.md"
oracfit_gauntlet_extract_ground_truth "$gt_spec" >"$gt_out"
comp="$tmpdir/composed-gt.md"
: >"$tmpdir/empty-accum.md"
oracfit_gauntlet_compose_spec "$gt_spec" "$tmpdir/empty-accum.md" "$comp" "$gt_out"
if grep -q 'oracfit-ground-truth' "$comp" && grep -q '4.290' "$comp"; then
  ok "compose injects ground-truth"
else
  not "ground-truth missing in compose"
fi

echo "--- gap stuck ---"
if oracfit_gauntlet_gap_stuck "missing UTM on all CTAs" "missing UTM on all CTAs"; then
  ok "identical gaps stuck"
else
  not "expected stuck"
fi
if oracfit_gauntlet_gap_stuck "missing UTM" "wrong price R$ 2990"; then
  not "different gaps should not stick"
else
  ok "different gaps not stuck"
fi

echo ""
echo "=== RESULTS: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
