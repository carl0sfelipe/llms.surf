#!/bin/bash
# oracfit-publish-cut.sh — automatiza o "corte publico" dispatch/ -> oracfit/.
#
# v1 — primeira versao, feita pra evoluir. Existe porque fazer esse corte
# na mao (comparar diretorio por diretorio, decidir o que publica) e trabalho
# repetitivo que vai se repetir toda vez que dispatch/ avancar e precisar
# sincronizar com oracfit/ (o repo publico, historico git proprio, corte
# separado - ver docs/PUBLIC-CUT.md que so existe em oracfit/).
#
# O manifesto abaixo foi derivado EMPIRICAMENTE (diff de verdade entre as
# duas pastas em 2026-08-01), nao e chute. Ver v1-release-cut.md e
# docs/PUBLIC-CUT.md (oracfit/) pro racional de cada categoria.
#
# Modos:
#   report (default)  - so mostra o que mudou/falta, nao escreve nada
#   apply              - copia de verdade as categorias seguras (espelho
#                        total e espelho-com-excecao). Categorias curadas
#                        (incidents/, scripts/) NUNCA sao copiadas
#                        automaticamente - exige decisao humana arquivo a
#                        arquivo (report lista os candidatos).
#
# Pre-condicao pro apply: check-saude.sh verde em dispatch/ (mesmo criterio
# de v1-release-cut.md "Critério de publicação").
set -uo pipefail

DISPATCH_DIR="${DISPATCH_DIR:-$HOME/dispatch}"
ORACFIT_DIR="${ORACFIT_DIR:-$HOME/oracfit}"
MODE="${1:-report}"

if [ ! -d "$DISPATCH_DIR/.git" ] || [ ! -d "$ORACFIT_DIR/.git" ]; then
  echo "ERROR: DISPATCH_DIR ($DISPATCH_DIR) ou ORACFIT_DIR ($ORACFIT_DIR) nao parecem repos git" >&2
  exit 2
fi

# ---- manifesto (evoluir aqui conforme dispatch/ ganha diretorios novos) ----
MIRROR_FULL_DIRS=(adapters panel tests fluxos .github site)
# docs/ NAO entra aqui de proposito: dispatch/docs/ esta vazio mas
# oracfit/docs/ tem conteudo real (PUBLIC-CUT.md etc.), promovido a mao de
# _bmad-output/ no corte anterior. rsync --delete apagaria esses arquivos.
# docs/ fica fora do escopo automatico deste script ate isso ser resolvido
# (achado real em 2026-08-01, primeira execucao do report).

# arquivos de raiz verificados byte-a-byte identicos em 2026-08-01 (seguro
# mirror cru). NAO inclui README.md/model-registry.json - ver TRANSFORM_FILES
# abaixo. .gitignore foi promovido pra cá em 2026-08-01 depois de sincronizar
# os dois manualmente (dev estava desatualizado, nao o publico - trazido pro
# dev, ver .gitignore comentario).
MIRROR_FULL_FILES=(AGENTS.md CLAUDE.md LICENSE NOTICE QWEN.md SKILL.md docs/STATE_TEMPLATE.md docs/TELEMETRY.md VERSION ZCODE.md docs/functions.md install.sh .gitignore)

# arquivos que PARECEM mirror mas tem conteudo transformado/sensivel -
# nunca copiar cru, so reportar o motivo. Achados reais em 2026-08-01:
#   README.md            - URL do clone (dispatch.git->oracfit.git) e links
#                           (_bmad-output/planning-artifacts/ -> docs/) sao
#                           reescritos de proposito pro publico.
#   model-registry.json   - campos id_status podem conter contexto de
#                           projeto/cliente interno (ex.: nome de EPIC e
#                           projeto do cliente) que nao deve vazar pro
#                           registry publico sem redacao manual.
TRANSFORM_FILES=(README.md model-registry.json)

CORE_EXCLUDE=(modes/flash_paid.yaml modes/flash_paid_0731.yaml)
# check-fantasma.sh SAIU desta lista em 2026-08-01: achado real rodando
# check-saude.sh dentro do oracfit/ publicado pela 1a vez — falhava com
# "No such file or directory" porque o proprio check-saude.sh (publico)
# chama check-fantasma.sh, que nunca tinha sido incluido no corte desde a
# v1.0.0 original. Script e generico (sem nada de projeto/cliente, so
# grep de declare/as-any/@ts-ignore) - devia ter sido publico desde sempre.
BIN_EXCLUDE=(classify-work.py classify-work.sh)

