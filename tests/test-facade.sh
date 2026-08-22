#!/usr/bin/env bash
# tests/test-facade.sh — guarda a fachada pública llms-surf (rename mínimo).
#
# A fachada é o contrato público do llms.surf: se quebrar (path resolution,
# permissão, repasse de args), o comando documentado nos 3 READMEs morre e
# nenhuma outra suíte percebe — elas chamam bin/oracfit diretamente.
#
# TESTE 1: help passa pela fachada (argv repassado, exec resolve o alvo).
# TESTE 2: subcomando real com saída (modes lista modos do ROOT).
# TESTE 3: exit code de erro É propagado (subcomando desconhecido → exit 2).

set -uo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FACADE="$REPO_ROOT/bin/llms-surf"
pas=0; falhas=0
ok()  { pas=$((pas + 1)); echo "PASS: $1"; }
not() { falhas=$((falhas + 1)); echo "FAIL: $1"; }

[ -x "$FACADE" ] && ok "fachada existe e é executável" || not "faltando ou não executável: $FACADE"

out=$("$FACADE" --help 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -qi "usage\|uso" \
  && ok "--help repassado (rc=0, texto de uso)" || not "--help pela fachada falhou (rc=$rc)"

out=$("$FACADE" modes 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -q "normal" \
  && ok "modes pela fachada lista modos do ROOT" || not "modes pela fachada (rc=$rc): $(echo "$out" | head -2)"

"$FACADE" __subcomando_inexistente__ >/dev/null 2>&1; rc=$?
[ "$rc" -eq 2 ] && ok "exit de erro propagado (rc=2, desconhecido)" || not "esperava rc=2, veio $rc"

echo "──"
echo "facade guard: $pas PASS / $falhas FAIL"
[ "$falhas" -eq 0 ]
