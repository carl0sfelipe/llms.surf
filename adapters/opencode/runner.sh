#!/bin/bash
# runner.sh — implementação opencode do contrato core/runner-contract.md
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
#
# Traduz para: opencode run --model "<model_id>" "$(cat <spec_file>)" [--session ID] [--fork]
# Sintaxe verificada em adapters/opencode/DISCOVERY.md (`opencode run --help`).
#
# Exit codes (RNF-04): 0=ok, 1=erro, 2=rate-limit, 3=erro de uso, 4=quota exausta

set -uo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]}"
shift 2

SESSION_ID=""
FORK=0

while [ $# -gt 0 ]; do
  case "$1" in
    --session)
      SESSION_ID="${2:?--session requer ID}"
      shift 2
      ;;
    --fork)
      FORK=1
      shift
      ;;
    *)
      echo "runner.sh (opencode): flag desconhecida: $1" >&2
      exit 3
      ;;
  esac
done

if [ "$FORK" = "1" ] && [ -z "$SESSION_ID" ]; then
  echo "runner.sh (opencode): --fork requer --session ID (ver core/runner-contract.md)" >&2
  exit 3
fi

if [ ! -f "$SPEC_FILE" ]; then
  echo "runner.sh (opencode): spec_file não encontrado: $SPEC_FILE" >&2
  exit 1
fi

# Incidente 2026-08-12-runner-herda-cwd-do-lancador: o opencode edita arquivos
# relativos ao CWD DELE, que era o cwd do LANÇADOR — com --workdir apontando
# pra outro lugar, o modelo despachado editou o REPO ERRADO (run 36E63816
# editou bin/ do repo vivo em vez do worktree). O workdir do run é o contrato:
# cd nele antes de subir o modelo. Spec canonicalizada ANTES do cd.
SPEC_FILE="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
if [ -n "${ORACFIT_WORKDIR:-}" ]; then
  cd "$ORACFIT_WORKDIR" || { echo "runner.sh (opencode): workdir inexistente: $ORACFIT_WORKDIR" >&2; exit 3; }
fi

OPENCODE_BIN="${OPENCODE_BIN:-opencode}"