CURATED_DIRS=(incidents scripts)

# Categorias PRIVADAS — nunca entram no corte, em nenhum modo. Declaradas
# aqui porque categoria fora do manifesto é a que vaza: specs/fornecedores/
# (~2.500 telefones de terceiros) chegou ao repo do produto exatamente por
# specs/ não ser categoria de lista nenhuma. Incidente:
# incidents/2026-08-13-oracfit-soldado-no-orbe-corte-sem-catego.md
PRIVATE_DIRS=(specs docs/handoffs docs/prompts incidents/uso lessons)

# ------------------------------------------------------------------

in_list() {
  local needle="$1"; shift
  for x in "$@"; do [ "$x" = "$needle" ] && return 0; done
  return 1
}

rsync_dir_with_exclude() {
  local name="$1"; shift
  local excludes=("$@")
  local args=(-a --delete)
  for e in "${excludes[@]}"; do
    args+=(--exclude="$e")
  done
  echo "  -> $name/"
  rsync "${args[@]}" "$DISPATCH_DIR/$name/" "$ORACFIT_DIR/$name/"
}

report_dir() {
  local name="$1"
  local diff_out
  diff_out=$(diff -rq "$DISPATCH_DIR/$name" "$ORACFIT_DIR/$name" 2>/dev/null)
  if [ -z "$diff_out" ]; then
    echo "  [$name] identico"
  else
    echo "  [$name] diferenças:"
    echo "$diff_out" | sed 's/^/    /'
  fi
}

report_curated() {
  local name="$1"
  echo "  [$name] (CURADO — nunca copiado automatico)"
  if [ "$name" = "incidents" ]; then
    echo "    lembrete (achado 2026-08-01, rodando check-saude.sh DENTRO do publico"
    echo "    pela 1a vez): incidente citado por 'regra: N' de uma regra viva NAO e"
    echo "    opcional — check-saude.sh 'invariantes da poda' falha se o arquivo nao"
    echo "    existir la. Promover TODOS os incidentes com regra viva, nao so os que"
    echo "    parecerem 'importantes o suficiente'."
  fi
  local only_dev
  only_dev=$(diff <(cd "$DISPATCH_DIR/$name" 2>/dev/null && find . -type f | sort) \
                  <(cd "$ORACFIT_DIR/$name" 2>/dev/null && find . -type f | sort) \
             | grep '^<' | sed 's/^< //')
  if [ -z "$only_dev" ]; then
    echo "    nenhum arquivo novo desde o ultimo corte"
  else
    echo "    candidatos a promover (existem no dev, ausentes no publico):"
    echo "$only_dev" | sed 's/^/      /'
  fi
}

echo "=== oracfit-publish-cut.sh [$MODE] ==="
echo "dispatch: $DISPATCH_DIR"
echo "oracfit:  $ORACFIT_DIR"
echo

if [ "$MODE" = "report" ]; then
  echo "--- espelho total ---"
  for d in "${MIRROR_FULL_DIRS[@]}"; do report_dir "$d"; done
  echo
  echo "--- arquivos de raiz (espelho total) ---"
  for f in "${MIRROR_FULL_FILES[@]}"; do
    if ! diff -q "$DISPATCH_DIR/$f" "$ORACFIT_DIR/$f" >/dev/null 2>&1; then
      echo "  [$f] diferente ou ausente no publico"
    fi
  done
  echo
  echo "--- espelho com excecao ---"
  echo "  [core] (exclui: ${CORE_EXCLUDE[*]})"
  diff -rq "$DISPATCH_DIR/core" "$ORACFIT_DIR/core" 2>/dev/null \
    | grep -vFf <(printf '%s\n' "${CORE_EXCLUDE[@]}") | sed 's/^/    /'
  echo "  [bin] (exclui: ${BIN_EXCLUDE[*]})"
  diff -rq "$DISPATCH_DIR/bin" "$ORACFIT_DIR/bin" 2>/dev/null \
    | grep -vFf <(printf '%s\n' "${BIN_EXCLUDE[@]}") | sed 's/^/    /'
  echo
  echo "--- transformados (NUNCA copiado cru — precisa edicao manual) ---"
  for f in "${TRANSFORM_FILES[@]}"; do
    if diff -q "$DISPATCH_DIR/$f" "$ORACFIT_DIR/$f" >/dev/null 2>&1; then
      echo "  [$f] identico por acaso — ainda assim revisar a mao (regra fixa, nao mirror)"
    else
      echo "  [$f] diferente — revisar a mao antes de promover"
    fi
  done
  echo
  echo "--- curado (decisao humana) ---"
  for d in "${CURATED_DIRS[@]}"; do report_curated "$d"; done
  echo
  echo "--- privado (NUNCA copiado, presenca no publico e bloqueio) ---"
  for d in "${PRIVATE_DIRS[@]}"; do
    if [ -e "$ORACFIT_DIR/$d" ]; then
      echo "  [$d] PRESENTE NO PUBLICO — remover antes de qualquer apply"
    else
      echo "  [$d] ausente no publico ok"
    fi
  done
  echo
  echo "Pra aplicar as categorias seguras (espelho total + espelho-com-excecao):"
  echo "  bin/oracfit-publish-cut.sh apply"
  exit 0
