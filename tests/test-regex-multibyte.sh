#!/bin/bash
# test-regex-multibyte.sh — acento dentro de conjunto `[...]` é defeito no macOS.
#
# Por que existe: o grep e o sed do macOS são BSD e tratam conjunto de caracteres
# BYTE A BYTE. Um acento ocupa dois bytes em UTF-8, então `[aã]` vira o conjunto
# de bytes {a, 0xC3, 0xA3} e o padrão casa meio caractere.
#
# Os dois efeitos medidos em 2026-07-28:
#   grep -qiE 'n[aã]o invente'  contra "não invente"        → NÃO CASA
#   sed  -E  's/[àáâã]/a/g'     contra "versão órfã"        → "versaao aorfaa"
#
# O primeiro reprovava spec que já trazia a cláusula anti-invenção, mandando o
# autor acrescentar o que já estava lá. O segundo CORROMPE o slug em vez de só
# falhar. Incidente: incidents/2026-07-28-acento-em-conjunto-de-regex-quebra-no.md
#
# A forma correta é ALTERNAÇÃO: `(a|ã)`, `(à|á|â|ã)`. Funciona nos dois grep.
#
# Exit: 0=nenhuma ocorrência, 1=achou

set -uo pipefail
cd "$(dirname "$0")/.."

# grep próprio do sistema: a shell interativa pode ter `grep` trocado por outra
# implementação que aceita multibyte em conjunto, e aí o teste não veria nada.
GREP=/usr/bin/grep
[ -x "$GREP" ] || GREP=grep

# Dois filtros, ambos por falso positivo real observado ao escrever este teste:
#   - linha de comentário: os próprios comentários que EXPLICAM o defeito citam
#     `[aã]` e seriam acusados.
#   - só interessa regex que vai para grep/sed. O `[oõ]` de
#     bin/check-output-invencao.sh:56 está dentro de um bloco Python, e o módulo
#     `re` do Python trata Unicode corretamente — ali não é defeito.
ACHADOS=$("$GREP" -rnE '\[[A-Za-z]*[À-ÿ][A-Za-zÀ-ÿ]*\]' \
  bin/ tests/ fluxos/ adapters/ 2>/dev/null \
  | "$GREP" -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | "$GREP" -E '(grep|sed)')

if [ -n "$ACHADOS" ]; then
  echo "❌ acento dentro de conjunto [...] — no macOS isso casa meio caractere:"
  echo "$ACHADOS" | sed 's/^/   /'
  echo
  echo "   Troque por alternação: [aã] → (a|ã)"
  exit 1
fi

echo "✅ nenhum conjunto de regex com acento"
exit 0