# Resolve <model_id> para a sintaxe do opencode via cli_hints do registry
# (core/runner-contract.md). Nunca concatena prefixo às cegas; id ausente do
# registry falha com exit 3 (PRD seção 11, regra 2: nunca inventar model id).
MODEL_REGISTRY="${MODEL_REGISTRY:-$(cd "$(dirname "$0")/../.." && pwd)/model-registry.json}"
RESOLVED=$(MODEL_ID="$MODEL_ID" REGISTRY="$MODEL_REGISTRY" python3 -c '
import json, os, sys
mid = os.environ["MODEL_ID"]
try:
    models = json.load(open(os.environ["REGISTRY"]))["models"]
except Exception as e:
    print("registry ilegível: %s" % e, file=sys.stderr); sys.exit(3)
for m in models:
    hint = m.get("cli_hints", {}).get("opencode")
    if mid in (m["id"], hint) and hint:   # aceita id ou hint já resolvido (idempotente)
        print(hint); sys.exit(0)
    if mid == m["id"]:
        print("modelo %s não tem cli_hint para opencode (ver model-registry.json)" % mid, file=sys.stderr); sys.exit(3)
print("modelo %s ausente do model-registry.json" % mid, file=sys.stderr); sys.exit(3)
') || exit 3

# --auto: auto-aprova permissões (read/write/bash) — sem isso, opencode em
# background pendura esperando aprovação que nunca vem (rejeita tudo).
# Verificada em 2026-08-13 contra `opencode run --help` da 1.18.16: a flag
# EXISTE e segue documentada ("auto-approve permissions that are not
# explicitly denied (dangerous!)"). O reporte do run ananke-20260813-0347 de
# que ela teria sumido não se confirmou. Se sumir numa versão futura, o yargs
# do opencode NÃO engole: flag desconhecida → help + exit 1 em <1s sem rodar
# nada (medido em 2026-08-13 com flag bogus — mesmo padrão do incidente do
# positional iniciado por `-`, ver comentário do `--` abaixo).
# NOTA: --session só funciona pra CONTINUAR sessão existente (não cria nova).
# Para evitar acúmulo de contexto (incidente A 2026-07-27), não passamos
# --session por padrão — o opencode cria sessão nova automaticamente a cada run.
# Quem quer continuar (HITL v1, resume pós-interrupt) passa --session pelo
# chamador (dispatch-mode.sh) usando o session id capturado do stderr desta
# mesma chamada (ver captura logo abaixo do watchdog).
# --print-logs --log-level INFO (era ERROR): nível ERROR não emite a linha
# "message=created id=ses_..." que expõe o session id real do opencode —
# sem isso não dá pra retomar sessão com cache preservado (custo real: cache
# hit é a maior parte do custo de token medido em 2026-08-01, ver lessons/).
ARGS=(run --auto --print-logs --log-level INFO --model "$RESOLVED")

# ── Provider NVIDIA só autentica dentro do agent-vault ───────────────────────
# A chave no ~/.opencode/opencode.json é a STRING literal `$NVIDIA_API_KEY` — o
# opencode não expande env var em config, então toda chamada direta volta 401 em
# ~3s. Dentro de `agent-vault run` a credencial é injetada e o mesmo modelo
# responde. Medido em 2026-07-27: 7 dos 11 ids marcados como "NVIDIA 401 morta"
# respondem OK por esta rota; os que ainda falham falham por 410 Gone (modelo
# aposentado), não por auth.
#
# Envolver aqui em vez de exigir que quem despacha lembre: o wrapper é o único
# lugar que sabe qual provider o modelo usa.
PREFIXO=()
if [ "${DISPATCH_NO_VAULT:-0}" != "1" ] && [ "${RESOLVED#nvidia/}" != "$RESOLVED" ]; then
  if command -v agent-vault >/dev/null 2>&1; then
    PREFIXO=(agent-vault run --vault "${AGENT_VAULT_NAME:-default}" --)
  else
    echo "runner.sh (opencode): $RESOLVED é NVIDIA e exige agent-vault, que não está no PATH — a chamada direta devolve 401." >&2
    exit 1
  fi
fi
[ -n "$SESSION_ID" ] && ARGS+=(--session "$SESSION_ID")
[ "$FORK" = "1" ] && ARGS+=(--fork)

# --format json agora e' o PADRAO (era opt-in) — achado 2026-08-01: stdout
# default (prosa) nunca mostra qual tool rodou (grep/edit/read + argumentos
# reais), so' texto narrativo. --format json expoe type=tool_use com nome +
# input real (confirmado numa chamada de teste: read filePath=VERSION). O
# tee (oracfit-thinking-tee.py) traduz de volta pra texto legivel no stdout
# (nao quebra run.log) e AINDA emite eventos tool_call estruturados pro
# painel. Desligar: DISPATCH_RUNNER_FORMAT_JSON=0.
[ "${DISPATCH_RUNNER_FORMAT_JSON:-1}" = "1" ] && ARGS+=(--format json)

# ── Detecção de erro de provider em STREAMING (incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md) ─────────────────────
# Antes: OUTPUT=$(... 2>&1) e só então grep de rate limit. Mas em rate limit o
# opencode PENDURA — o processo nunca termina, o grep nunca roda, e o teto externo
# devolvia 124. Resultado: a cadeia de fallback do RF-08 (que dispara em exit 2)
# nunca era acionada justamente no caso para o qual foi criada.
# Incidente: incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md
#
# Agora stdout e stderr ficam SEPARADOS.
# stdout vai DIRETO pro LOG do dispatch (tealias/pipe) — stream, não buffer.
# Isso resolve o watchdog (incidente C 2026-07-27): antes o runner só escrevia
# no final (cat "$OUT_F"), deixando o log sem bytes por minutos.
# stderr vai pra tempfile (inspecionada pra detectar rate limit/balance).
ERR_F=$(mktemp)
limpar() { rm -f "$ERR_F"; }
trap limpar EXIT

set -m   # filho vira líder do próprio grupo, para o kill de grupo (incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md)
# `${PREFIXO[@]+...}`: com `set -u`, o bash 3.2 do macOS trata array vazio como
# variável não definida e aborta. Sem esse idioma o runner morre em todo modelo
# que NÃO é da NVIDIA — a proteção quebraria o caminho comum.
# `--` antes do positional: spec com frontmatter YAML começa com `---`, e o
# yargs do opencode interpreta positional iniciado por `-` como flag → help +
# exit 1 silencioso (descoberto 2026-08-10 no tripcstory overnight: runner_exit=1
# em ~1s, sem stderr visível, specs do artefato-template TODAS afetadas).
${PREFIXO[@]+"${PREFIXO[@]}"} "$OPENCODE_BIN" "${ARGS[@]}" -- "$(cat "$SPEC_FILE")" 2> "$ERR_F" &
RUN_PID=$!
set +m

# O opencode também roda um modelo auxiliar (agent=title, small=true) para nomear
# a sessão. Um erro DELE não diz nada sobre o modelo pedido — sem este filtro,
# "Insufficient balance" do gpt-5.4-nano fazia toda chamada devolver exit 4.
# Só contam linhas cujo modelID casa com o modelo alvo.
MODEL_PART="${RESOLVED##*/}"
erro_do_alvo() {  # erro_do_alvo <padrão>
  grep -iE "$1" "$ERR_F" 2>/dev/null | grep -F "modelID=$MODEL_PART" | head -1
}

# Fecha o ciclo observação -> gate (incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md): grava o erro de provider no
# usage-hub BUILT-IN (v3.5, bin/usage-hub.py) para que recommend/pick e
# pre-dispatch-check.sh passem a recomendar espera para esse provider/modelo.
# Antes ia por POST ao daemon HTTP do ~/ai-usage-hub, que raramente estava de
# pé — a observação se perdia. Melhor-esforço: falha na gravação não pode
# travar nem mudar o exit code do runner (FAIL-OPEN).
reportar_hub() {  # reportar_hub <kind: rate_limit|balance> <mensagem>
  [ "${DISPATCH_NO_REPORT:-0}" = "1" ] && return 0
  local kind="$1" msg="$2"
  local repo_root
  repo_root=$(cd "$(dirname "$0")/../.." && pwd)
  python3 "$repo_root/bin/usage-hub.py" observe --kind "$kind" \
    --model-ref "$RESOLVED" --message "$msg" --source dispatch-runner \
    >/dev/null 2>&1
  return 0
}

SESSION_CAPTURED=0
DETECTADO=0
while kill -0 "$RUN_PID" 2>/dev/null; do
  if [ -n "$(erro_do_alvo 'rate limit exceeded|429|rate.?limit')" ]; then
    DETECTADO=2; break
  fi
  if [ -n "$(erro_do_alvo 'insufficient balance|quota exceeded|out of credit')" ]; then
    DETECTADO=4; break
  fi
  # HITL v1: humano pediu interrupcao pelo painel (toca este arquivo via
  # dispatch-mode.sh/oracfit_interrupt_file). Reusa o MESMO watchdog do
  # rate-limit, so mais uma condicao no loop que ja existia.
  if [ -n "${ORACFIT_INTERRUPT_FILE:-}" ] && [ -f "$ORACFIT_INTERRUPT_FILE" ]; then
    DETECTADO=5; break
  fi
  # Captura o session id real do opencode assim que aparece no stderr
  # (--log-level INFO), pra permitir retomar com --session em caso de
  # interrupt e preservar cache hit (custo real, nao so continuidade de
  # conversa — ver lessons/2026-08-01-hitl-v1-...). So escreve 1x.
  if [ "$SESSION_CAPTURED" = "0" ] && [ -n "${ORACFIT_SESSION_FILE:-}" ]; then
    SID=$(grep -om1 'id=ses_[A-Za-z0-9]*' "$ERR_F" 2>/dev/null | head -1 | sed 's/^id=//')
    if [ -n "$SID" ]; then
      echo "$SID" > "$ORACFIT_SESSION_FILE"
      SESSION_CAPTURED=1
    fi
  fi
  sleep 1
done

if [ "$DETECTADO" != "0" ]; then
  kill -9 -"$RUN_PID" 2>/dev/null   # grupo inteiro (incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md)
  kill -9 "$RUN_PID" 2>/dev/null
  # stdout já foi streamado direto pro LOG do dispatch (sem OUT_F)
  if [ "$DETECTADO" = "5" ]; then
    echo "runner.sh (opencode): INTERROMPIDO pelo humano via painel — exit 5" >&2
    exit 5
  fi
  # devolve a causa real ao chamador, em vez de silêncio + 124
  MSG_ERRO=$(erro_do_alvo 'rate limit|insufficient balance|quota exceeded|out of credit')
  echo "$MSG_ERRO" >&2
  [ "$DETECTADO" = "2" ] && { echo "runner.sh (opencode): RATE LIMIT — exit 2 (fallback do RF-08 deve assumir)" >&2; reportar_hub "rate_limit" "$MSG_ERRO"; }
  [ "$DETECTADO" = "4" ] && { echo "runner.sh (opencode): SALDO/QUOTA esgotado — exit 4" >&2; reportar_hub "balance" "$MSG_ERRO"; }
  exit "$DETECTADO"
fi

wait "$RUN_PID"
EXIT_CODE=$?

# rede de seguranca: processo pode ter terminado rapido demais pro
# watchdog nunca ter rodado o corpo do loop (kill -0 ja falso na 1a
# checagem) — tenta capturar o session id uma ultima vez aqui.
if [ "$SESSION_CAPTURED" = "0" ] && [ -n "${ORACFIT_SESSION_FILE:-}" ]; then
  SID=$(grep -om1 'id=ses_[A-Za-z0-9]*' "$ERR_F" 2>/dev/null | head -1 | sed 's/^id=//')
  [ -n "$SID" ] && echo "$SID" > "$ORACFIT_SESSION_FILE"
fi

# stdout já foi streamado direto pro LOG do dispatch (sem OUT_F)

# Erro pode ter aparecido no fim, sem pendurar — checa uma última vez.
MSG_ERRO=$(erro_do_alvo 'rate limit exceeded|429|rate.?limit')
if [ -n "$MSG_ERRO" ]; then
  echo "$MSG_ERRO" >&2
  reportar_hub "rate_limit" "$MSG_ERRO"
  exit 2
fi
MSG_ERRO=$(erro_do_alvo 'insufficient balance|quota exceeded|out of credit')
if [ -n "$MSG_ERRO" ]; then
  echo "$MSG_ERRO" >&2
  reportar_hub "balance" "$MSG_ERRO"
  exit 4
fi

# Erro só do modelo auxiliar (agent=title): avisa, mas não define o exit code.
if grep -qiE 'insufficient balance' "$ERR_F" 2>/dev/null; then
  echo "runner.sh (opencode): aviso — modelo auxiliar sem saldo (não afeta o modelo pedido)." >&2
fi

[ $EXIT_CODE -ne 0 ] && exit 1
exit 0