fi

if [ "$MODE" = "apply" ]; then
  # Guarda anti-regressao: em 2026-08-13 o fluxo estava INVERTIDO (dispatch/
  # congelado em 1.8.0, oracfit/ vivo em 3.5.0). Um apply com os defaults
  # teria feito rsync --delete do velho por cima do vivo. Fonte mais velha
  # que destino = corte regressivo, recusado.
  SRC_VER=$(cat "$DISPATCH_DIR/VERSION" 2>/dev/null || echo 0)
  DST_VER=$(cat "$ORACFIT_DIR/VERSION" 2>/dev/null || echo 0)
  if [ "$(printf '%s\n%s\n' "$SRC_VER" "$DST_VER" | sort -V | tail -1)" != "$SRC_VER" ]; then
    echo "ERROR: corte regressivo — fonte $DISPATCH_DIR ($SRC_VER) e mais VELHA que destino $ORACFIT_DIR ($DST_VER). Recusado." >&2
    exit 1
  fi

  echo "--- pre-condicao: check-saude.sh em dispatch/ ---"
  if ! bash "$DISPATCH_DIR/bin/check-saude.sh" >/tmp/oracfit-cut-check-saude.log 2>&1; then
    echo "ERROR: check-saude.sh nao esta verde — corte cancelado. Log: /tmp/oracfit-cut-check-saude.log" >&2
    exit 1
  fi
  echo "  ok"
  echo

  echo "--- copiando espelho total ---"
  for d in "${MIRROR_FULL_DIRS[@]}"; do
    mkdir -p "$ORACFIT_DIR/$d"
    rsync -a --delete "$DISPATCH_DIR/$d/" "$ORACFIT_DIR/$d/"
    echo "  $d/ ok"
  done
  for f in "${MIRROR_FULL_FILES[@]}"; do
    mkdir -p "$(dirname "$ORACFIT_DIR/$f")"
    cp "$DISPATCH_DIR/$f" "$ORACFIT_DIR/$f"
  done
  echo "  arquivos de raiz ok"
  echo

  echo "--- copiando espelho com excecao ---"
  rsync_dir_with_exclude core "${CORE_EXCLUDE[@]}"
  rsync_dir_with_exclude bin "${BIN_EXCLUDE[@]}"
  echo

  echo "--- pos-condicao: categoria privada ausente no publico ---"
  PRIV_FAIL=0
  for d in "${PRIVATE_DIRS[@]}"; do
    if [ -e "$ORACFIT_DIR/$d" ]; then
      echo "  ERROR: $d/ existe no publico — categoria privada por politica" >&2
      PRIV_FAIL=1
    fi
  done
  [ "$PRIV_FAIL" -eq 1 ] && { echo "ERROR: corte contaminado — remova as categorias acima e rode de novo." >&2; exit 1; }
  echo "  ok"
  echo

  echo "--- pos-condicao: check-publico.sh no corte (dado pessoal / caminho de maquina) ---"
  if ! bash "$DISPATCH_DIR/bin/check-publico.sh" "$ORACFIT_DIR"; then
    echo "ERROR: corte contem dado pessoal ou caminho de maquina — NAO publique." >&2
    exit 1
  fi
  echo

  echo "--- categorias curadas (incidents/, scripts/) NAO foram tocadas ---"
  echo "--- arquivos transformados (${TRANSFORM_FILES[*]}) NAO foram tocados ---"
  echo "rode 'bin/oracfit-publish-cut.sh report' pra ver candidatos e promova a mao."
  echo
  echo "--- proximo passo (nao automatico) ---"
  echo "cd $ORACFIT_DIR && git status  # revisar antes de commitar/dar push"
  exit 0
fi

echo "Uso: oracfit-publish-cut.sh [report|apply]" >&2
exit 2
