#!/bin/bash
# tests/test-credential-noise.sh — aviso de perna sem credencial 1x por run.
#
# Incidente 2026-09-20-run-with-fallback-reimprime-pulando-sem-: o loop de
# attempts re-executa o run-with-fallback.sh inteiro por tentativa, e a
# listagem de pernas puladas por falta de credencial era reimpressa íntegra
# a cada tentativa (9 pernas × 5 tentativas = 45 linhas do mesmo aviso).
# Agora: detalhe na 1ª tentativa (DISPATCH_ATTEMPT<=1 ou unset), uma linha
# resumida nas seguintes.
#
# Fixtures: ORACFIT_AUTH_JSON/ORACFIT_OPENCODE_CONFIG apontam para caminhos
# inexistentes (contrato de env de teste da lib-free-credentials) — assim o
# gate de credencial recusa TODA perna keyless=false do catálogo real,
# deterministicamente, com ou sem credenciais reais na máquina.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-crednoise.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

export DISPATCH_RUNNER="$REPO_ROOT/adapters/stub/runner.sh"
export ORACFIT_AUTH_JSON="$TMPDIR/auth-inexistente.json"
export ORACFIT_OPENCODE_CONFIG="$TMPDIR/config-inexistente.json"
unset DISPATCH_ATTEMPT ORACFIT_STAGE_ATTEMPT MODEL_REGISTRY FREE_CATALOG 2>/dev/null || true

SPEC="$TMPDIR/spec.md"
echo "## Objetivo
qualquer coisa

## Oráculo
- comando: test -f nunca-vai-existir.txt
- exit esperado: 0" >"$SPEC"

# Pernas que DEVEM ser puladas (keyless=false no catálogo real).
N_NONKEYLESS=$(python3 -c '
import json
cat = json.load(open("'"$REPO_ROOT"'/data/free-catalog.json"))
print(sum(1 for m in cat.get("models", []) if not m.get("keyless", True)))
')

# (1) tentativa 1 (sem DISPATCH_ATTEMPT): listagem detalhada, uma linha por perna.
# O padrão de detalhe ('env herdada não conta') é exclusivo da linha por perna —
# a linha de resumo também menciona "sem credencial", não pode contar aqui.
set +e
bash "$REPO_ROOT/bin/run-with-fallback.sh" tier:cheap "$SPEC" >"$TMPDIR/run1.txt" 2>&1
RC1=$?
set -e
N_DETALHE_1=$(grep -c 'env herdada não conta' "$TMPDIR/run1.txt" || true)
N_RESUMO_1=$(grep -c 'perna(s) puladas' "$TMPDIR/run1.txt" || true)
if [ "$N_NONKEYLESS" -gt 0 ] && [ "$N_DETALHE_1" = "$N_NONKEYLESS" ] && [ "$N_RESUMO_1" = "0" ]; then
  ok "tentativa 1: $N_DETALHE_1 linha(s) de detalhe, zero resumo — como antes"
else
  bad "tentativa 1: esperado $N_NONKEYLESS detalhe(s) e 0 resumo, veio detalhe=$N_DETALHE_1 resumo=$N_RESUMO_1 (rc=$RC1)"
fi

# (2) tentativa 2 (DISPATCH_ATTEMPT=2): NENHUMA linha de detalhe, 1 resumo.
set +e
DISPATCH_ATTEMPT=2 bash "$REPO_ROOT/bin/run-with-fallback.sh" tier:cheap "$SPEC" >"$TMPDIR/run2.txt" 2>&1
RC2=$?
set -e
N_DETALHE_2=$(grep -c 'env herdada não conta' "$TMPDIR/run2.txt" || true)
N_RESUMO_2=$(grep -c 'perna(s) puladas' "$TMPDIR/run2.txt" || true)
if [ "$N_NONKEYLESS" -gt 0 ] && [ "$N_DETALHE_2" = "0" ] && [ "$N_RESUMO_2" = "1" ]; then
  ok "tentativa 2: 0 detalhe, 1 linha resumo — ruído não se repete"
else
  bad "tentativa 2: esperado 0 detalhe e 1 resumo, veio detalhe=$N_DETALHE_2 resumo=$N_RESUMO_2 (rc=$RC2)"
fi

# (3) quando a cadeia INTEIRA é pulada (só pernas keyless=false no catálogo),
# o erro loud de cadeia vazia tem que continuar loud na tentativa 2 — o latch
# deduplica o AVISO, nunca a FALHA. Se o catálogo tem perna keyless, o stub
# atende e este caso não se aplica.
if grep -q 'vazia após gate de credencial' "$TMPDIR/run1.txt"; then
  if grep -q 'vazia após gate de credencial' "$TMPDIR/run2.txt"; then
    ok "cadeia vazia por credencial segue sendo erro loud na tentativa 2"
  else
    bad "erro loud de cadeia vazia sumiu na tentativa 2 — o latch engoliu a falha"
  fi
else
  ok "catálogo tem perna keyless (stub atendeu) — caso cadeia-vazia não exercitado aqui"
fi

if [ "$N_NONKEYLESS" = "0" ]; then
  echo "NOTE: catálogo sem pernas keyless=false hoje — (1) e (2) ficaram vacuos."
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
