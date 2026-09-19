#!/usr/bin/env bash
# test-kernel-test-mode.sh — T20: kernel_test mode validates and a stub
# oracfit run of T01 (2 stages → dispatch-stages) leaves attempts +
# oracle_exit + provider_efetivo on the mode ledger.
#
# writes: scratch workdir only
# reads: core/modes/kernel_test.yaml, kernel/test-specs/oracle.sh

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not_() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-kernel-test-mode (T20) ==="

rc=0
python3 "$ROOT/bin/lib-oracfit-mode-loader.py" validate "$ROOT/core/modes/kernel_test.yaml" >/dev/null || rc=$?
[ "$rc" -eq 0 ] && ok "kernel_test.yaml validate" || not_ "validate rc=$rc"

rc=0
bash "$ROOT/kernel/test-specs/oracle.sh" T01 >/dev/null || rc=$?
[ "$rc" -eq 0 ] && ok "oracle.sh T01 (report + cargo test)" || not_ "oracle.sh T01 rc=$rc"

WD=$(mktemp -d /tmp/t20-mode-XXXXXX)
cleanup() { rm -rf "$WD"; }
trap cleanup EXIT
git -C "$WD" init -q
git -C "$WD" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
mkdir -p "$WD/.dispatch"
cat > "$WD/spec.md" <<'EOS'
# spec: t20-kernel-test

## Tarefa

Crie o arquivo `.dispatch/stub-proof` com exatamente 3 linhas:

    stub_ok
    model_id=<o identificador do modelo com que você foi lançado>
    spec=<o nome desta spec>

## Regras

Nao invente outro caminho, numero, prazo ou fato alem do listado abaixo.
Nao use declare const como workaround — artefato inexistente nao se
declara, se cria.

## Dados verificados

- Existe `.dispatch` no workdir — o dispatcher cria o diretório antes de
  qualquer preflight, em todo run.

## Oráculo

- comando: test -f .dispatch/stub-proof && grep -q stub_ok .dispatch/stub-proof
- exit esperado: 0 — antes do run, exit 1 sem stderr é o estado correto.
EOS

rc=0
ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh" \
  KERNEL_TEST_ID=T01 \
  bash "$ROOT/bin/oracfit" run kernel_test "$WD/spec.md" t20-t01 --workdir "$WD" \
  >"$WD/mode.out" 2>&1 || rc=$?
[ "$rc" -eq 0 ] && ok "oracfit run kernel_test T01 (stub, 2 stages) exit 0" || not_ "oracfit run rc=$rc $(tail -8 "$WD/mode.out")"

if grep -q 'mechanical stage run: running command' "$WD/mode.out"; then
  ok "command stage ran oracle.sh"
else
  not_ "command stage did not run (not dispatch-stages?) $(grep -E 'stage |mechanical|dispatch-' "$WD/mode.out" | head -8)"
fi

LEDGER="$WD/.dispatch/ledger/mode.jsonl"
if [ ! -f "$LEDGER" ]; then
  not_ "mode ledger missing"
else
  python3 - "$LEDGER" <<'PY' && ok "ledger has provider_efetivo, attempt, oracle_exit" || not_ "ledger fields missing"
import json, sys
row = json.loads(open(sys.argv[1]).read().splitlines()[-1])
need = ("oracle_exit", "attempt", "provider_efetivo")
missing = [k for k in need if k not in row or row[k] == ""]
if missing:
    print("missing", missing, row)
    raise SystemExit(1)
if str(row["oracle_exit"]) != "0":
    print("oracle_exit", row["oracle_exit"])
    raise SystemExit(1)
PY
fi

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
