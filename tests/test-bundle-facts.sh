#!/bin/bash
# Focused tests for bin/check-bundle-facts.py (ADR-0003).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECKER="$ROOT/bin/check-bundle-facts.py"
TMPDIR="$(mktemp -d /tmp/oracfit-bundle-facts.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
cat >"$SPEC" <<'EOF'
# Bundle facts fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
Produto: 24GB, 1TB, R$ 4.290,00, 120 W, 60 fps, 3,20 GHz,
500 MHz, 2.000 mm e 15%.
A data 2026 e as 12 parcelas não têm unidade e não entram no gate.

## Números derivados permitidos
- derived: R$ 357,50 <- R$ 4.290,00 / 12 — parcela mensal explicitamente autorizada
EOF

NORMALIZED="$TMPDIR/normalized.txt"
cat >"$NORMALIZED" <<'EOF'
RAM 24 GB; storage 1TB; price R$4290; power 120W.
Video 60 fps; clock 3.2GHz; memory 500 MHz; width 2000mm; tax 15%.
There are 12 installments in 2026, but those numbers have no declared unit.
EOF

if python3 "$CHECKER" "$SPEC" "$NORMALIZED" >/dev/null; then
  ok "Brazilian formatting and unit normalization pass"
else
  not "equivalent Brazilian numeric formats should pass"
fi

BUNDLE_DIR="$TMPDIR/bundle-dir"
mkdir -p "$BUNDLE_DIR"
cp "$NORMALIZED" "$BUNDLE_DIR/content.md"
printf 'A section number 42 and date 2026 have no declared unit.\n' >"$BUNDLE_DIR/metadata.txt"
if python3 "$CHECKER" "$SPEC" "$BUNDLE_DIR" >/dev/null; then
  ok "bundle directory input scans text files and ignores unitless numbers"
else
  not "bundle directory input should pass"
fi

MISMATCH="$TMPDIR/mismatch.txt"
printf 'RAM advertised as 32GB on source line\n' >"$MISMATCH"
out=""
rc=0
out="$(python3 "$CHECKER" "$SPEC" "$MISMATCH" 2>&1)" || rc=$?
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$out" | grep -qF "32GB" \
  && printf '%s\n' "$out" | grep -qF "expected ground-truth set for GB" \
  && printf '%s\n' "$out" | grep -qF "source line:"; then
  ok "numeric mismatch fails with value, expected set, and source line"
else
  not "numeric mismatch diagnostics incomplete (rc=$rc): $out"
fi

DERIVED="$TMPDIR/derived.txt"
printf 'Pagamento: R$ 357,50 em 12 parcelas.\n' >"$DERIVED"
if python3 "$CHECKER" "$SPEC" "$DERIVED" >/dev/null; then
  ok "explicit auditable derived-number whitelist passes"
else
  not "declared derived number should pass"
fi

UNDECLARED_DERIVED="$TMPDIR/undeclared-derived.txt"
printf 'Pagamento: R$ 358,00 em 12 parcelas.\n' >"$UNDECLARED_DERIVED"
rc=0
python3 "$CHECKER" "$SPEC" "$UNDECLARED_DERIVED" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "non-whitelisted derived number fails closed"
else
  not "non-whitelisted derived number should fail (rc=$rc)"
fi

BAD_SPEC="$TMPDIR/bad-whitelist.md"
cp "$SPEC" "$BAD_SPEC"
python3 - "$BAD_SPEC" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
text = path.read_text()
text = text.replace(
    "- derived: R$ 357,50 <- R$ 4.290,00 / 12 — parcela mensal explicitamente autorizada",
    "- derived: R$ 357,50 <- R$ 99,00 / 12 — fonte que não existe",
)
path.write_text(text)
PY
rc=0
python3 "$CHECKER" "$BAD_SPEC" "$DERIVED" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 1 ]; then
  ok "whitelist citing absent ground truth fails closed"
else
  not "unsafe whitelist should fail closed (rc=$rc)"
fi

echo
echo "=== RESULTS: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
