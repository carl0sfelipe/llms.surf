#!/bin/bash
# incident.sh — módulo de feedback: incidente vira regra do framework
# Spec: core/feedback-protocol.md
#
# Uso:
#   bin/incident.sh new "<título>"                  cria incidente a partir do template
#   bin/incident.sh list                            tabela de incidentes
#   bin/incident.sh promote <id> "<texto da regra>" promove para regra no SKILL.md
#   bin/incident.sh audit                           exit 1 se houver recorrível sem regra
#
# Exit codes (RNF-04): 0=ok, 1=dívida aberta (audit), 3=erro de uso

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INCIDENTS_DIR="${INCIDENTS_DIR:-$REPO_ROOT/incidents}"
SKILL_FILE="${SKILL_FILE:-$REPO_ROOT/SKILL.md}"

mkdir -p "$INCIDENTS_DIR"

campo() {  # campo <arquivo> <nome>
  grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//"
}

slug() {
  # sed do macOS é BRE e não entende \+ — usar -E (ERE), portável nos dois.
  # Acento vai em ALTERNAÇÃO `(à|á)`, nunca em conjunto `[àá]`: o sed do macOS
  # trata o conjunto byte a byte e o acento ocupa dois bytes, então ele casa
  # meio caractere e CORROMPE a saída em vez de só falhar — "versão órfã" saía
  # como "versaao aorfaa". Descoberto em 2026-07-28.
  echo "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/(à|á|â|ã)/a/g; s/(é|ê)/e/g; s/í/i/g; s/(ó|ô|õ)/o/g; s/ú/u/g; s/ç/c/g' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-//; s/-$//' | cut -c1-40
}

case "${1:-}" in
  new)
    TITULO="${2:?Uso: incident.sh new \"<título>\"}"
    DATA=$(date +%Y-%m-%d)
    ID="$DATA-$(slug "$TITULO")"
    FILE="$INCIDENTS_DIR/$ID.md"
    if [ -e "$FILE" ]; then
      echo "❌ Já existe: $FILE" >&2
      exit 3
    fi
    cat > "$FILE" <<EOF
---
id: $ID
titulo: $TITULO
data: $DATA
recorrivel: ?
regra: pendente
status: aberto
---

# $TITULO

## Sintoma

<o que foi observado — sem interpretação>

## Causa

<com EVIDÊNCIA (comando + saída). Sem evidência, escreva: não determinada.
Nunca conflatar dois eventos distintos — cada um tem sua própria causa.>

## Correção aplicada

<o que mudou no repo, com arquivo:linha>

## Pode acontecer de novo?

<sim/não e por quê. Se sim, este incidente DEVE virar regra:
  bin/incident.sh promote $ID "<texto da regra>">
