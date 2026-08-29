#!/bin/bash
# check-docs.sh — números copiados à mão nos READMEs têm que derivar da árvore.
#
# Existe porque o apodrecimento foi medido: README.md dizia 91 incidentes /
# 23 suítes quando a árvore tinha 104 / 26, e docs/README.Detailed.md +
# docs/README.pt-BR.md diziam v3.0.0 / 56 — uma geração inteira atrás.
# Número de README copiado à mão apodrece em silêncio; a única defesa da casa
# é mecânica (regra 16: problema que pode se repetir vira mecanismo).
#
# O gate NÃO julga prosa — só afirmações enumeráveis da árvore:
#   VERSION                      → badge version-X.Y.Z nos 3 READMEs
#   incidents/*.md (contagem)    → badge de incidentes + menções em prosa
#   tests/test-*.sh (contagem)   → "N test suites" no README.md
#   core/modes/*.yaml (contagem) → "N modes" no README.md
#   model-registry.json models   → "N models in the registry" no README.md
# Se o texto muda e o padrão some, o gate FALHA avisando — não adivinha.
#
# Uso: bin/check-docs.sh [raiz]   (default: raiz do repo, útil ao checkout)
# Exit: 0=todos os números batem, 1=drift ou padrão desaparecido

set -uo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO_ROOT" || exit 1

FALHAS=0

# ── fatos derivados da árvore ──────────────────────────────────────────
VERSAO="$(cat VERSION 2>/dev/null || echo "?")"
# Exclui o índice incidents/README.md da contagem — é sumário, não postmortem
# (mesma definição do tests/test-site-honesty.sh; o ls cru contava o índice e
# fabricava um off-by-one contra toda a copy que diz 106).
INCIDENTES="$(find incidents -maxdepth 1 -name '*.md' ! -name README.md 2>/dev/null | wc -l | tr -d ' ')"
SUITES="$(ls tests/test-*.sh 2>/dev/null | wc -l | tr -d ' ')"
MODOS="$(ls core/modes/*.yaml 2>/dev/null | wc -l | tr -d ' ')"
MODELOS="$(python3 -c "import json;print(len(json.load(open('model-registry.json'))['models']))" 2>/dev/null || echo '?')"

extrai() {  # extrai <arquivo> <padrão BRE> → número da 1ª ocorrência (ou vazio)
  grep -o "$2" "$1" 2>/dev/null | head -1 | tr -dc '0-9.'
}

checa() {  # checa <arquivo> <rótulo> <padrão BRE> <esperado>
  local arq="$1" rotulo="$2" padrao="$3" esperado="$4" achado
  if [ ! -f "$arq" ]; then
    printf "  ❌ %s: arquivo ausente\n" "$arq"
    FALHAS=$((FALHAS + 1)); return
  fi
  achado="$(extrai "$arq" "$padrao")"
  if [ -z "$achado" ]; then
    printf "  ❌ %s: padrão sumiu do texto — \"%s\". Copy mudou? Atualize o gate.\n" \
      "$arq" "$rotulo"
    FALHAS=$((FALHAS + 1))
  elif [ "$achado" != "$esperado" ]; then
    printf "  ❌ %s: %s diz %s, árvore tem %s\n" "$arq" "$rotulo" "$achado" "$esperado"
    FALHAS=$((FALHAS + 1))
  fi
}

checa_versao() {  # badge version-X.Y.Z-brightgreen (tem ponto, não é inteiro)
  local arq="$1" achado
  if [ ! -f "$arq" ]; then
    printf "  ❌ %s: arquivo ausente\n" "$arq"; FALHAS=$((FALHAS + 1)); return
  fi
  achado="$(grep -o 'version-[0-9.]*-brightgreen' "$arq" | head -1 | sed 's/version-//;s/-brightgreen//')"
  if [ "$achado" != "$VERSAO" ]; then
    printf "  ❌ %s: badge version diz %s, VERSION é %s\n" "$arq" "${achado:-?}" "$VERSAO"
    FALHAS=$((FALHAS + 1))
  fi
}

