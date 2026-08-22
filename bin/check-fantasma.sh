#!/bin/bash
# check-fantasma.sh — o lint que o compilador não faz.
#
# `declare const x: T` é TypeScript legal: nenhuma flag do tsc reclama, o
# arquivo compila limpo em modo strict. Mas `declare` não gera código —
# some no emit. O `.js` publicado chama uma função que nunca existiu.
# Medido em packages/kit-storefront: strict completo dá 0 erros de tsc e,
# mesmo assim, 2 arquivos (login-form.tsx, register-form.tsx) têm
# `declare const loginCustomer`/`registerCustomer` como stub — sem este
# script, ninguém no compilador teria avisado.
#
# `as any` e `@ts-ignore` são as outras duas fantasmas: desligam o
# typechecker localmente sem deixar rastro fora do diff.
#
# NÃO é "grep == 0": debito pré-existente e documentado (stub marcado como
# tal) não é o alvo. O alvo é FANTASMA NOVO — por isso baseline, não zero
# absoluto (mesmo princípio da regra de-branding classe D no
# plan_dispatch_2.0_fixed.md: "hits == baseline_permitido", não "hits == 0").
#
# Uso: bin/check-fantasma.sh <diretório-alvo> <arquivo-de-baseline>
# Primeira execução (baseline ausente): cria o baseline com o estado atual e
#   passa — é aceitar a dívida de hoje, não perdoar a de amanhã.
# Execuções seguintes: falha só se aparecer entrada NOVA (fora do baseline).
# Entrada que sumiu (foi corrigida) gera aviso, não falha — não pune quem
# limpou dívida antes do baseline ser atualizado.
#
# Exit: 0=sem fantasma novo (ou baseline recém-criado), 1=fantasma novo achado, 3=erro de uso

set -uo pipefail

TARGET="${1:?Uso: check-fantasma.sh <diretório-alvo> <arquivo-de-baseline>}"
BASELINE="${2:?Uso: check-fantasma.sh <diretório-alvo> <arquivo-de-baseline>}"

[ -d "$TARGET" ] || { echo "check-fantasma.sh: diretório não existe: $TARGET" >&2; exit 3; }

ACHADOS=$(mktemp)
trap 'rm -f "$ACHADOS"' EXIT

# find + grep, não grep -r direto: precisamos excluir node_modules/dist/testes
# sem depender de --exclude-dir (BSD grep do macOS aceita, mas a lista de
# exclusão fica mais legível como filtro de path aqui).
find "$TARGET" -type f \( -name '*.ts' -o -name '*.tsx' \) \
    -not -path '*/node_modules/*' \
    -not -path '*/dist/*' \
    -not -path '*/__tests__/*' \
    -not -name '*.test.ts' -not -name '*.test.tsx' \
    -print0 \
  | xargs -0 grep -nE 'declare[[:space:]]+const|declare[[:space:]]+let|declare[[:space:]]+var|as[[:space:]]+any\b|@ts-ignore' \
    2>/dev/null \
  | sed "s#^$TARGET/##" \
  | sort > "$ACHADOS"

if [ ! -f "$BASELINE" ]; then
  mkdir -p "$(dirname "$BASELINE")"
  cp "$ACHADOS" "$BASELINE"
  N=$(wc -l < "$BASELINE" | tr -d ' ')
  echo "ℹ️  baseline criado com $N entrada(s) já existentes em $BASELINE — commite este arquivo."
  echo "   A partir de agora, só entrada NOVA (fora dele) reprova."
  exit 0
fi

NOVOS=$(comm -13 <(sort "$BASELINE") "$ACHADOS")
SUMIDOS=$(comm -23 <(sort "$BASELINE") "$ACHADOS")

if [ -n "$SUMIDOS" ]; then
  echo "ℹ️  entrada(s) do baseline que sumiram (dívida corrigida — atualize o baseline se for definitivo):"
  echo "$SUMIDOS" | sed 's/^/   - /'
fi

if [ -z "$NOVOS" ]; then
  echo "✅ sem fantasma novo em $TARGET (contra baseline $BASELINE)"
  exit 0
fi

echo "❌ fantasma NOVO — declare/as any/@ts-ignore fora do baseline:" >&2
echo "$NOVOS" | sed 's/^/   - /' >&2
echo "   Se for débito aceito de propósito, adicione a linha ao baseline: $BASELINE" >&2
exit 1