EOF
    echo "📝 Criado: $FILE"
    echo "   Preencha, defina 'recorrivel', e promova se for o caso:"
    echo "   bin/incident.sh promote $ID \"<texto da regra>\""
    ;;

  list)
    printf "%-46s %-11s %-10s %s\n" "ID" "RECORRIVEL" "REGRA" "STATUS"
    printf "%s\n" "------------------------------------------------------------------------------------"
    FOUND=0
    for f in "$INCIDENTS_DIR"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in TEMPLATE.md|INCIDENTS.md) continue ;; esac
      FOUND=1
      printf "%-46s %-11s %-10s %s\n" \
        "$(campo "$f" id)" "$(campo "$f" recorrivel)" "$(campo "$f" regra)" "$(campo "$f" status)"
    done
    [ "$FOUND" = "0" ] && echo "(nenhum incidente registrado)"
    ;;

  promote)
    ID="${2:?Uso: incident.sh promote <id> \"<texto da regra>\"}"
    REGRA="${3:?Uso: incident.sh promote <id> \"<texto da regra>\"}"
    FILE="$INCIDENTS_DIR/$ID.md"
    [ -f "$FILE" ] || { echo "❌ Incidente não encontrado: $FILE" >&2; exit 3; }
    [ -f "$SKILL_FILE" ] || { echo "❌ SKILL.md não encontrado: $SKILL_FILE" >&2; exit 3; }

    # Próximo número: MAIOR número já usado + 1. Depois da poda de 2026-07-27
    # (fluxos/_comum/mapa-regras.md) a numeração tem buracos de propósito —
    # número de regra removida NUNCA é reciclado, senão referência antiga em
    # código e incidente passa a apontar para outra regra.
    # O maior número VIVO não basta: a regra 35 foi removida na poda, então
    # max(vivas)+1 daria 33, que já pertenceu a outra regra. O marcador
    # `ultimo-numero-de-regra` guarda o maior número já EMITIDO.
    VIVA=$(grep -oE '^\*\*[0-9]+\.' "$SKILL_FILE" | grep -oE '[0-9]+' | sort -n | tail -1)
    [ -n "$VIVA" ] || { echo "❌ Não achei a lista de regras em $SKILL_FILE" >&2; exit 3; }
    EMITIDA=$(grep -oE '<!-- ultimo-numero-de-regra: [0-9]+ -->' "$SKILL_FILE" | grep -oE '[0-9]+' | tail -1)
    ULTIMA=$VIVA
    [ -n "$EMITIDA" ] && [ "$EMITIDA" -gt "$ULTIMA" ] && ULTIMA=$EMITIDA
    NOVA=$((ULTIMA + 1))

    # Insere a nova regra no fim da seção REGRAS, antes do primeiro `---` que
    # a fecha. Não pode ser "após a última regra": cada regra ocupa várias
    # linhas e a nova cairia no meio do corpo da anterior.
    LINHA=$(awk '/^## REGRAS$/{dentro=1} dentro && /^---$/{print NR; exit}' "$SKILL_FILE")
    [ -n "$LINHA" ] || { echo "❌ Não achei o fim da seção REGRAS em $SKILL_FILE" >&2; exit 3; }
    NEW_RULE="**$NOVA. $REGRA** (incidente: \`incidents/$ID.md\`)"
    awk -v ln="$LINHA" -v rule="$NEW_RULE" 'NR==ln{print rule; print ""} {print}' \
      "$SKILL_FILE" > "$SKILL_FILE.tmp" && mv "$SKILL_FILE.tmp" "$SKILL_FILE"

    # Avança o marcador: o número fica queimado mesmo se a regra for podada depois.
    sed -i '' -E "s/<!-- ultimo-numero-de-regra: [0-9]+ -->/<!-- ultimo-numero-de-regra: $NOVA -->/" "$SKILL_FILE" 2>/dev/null \
      || sed -i -E "s/<!-- ultimo-numero-de-regra: [0-9]+ -->/<!-- ultimo-numero-de-regra: $NOVA -->/" "$SKILL_FILE"

    # Atualiza o incidente
    sed -i '' -e "s/^regra: .*/regra: $NOVA/" -e "s/^status: .*/status: promovido/" "$FILE" 2>/dev/null \
      || sed -i -e "s/^regra: .*/regra: $NOVA/" -e "s/^status: .*/status: promovido/" "$FILE"

    echo "✅ Regra $NOVA adicionada ao SKILL.md:"
    echo "   $NEW_RULE"
    echo "   Incidente $ID marcado como promovido."

    # ── Análise de interação com regras existentes (regra da meta-regra) ──────
    # Regra nova nunca é isolada. Prova: as regras 17 (matar grupo) e 18
    # (detecção em streaming com `set -m`) juntas criaram o bug dos 9 órfãos,
    # que virou a regra do incidente incidents/2026-07-25-grupo-nao-basta-neto-com-set-m-escapa.md. Nenhuma das duas tinha o furo sozinha.
    echo ""
    echo "🔗 Possíveis interações (revise antes de confiar):"
    TERMOS=$(printf '%s' "$REGRA" | tr 'A-ZÀ-Ú' 'a-zà-ú' \
      | grep -oE '[a-zà-ú_-]{6,}' \
      | grep -vE '^(processo|comando|modelo|quando|porque|precisa|deveria|sempre|nunca|antes|depois|entao|tambem|apenas|mesmo|ainda|aquele|dentro|sobre|entre|nao)$' \
      | sort -u)
    # Achata cada regra em UMA linha ("<n> <texto inteiro>"). Depois da poda a
    # regra ocupa várias linhas: buscar só na linha do título perdia o corpo,
    # que é onde mora quase toda a substância.
    PLANO=$(mktemp)
    awk '
      /^## REGRAS$/ { dentro=1; next }
      dentro && /^---$/ { if (n) print n " " buf; exit }
      dentro && /^\*\*[0-9]+\./ {
        if (n) print n " " buf
        linha=$0; sub(/^\*\*/,"",linha); sub(/\..*/,"",linha)
        n=linha; buf=$0; next
      }
      dentro && n { buf = buf " " $0 }
    ' "$SKILL_FILE" | tr 'A-ZÀ-Ú' 'a-zà-ú' > "$PLANO"

    ACHOU=0
    for T in $TERMOS; do
      HITS=$(grep -i -- "$T" "$PLANO" | grep -oE '^[0-9]+' | grep -vxF "$NOVA" | tr '\n' ' ')
      if [ -n "$HITS" ]; then
        printf "   termo '%s' também aparece na(s) regra(s): %s\n" "$T" "$HITS"
        ACHOU=1
      fi
    done
    rm -f "$PLANO"
    [ "$ACHOU" = "0" ] && echo "   (nenhuma sobreposição de termo detectada — não garante ausência de conflito)"
    echo ""
    echo "   ⚠️  Sobreposição de termo NÃO é conflito, e ausência dela NÃO é prova de"
    echo "       independência. Registre no incidente, campo 'interage_com:', quais"
    echo "       regras esta nova reforça, restringe ou SUPERA — e o que pode quebrar."
    ;;

  audit)
    DIVIDA=0
    for f in "$INCIDENTS_DIR"/*.md; do
      [ -e "$f" ] || continue
      case "$(basename "$f")" in TEMPLATE.md|INCIDENTS.md) continue ;; esac
      REC=$(campo "$f" recorrivel)
      REG=$(campo "$f" regra)
      # `promote` grava `regra: <número>`. Portanto SÓ número é quitação.
      #
      # A versão anterior comparava com a string literal `pendente`, e por isso
      # aceitava qualquer outra coisa: `[A DEFINIR]`, ou o texto da regra
      # proposta em prosa. Medido em 2026-07-29 — dois incidentes escritos por
      # dispatch passaram no audit sem nunca terem sido promovidos: um trouxe
      # `regra: [A DEFINIR]` (correto pela cláusula anti-invenção, que manda
      # marcar o que não foi decidido) e o outro trouxe a regra proposta escrita
      # por extenso. Os dois são dívida, e o auditor da dívida dizia "sem
      # dívida".
      #
      # É a mesma família dos sensores cegos do 2.0/2.1: o campo estar
      # preenchido é EFEITO COLATERAL de alguém ter escrito nele, não prova de
      # que a regra existe no SKILL.md.
      #
      # Três formas de QUITAÇÃO, e só três:
      #   a) começa com número     → promovida a regra do SKILL.md
      #   b) começa com `nao`/`não`→ deliberadamente não vira regra
      #   c) diz `mecanismo aplicado` / `virou codigo` / `classe C`
      #      → fechada por código, que é o que a regra 32 manda
      # Qualquer outra coisa — `pendente`, `[A DEFINIR]`, `?`, vazio, ou a regra
      # proposta escrita em prosa — é DÍVIDA. Prosa no campo é decisão não
      # tomada, não decisão registrada.
      QUITADO=0
      case "$REG" in
        [0-9]*) QUITADO=1 ;;
        [Nn]ao*|[Nn]ão*) QUITADO=1 ;;
      esac
      if echo "$REG" | grep -qiE 'mecanismo aplicado|virou c(o|ó)digo|classe C'; then
        # v4 (regra 32 no auditor): alegar mecanismo exige apontar código que
        # EXISTE. O demiurgo alegou "hard-fails mecânicos" que não eram código
        # e o autarca provou que cláusula degrada na mesma sessão. Para
        # incidentes novos (>= 2026-08-13), quitação por mecanismo só vale se
        # o corpo citar um path bin/|core/|tests/ existente no repo. Legado
        # anterior à data: warning, não dívida (não reabrir 87 incidentes).
        DATA_INC=$(campo "$f" data)
        TEM_PATH=0
        for P in $(grep -ohE '(bin|core|tests)/[A-Za-z0-9._/-]+' "$f" | sort -u); do
          [ -e "$REPO_ROOT/$P" ] && { TEM_PATH=1; break; }
        done
        if [ "$TEM_PATH" = "1" ]; then
          QUITADO=1
        elif [ -n "$DATA_INC" ] && [ "$(printf '%s\n' "$DATA_INC" "2026-08-13" | sort | head -1)" = "2026-08-13" ]; then
          echo "⚠️  DÍVIDA: $(campo "$f" id) alega mecanismo mas não cita path"
          echo "    bin/|core/|tests/ existente no corpo — mecanismo sem código (regra 32)."
        else
          echo "⚠️  (legado) $(campo "$f" id): quitação por mecanismo sem path verificável no corpo."
          QUITADO=1
        fi
      fi
      if [ "$REC" = "sim" ] && [ "$QUITADO" = "0" ]; then
        if [ "$REG" = "pendente" ]; then
          echo "⚠️  DÍVIDA: $(campo "$f" id) é recorrível e não virou regra."
        else
          echo "⚠️  DÍVIDA: $(campo "$f" id) é recorrível e o campo 'regra' não"
          echo "    registra decisão — é prosa ou marcador: '$REG'"
          echo "    Promova com: bin/incident.sh promote $(campo "$f" id) \"<texto>\""
        fi
        DIVIDA=1
      fi
      if [ "$REC" = "?" ]; then
        echo "⚠️  INDEFINIDO: $(campo "$f" id) não declarou se é recorrível."
        DIVIDA=1
      fi
    done
    if [ "$DIVIDA" = "1" ]; then
      echo ""
      echo "Princípio (core/feedback-protocol.md): problema que pode acontecer de novo SEMPRE vira regra."
      exit 1
    fi
    echo "✅ Sem dívida: todo incidente recorrível já é regra do framework."
    ;;

  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 3
    ;;
esac
