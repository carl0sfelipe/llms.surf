#!/bin/bash
# tests/test-artefato-template.sh — o template oficial passa nos gates que ensina.
#
# Incidente 2026-09-20-template-oficial-contradizia-check-spec-: o template
# ensinava crase na linha `comando:` (regra 46 reprova) e não trazia as
# defesas que o check-spec exige — quem copiava o template levava reprovação
# na primeira rodada. Este teste instancia o template (substitui cada
# <placeholder> por conteúdo de exemplo, sem tocar na estrutura) e roda o
# bin/check-spec.sh contra o resultado: cópia preenchida tem que passar.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-template.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

TEMPLATE="$REPO_ROOT/fluxos/_comum/artefato-template.md"

# (1) nenhuma linha de campo "- chave:" do template contém crase — checagem
#     direta, pega o ensino do padrão errado mesmo antes do render.
if grep -qE '^[-*][[:space:]]*[[:alnum:]_]+([[:space:]]+[[:alnum:]_]+)?:.*`' "$TEMPLATE"; then
  bad "template tem linha de campo '- chave:' com CRASE — ensina o que a regra 46 reprova"
else
  ok "nenhuma linha de campo '- chave:' no template contém crase"
fi

# (2) render: cada <placeholder> vira conteúdo de exemplo; estrutura intacta.
RENDERED="$TMPDIR/rendered-spec.md"
sed -E 's/<[^>]+>/EXEMPLO/g' "$TEMPLATE" >"$RENDERED"

if bash "$REPO_ROOT/bin/check-spec.sh" "$RENDERED" >/dev/null 2>&1; then
  ok "template instanciado passa no check-spec.sh (cópia preenchida não reprova)"
else
  bad "template instanciado REPROVA no check-spec.sh — quem copia o template leva reprovação na primeira rodada"
fi

# (3) o render tem exatamente 1 linha 'comando:' contável (1 arquivo = 1
#     história; o exemplo interno é indentado de propósito para não contar).
N_COMANDO=$(grep -cE '^[-*][[:space:]]*comando:' "$RENDERED" || true)
if [ "$N_COMANDO" = "1" ]; then
  ok "template instanciado tem exatamente 1 linha 'comando:'"
else
  bad "template instanciado tem ${N_COMANDO} linhas 'comando:' (esperado 1 — preflight recusa N>1)"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
