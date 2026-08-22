#!/bin/bash
# test-regras.sh — guarda as invariantes da poda de regras (D11).
#
# A poda de 2026-07-27 reduziu 35 regras para 10 e estabeleceu que o número de
# uma regra é IMUTÁVEL: removida, o número fica queimado. Sem teste, a próxima
# promoção recicla um número e toda referência antiga passa a apontar para
# outra regra — em silêncio.
#
# Mapa da poda: fluxos/_comum/mapa-regras.md
#
# Exit: 0=tudo passou, 1=alguma invariante quebrada

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_FILE="${SKILL_FILE:-$REPO_ROOT/SKILL.md}"
MAPA="$REPO_ROOT/fluxos/_comum/mapa-regras.md"

PASSOU=0
FALHOU=0

ok()   { echo "PASS: $1"; PASSOU=$((PASSOU + 1)); }
nok()  { echo "FAIL: $1"; FALHOU=$((FALHOU + 1)); }

# ── 1. Números de regra são únicos ───────────────────────────────────────────
NUMS=$(grep -oE '^\*\*[0-9]+\.' "$SKILL_FILE" | grep -oE '[0-9]+')
TOTAL=$(printf '%s\n' "$NUMS" | grep -c . )
UNICOS=$(printf '%s\n' "$NUMS" | sort -u | grep -c . )
if [ "$TOTAL" -gt 0 ] && [ "$TOTAL" = "$UNICOS" ]; then
  ok "números de regra únicos ($TOTAL regras vivas)"
else
  nok "número de regra duplicado no SKILL.md ($TOTAL linhas, $UNICOS distintos)"
fi

# ── 2. Marcador de último número emitido existe e cobre as vivas ─────────────
MARCADOR=$(grep -oE '<!-- ultimo-numero-de-regra: [0-9]+ -->' "$SKILL_FILE" | grep -oE '[0-9]+' | tail -1)
MAIOR_VIVA=$(printf '%s\n' "$NUMS" | sort -n | tail -1)
if [ -z "$MARCADOR" ]; then
  nok "marcador 'ultimo-numero-de-regra' ausente — incident.sh promote vai reciclar número"
elif [ "$MARCADOR" -ge "${MAIOR_VIVA:-0}" ]; then
  ok "marcador ($MARCADOR) >= maior regra viva ($MAIOR_VIVA)"
else
  nok "marcador ($MARCADOR) menor que a maior regra viva ($MAIOR_VIVA)"
fi

# ── 3. Toda regra viva aparece no mapa da poda como R ────────────────────────
FORA_DO_MAPA=""
for N in $NUMS; do
  grep -qE "^\| $N \|.*\| \*\*R\*\* \|" "$MAPA" || FORA_DO_MAPA="$FORA_DO_MAPA $N"
done
if [ -z "$FORA_DO_MAPA" ]; then
  ok "toda regra viva está classificada como R no mapa"
else
  nok "regra(s) viva(s) sem classificação R no mapa:$FORA_DO_MAPA"
fi

# ── 4. Nenhum arquivo cita regra que foi removida ────────────────────────────
# Citação a regra removida é a falha que a poda existe para evitar: o número
# sobrevive no comentário e aponta para outra coisa.
#
# Fora do escopo, de propósito:
#  - "regra N.M" e qualquer linha com "PRD": numeração do PRD, não do SKILL.md
#  - fluxos/_comum/mapa-regras.md: é o mapa da poda, cita removidas por dever
#  - bin/incident.sh: explica por que o número 35 morreu
CITACOES=$(grep -rnoE "regra [0-9]+(\.[0-9]+)?" "$REPO_ROOT/bin" "$REPO_ROOT/fluxos" "$REPO_ROOT/core" \
             --include='*.sh' --include='*.md' --include='*.json' 2>/dev/null \
           | grep -vE "regra [0-9]+\.[0-9]+" \
           | grep -v "mapa-regras.md" \
           | grep -v "bin/incident.sh" || true)
ORFAS=""
while IFS= read -r LINHA; do
  [ -z "$LINHA" ] && continue
  ARQ="${LINHA%%:*}"
  NLINHA=$(printf '%s' "$LINHA" | cut -d: -f2)
  grep -q "PRD" <(sed -n "${NLINHA}p" "$ARQ" 2>/dev/null) && continue
  N=$(printf '%s' "$LINHA" | grep -oE '[0-9]+$')
  [ -z "$N" ] && continue
  printf '%s\n' "$NUMS" | grep -qxF "$N" || ORFAS="$ORFAS"$'\n'"  $LINHA"
done <<< "$CITACOES"
ORFAS=$(printf '%s' "$ORFAS" | grep -v '^$' || true)
if [ -z "$ORFAS" ]; then
  ok "nenhuma citação a regra removida"
else
  nok "citação a regra removida (troque por incidents/<id>):"
  printf '%s\n' "$ORFAS"
fi

# ── 5. Todo caminho de incidente citado existe ───────────────────────────────
QUEBRADOS=""
while IFS= read -r P; do
  [ -f "$REPO_ROOT/$P" ] || QUEBRADOS="$QUEBRADOS $P"
done < <(grep -rhoE "incidents/[a-z0-9.-]+\.md" "$REPO_ROOT/bin" "$REPO_ROOT/fluxos" \
           "$REPO_ROOT/core" "$REPO_ROOT/adapters" "$SKILL_FILE" 2>/dev/null | sort -u)
if [ -z "$QUEBRADOS" ]; then
  ok "todo incidente citado existe em incidents/"
else
  nok "incidente citado que não existe:$QUEBRADOS"
fi

echo ""
echo "=== RESUMO ==="
echo "Passou: $PASSOU | Falhou: $FALHOU"
[ "$FALHOU" -eq 0 ] || exit 1
exit 0
