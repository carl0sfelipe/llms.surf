#!/bin/bash
# Test: lib-oracfit-mode-loader.py (explicit rc — never cmd && ok || not)
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOADER="$SCRIPT_DIR/lib-oracfit-mode-loader.py"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-oracfit-mode-loader ==="

echo "--- validate kernel_test.yaml (T20) ---"
rc=0
python3 "$LOADER" validate "$ROOT/core/modes/kernel_test.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "kernel_test.yaml validates"; else not "kernel_test.yaml should validate (rc=$rc)"; fi

echo "--- validate normal.yaml ---"
rc=0
python3 "$LOADER" validate "$ROOT/core/modes/normal.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "normal.yaml validates"; else not "normal.yaml should validate (rc=$rc)"; fi

echo "--- validate unlock_plan.yaml ---"
rc=0
python3 "$LOADER" validate "$ROOT/core/modes/unlock_plan.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "unlock_plan.yaml validates"; else not "unlock_plan.yaml should validate (rc=$rc)"; fi

echo "--- validate vision_catalog.yaml ---"
rc=0
python3 "$LOADER" validate "$ROOT/core/modes/vision_catalog.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "vision_catalog.yaml validates"; else not "vision_catalog.yaml should validate (rc=$rc)"; fi

echo "--- validate ui_visual_qa.yaml ---"
rc=0
python3 "$LOADER" validate "$ROOT/core/modes/ui_visual_qa.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 0 ]; then ok "ui_visual_qa.yaml validates"; else not "ui_visual_qa.yaml should validate (rc=$rc)"; fi

echo "--- all oracle modes declare gauntlet ---"
missing=0
for f in "$ROOT"/core/modes/*.yaml; do
  if grep -qE 'oracle:\s*true' "$f" && ! grep -qE '^gauntlet:' "$f"; then
    echo "  missing gauntlet: in $(basename "$f")"
    missing=1
  fi
done
if [ "$missing" -eq 0 ]; then ok "every oracle mode has gauntlet:"; else not "some oracle modes lack gauntlet:"; fi

echo "--- unknown key test ---"
tmpfile=$(mktemp /tmp/oracfit-test-XXXXXX.yaml)
cat > "$tmpfile" <<'EOF'
id: bad
version: "1"
stages:
  - role: run
    model_ref: test
foo: 1
EOF
rc=0
python3 "$LOADER" validate "$tmpfile" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "unknown key -> exit 2"; else not "unknown key should exit 2, got $rc"; fi
rm -f "$tmpfile"

echo "--- map without rate_limit_s ---"
tmpfile=$(mktemp /tmp/oracfit-test-XXXXXX.yaml)
cat > "$tmpfile" <<'EOF'
id: bad
version: "1"
stages:
  - role: map
    model_ref: test
EOF
rc=0
python3 "$LOADER" validate "$tmpfile" 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then ok "map without rate_limit_s -> exit 2"; else not "map without rate_limit_s should exit 2, got $rc"; fi
rm -f "$tmpfile"

echo "--- resolve-tier cheap (E5-M4: lista fallback do catálogo carimbado) ---"
output=$(python3 "$LOADER" resolve-tier tier:cheap 2>/dev/null || true)
rc=$?
if [ -n "$output" ]; then ok "resolve-tier tier:cheap não vazio"; else not "resolve-tier should print non-empty"; fi
n_refs=$(printf '%s\n' "$output" | grep -c . || true)
if [ "$n_refs" -ge 3 ]; then ok "tier:cheap devolve >=3 refs vivos ($n_refs)"; else not "tier:cheap devolveu $n_refs refs (<3 — D5 reprova)"; fi
first_ref=$(printf '%s\n' "$output" | head -1)
if [ "$first_ref" = "mimo-v2.5-free" ] || [ "$first_ref" = "nemotron-3-ultra-free" ]; then ok "keyless primeiro na ordem ($first_ref)"; else not "primeiro ref não é keyless: $first_ref"; fi

echo "--- resolve-tier cheap: catálogo ausente reprova LOUD (E5-D3/D5) ---"
rc=0
errout=$(python3 "$LOADER" resolve-tier tier:cheap --catalog /tmp/free-catalog-inexistente-xyz.json 2>&1 >/dev/null) || rc=$?
if [ "$rc" -eq 2 ] && printf '%s' "$errout" | grep -q "catálogo"; then ok "catálogo ausente -> exit 2 com mensagem"; else not "catálogo ausente deveria exit 2 loud, got rc=$rc"; fi

echo "--- resolve-tier cheap: id morto stampado é pulado na porta (E5-M2) ---"
tmpreg=$(mktemp /tmp/oracfit-reg-XXXXXX.json)
python3 - "$ROOT/model-registry.json" "$tmpreg" <<'PYEOF'
import json, sys
reg = json.load(open(sys.argv[1]))
for m in reg["models"]:
    if m["id"] == "mimo-v2.5-free":
        m["id_status"] = "FANTASMA"
json.dump(reg, open(sys.argv[2], "w"), indent=2, ensure_ascii=False)
PYEOF
output=$(python3 "$LOADER" resolve-tier tier:cheap --registry "$tmpreg" 2>/tmp/oracfit-gate-err.txt || true)
rc=$?
if [ "$rc" -eq 0 ] && ! printf '%s' "$output" | grep -q "mimo-v2.5-free" && grep -q "WARN.*mimo-v2.5-free" /tmp/oracfit-gate-err.txt; then
  ok "ref morto pulado com WARN na porta"
else
  not "gate de id morto falhou (rc=$rc)"
fi
rm -f "$tmpreg" /tmp/oracfit-gate-err.txt

echo "--- resolve-tier with registry ---"
output=$(python3 "$LOADER" resolve-tier tier:cheap --registry "$ROOT/model-registry.json" 2>/dev/null || true)
if [ -n "$output" ]; then ok "resolve-tier with registry -> non-empty"; else not "resolve-tier with registry should print non-empty"; fi

echo "--- file missing ---"
rc=0
python3 "$LOADER" validate "/tmp/nonexistent-oracfit-mode.yaml" 2>&1 || rc=$?
if [ "$rc" -eq 3 ]; then ok "missing file -> exit 3"; else not "missing file should exit 3, got $rc"; fi

echo ""
echo "=== RESULTS: $pass passed, $fail failed ==="
if [ "$fail" -gt 0 ]; then
  exit 1
fi
echo "ALL TESTS PASSED"
exit 0
