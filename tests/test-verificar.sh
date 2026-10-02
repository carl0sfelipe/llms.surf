#!/bin/bash
# tests/test-verificar.sh — `oracfit verificar`: modo direto visível no ledger e no painel.
# Proposta: docs/proposta-check-delegacao.md §3. Padrão: tests/test-model-override.sh.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OF="$ROOT/bin/oracfit"
TMPDIR="$(mktemp -d /tmp/oracfit-verificar.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_de() { set +e; "$@" >"$TMPDIR/last.log" 2>&1; echo $?; set -e; }

W="$TMPDIR/w"; mkdir -p "$W"; cd "$W"
cat >spec.md <<'EOF'
# fixture verificar

## Oráculo
- comando: test -f entregue
EOF
export ORACFIT_WORKDIR="$W"

echo "== 1. fechar sem abrir → erro de uso"
[ "$(rc_de "$OF" verificar spec.md t1)" -eq 3 ] && ok "exit 3" || not "exit 3"

echo "== 2. oráculo já verde no --antes → recusa"
touch entregue
[ "$(rc_de "$OF" verificar spec.md t2 --antes)" -eq 2 ] && ok "exit 2" || not "exit 2"
grep -q "Endureça o oráculo" "$TMPDIR/last.log" && ok "explica por quê" || not "explica por quê"
rm -f entregue

echo "== 3. vermelho → implementa → verde: pass no ledger como orquestrador"
[ "$(rc_de "$OF" verificar spec.md t3 --antes)" -eq 0 ] && ok "--antes abre o run" || not "--antes abre o run"
touch entregue
[ "$(rc_de "$OF" verificar spec.md t3)" -eq 0 ] && ok "fecha com pass" || not "fecha com pass"
python3 - "$W/.dispatch/ledger/mode.jsonl" <<'PY' && ok "ledger: pass, orquestrador, modo direto" || not "ledger: pass, orquestrador, modo direto"
import json, sys
d = json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert d["task"] == "t3" and d["status"] == "pass" and d["model_id"] == "orquestrador" and d["mode_id"] == "direto", d
PY
grep -q '"run_finished"' "$W/.dispatch/logs/events.jsonl" && ok "run_finished no painel" || not "run_finished no painel"
[ ! -f "$W/.dispatch/verificar/t3.json" ] && ok "run fechado (estado apagado)" || not "run fechado (estado apagado)"
rm -f entregue

echo "== 4. implementação errada → fail no ledger e saída do oráculo"
[ "$(rc_de "$OF" verificar spec.md t4 --antes)" -eq 0 ] || not "--antes t4"
[ "$(rc_de "$OF" verificar spec.md t4)" -eq 1 ] && ok "exit 1" || not "exit 1"
python3 - "$W/.dispatch/ledger/mode.jsonl" <<'PY' && ok "ledger: fail" || not "ledger: fail"
import json, sys
d = json.loads(open(sys.argv[1]).read().splitlines()[-1])
assert d["task"] == "t4" and d["status"] == "fail", d
PY

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
