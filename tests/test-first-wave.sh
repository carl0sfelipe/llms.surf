#!/bin/bash
# tests/test-first-wave.sh — a promessa do ANÚNCIO, na árvore VIRGEM.
#
# "Clone it — 2 minutes, no API key." O check D1 do gate local prova o start
# em workdir ESTRANHO; este prova o CLONE VIRGEM: só arquivos git-tracked (o
# que um git clone real baixaria — nenhum untracked, nenhuma sujeira local),
# env stub, bin/llms-surf start, exit 0 + stub_ok no disco. Sem rede: o stub
# runner não faz chamada nenhuma (ver adapters/stub/runner.sh). São promessas
# diferentes — workdir estranho ainda roda sobre ESTA árvore; clone virgem
# tem que se bastar com o que o git entrega.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d /tmp/oracfit-first-wave.XXXXXX)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Cópia fiel de clone: apenas arquivos git-tracked (índice), com modos.
# tar preserva o bit de execução que o start precisa (bin/llms-surf).
git -C "$ROOT" ls-files -z | (cd "$ROOT" && tar --null -T - -cf -) | tar -C "$TMP" -xf -
[ -x "$TMP/bin/llms-surf" ] || { echo "FAIL: clone sem bit de execução em bin/llms-surf"; exit 1; }

# O quickstart do site, palavra por palavra, a partir da árvore virgem.
cd "$TMP" || exit 1
export ORACFIT_ROOT="$TMP"
export DISPATCH_RUNNER="$TMP/adapters/stub/runner.sh"
export ORACFIT_WORKDIR="$TMP"

bash bin/llms-surf start >.first-wave.out 2>.first-wave.err
rc=$?

fail=0
if [ "$rc" -ne 0 ]; then
  echo "FAIL: bin/llms-surf start saiu rc=$rc na árvore virgem"
  tail -5 .first-wave.err >&2
  fail=1
fi
if ! grep -q stub_ok "$TMP/.dispatch/stub-proof" 2>/dev/null; then
  echo "FAIL: stub_ok ausente — o oráculo não teria o que ler no disco"
  fail=1
fi
if grep -q 'status: pass' .first-wave.out; then
  :
else
  echo "FAIL: run não fechou pass (ver .first-wave.out)"
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "PASS: clone virgem → start → exit 0 + stub_ok (2 minutos, sem chave, sem rede)"
  exit 0
fi
exit 1