checa_badge_incidentes() {  # badge incidents→X-N-orange (extrai só o N: o
  # rótulo URL-encodado carrega dígitos próprios em %E2%86%92 — tr não serve)
  local arq="$1" achado
  if [ ! -f "$arq" ]; then
    printf "  ❌ %s: arquivo ausente\n" "$arq"; FALHAS=$((FALHAS + 1)); return
  fi
  achado="$(grep -o 'incidents[^-]*-[0-9]\{1,\}-orange' "$arq" 2>/dev/null | head -1 \
            | sed 's/.*-\([0-9]\{1,\}\)-orange/\1/')"
  if [ -z "$achado" ]; then
    printf "  ❌ %s: badge de incidentes sumiu do texto. Copy mudou? Atualize o gate.\n" "$arq"
    FALHAS=$((FALHAS + 1))
  elif [ "$achado" != "$INCIDENTES" ]; then
    printf "  ❌ %s: badge de incidentes diz %s, árvore tem %s\n" "$arq" "$achado" "$INCIDENTES"
    FALHAS=$((FALHAS + 1))
  fi
}

# ── README.md (frente pública EN) ──────────────────────────────────────
checa_versao README.md
checa_badge_incidentes README.md
checa README.md "postmortems (negrito)"    '\*\*[0-9]\{1,\} postmortems'        "$INCIDENTES"
checa README.md "So are N others"          'So are [0-9]\{1,\}'                  "$((INCIDENTES - 2))"
checa README.md "incident postmortems"     '[0-9]\{1,\} incident postmortems'   "$INCIDENTES"
checa README.md "the N happened"           'the [0-9]\{1,\} in this cut happened' "$INCIDENTES"
checa README.md "incidents/ na tabela"     '[0-9]\{1,\} failures that became permanent protections' "$INCIDENTES"
checa README.md "test suites"              '[0-9]\{1,\} test suites'            "$SUITES"
checa README.md "models in the registry"   '[0-9]\{1,\} models in the registry' "$MODELOS"
checa README.md "modes"                    '[0-9]\{1,\} modes'                  "$MODOS"

# ── contexto: corte vs oficina ─────────────────────────────────────────
# O corte público shippa só README.md; a oficina tem os três. Se falta
# Detailed/pt-BR mas também falta docs/handoffs/ (privado), estamos num
# corte — os dois são pulados com aviso. Na oficina, falta = erro.
if [ ! -f docs/README.Detailed.md ] && [ ! -d docs/handoffs ]; then
  echo "  ⓘ corte público: docs/README.Detailed.md e README.pt-BR fora da superfície — pulados"
elif [ ! -f docs/README.Detailed.md ] || [ ! -f docs/README.pt-BR.md ]; then
  echo "  ❌ oficina sem os 3 READMEs (Detailed/pt-BR) — superfície incompleta"
  FALHAS=$((FALHAS + 1))
fi

# ── docs/README.Detailed.md (EN, história completa) ────────────────────
if [ -f docs/README.Detailed.md ]; then
checa_versao docs/README.Detailed.md
checa_badge_incidentes docs/README.Detailed.md
checa docs/README.Detailed.md "N so far"            '[0-9]\{1,\} so far'                 "$INCIDENTES"
checa docs/README.Detailed.md "N and counting"      '[0-9]\{1,\} and counting'           "$INCIDENTES"
checa docs/README.Detailed.md "incidents/ na tabela" '[0-9]\{1,\} failures that became protections' "$INCIDENTES"

# ── docs/README.pt-BR.md (pt) ──────────────────────────────────────────
checa_versao docs/README.pt-BR.md
checa_badge_incidentes docs/README.pt-BR.md
checa docs/README.pt-BR.md "N até hoje"             '[0-9]\{1,\} até hoje'               "$INCIDENTES"
checa docs/README.pt-BR.md "incidents/ na tabela"   '[0-9]\{1,\} falhas que viraram proteção' "$INCIDENTES"
fi

if [ "$FALHAS" -eq 0 ]; then
  echo "✅ check-docs: números dos 3 READMEs derivam da árvore (v$VERSAO, $INCIDENTES incidentes, $SUITES suítes, $MODOS modos, $MODELOS modelos)"
  exit 0
fi
echo "❌ check-docs: $FALHAS número(s) de README em drift com a árvore — corrija a copy, não o gate"
exit 1
