#!/bin/bash
# stub runner — contract-compatible local runner for smoke/onboarding without OpenRouter.
# Uso: runner.sh <model_id> <spec_file> [--session ID] [--fork]
# Creates <workdir>/.dispatch/stub-proof so smoke oracles can pass.
# Workdir = ORACFIT_WORKDIR or cwd.

set -euo pipefail

MODEL_ID="${1:?Uso: runner.sh <model_id> <spec_file>}"
SPEC_FILE="${2:?Uso: runner.sh <model_id> <spec_file>}"
shift 2

STUB_SESSION_IN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --session) STUB_SESSION_IN="${2:-}"; shift 2 ;;
    --fork) shift ;;
    *) echo "runner.sh (stub): unknown flag: $1" >&2; exit 3 ;;
  esac
done

# HITL v1 (teste): simula a captura do session id real do opencode. Se
# recebeu --session (resume), reusa o mesmo id (prova de continuidade);
# senao inventa um novo, igual o opencode faria numa sessao nova.
if [ -n "${ORACFIT_SESSION_FILE:-}" ]; then
  if [ -n "$STUB_SESSION_IN" ]; then
    echo "$STUB_SESSION_IN" > "$ORACFIT_SESSION_FILE"
    echo "runner.sh (stub): retomando sessao $STUB_SESSION_IN (cache preservado)" >&2
  else
    echo "ses_stub_$(date +%s 2>/dev/null || echo 0)_$$" > "$ORACFIT_SESSION_FILE"
  fi
fi

[ -f "$SPEC_FILE" ] || { echo "runner.sh (stub): spec not found: $SPEC_FILE" >&2; exit 3; }

# ORACFIT_STUB_SLEEP: so pra teste do watchdog de interrupt HITL (sem
# gastar chamada real de modelo). Dorme em passos de 1s checando
# ORACFIT_INTERRUPT_FILE, igual ao watchdog real do adapters/opencode.
if [ -n "${ORACFIT_STUB_SLEEP:-}" ]; then
  i=0
  while [ "$i" -lt "$ORACFIT_STUB_SLEEP" ]; do
    if [ -n "${ORACFIT_INTERRUPT_FILE:-}" ] && [ -f "$ORACFIT_INTERRUPT_FILE" ]; then
      echo "runner.sh (stub): INTERROMPIDO pelo humano via painel — exit 5" >&2
      exit 5
    fi
    echo "runner.sh (stub): trabalhando... (${i}s/${ORACFIT_STUB_SLEEP}s)"
    sleep 1
    i=$((i + 1))
  done
fi

WD="${ORACFIT_WORKDIR:-$PWD}"
mkdir -p "$WD/.dispatch"
# Proof artifact for smoke oracle (content cites model for debug)
{
  echo "stub_ok"
  echo "model_id=$MODEL_ID"
  echo "spec=$(basename "$SPEC_FILE")"
} > "$WD/.dispatch/stub-proof"

# P5 multi-stage: also write proof into stage artifacts dir when provided.
if [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  cp "$WD/.dispatch/stub-proof" "$ORACFIT_STAGE_ARTIFACTS/stub-proof"
  {
    echo "stage_role=${ORACFIT_STAGE_ROLE:-unknown}"
  } >> "$ORACFIT_STAGE_ARTIFACTS/stub-proof"
  echo "stub runner: stage proof → $ORACFIT_STAGE_ARTIFACTS/stub-proof"
fi

# Guard de zonas protegidas (só teste): simula um modelo escrevendo num
# caminho arbitrário do workdir (tests/test-protected-paths.sh) sem gastar
# chamada real de modelo — mesmo espírito do ORACFIT_STUB_SLEEP acima.
if [ -n "${ORACFIT_STUB_WRITE:-}" ]; then
  mkdir -p "$WD/$(dirname "$ORACFIT_STUB_WRITE")"
  echo "stub write $(date +%s 2>/dev/null || echo 0)" > "$WD/$ORACFIT_STUB_WRITE"
  echo "stub runner: also wrote $WD/$ORACFIT_STUB_WRITE"
fi

# S8 pergunta do dono (só teste): simula o modelo bloqueado em fato que só o
# dono tem — escreve owner-question.md no artifacts dir do stage.
# ORACFIT_STUB_QUESTION=1        → pergunta bem-formada (pergunta + garfo >=2)
# ORACFIT_STUB_QUESTION=malformed → sem garfo (deve ser ignorada pelo runtime)
if [ -n "${ORACFIT_STUB_QUESTION:-}" ] && [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  if [ "$ORACFIT_STUB_QUESTION" = "malformed" ]; then
    printf 'pergunta sem garfo de consequencias\n' >"$ORACFIT_STAGE_ARTIFACTS/owner-question.md"
  else
    cat >"$ORACFIT_STAGE_ARTIFACTS/owner-question.md" <<'OQ'
pergunta: qual fonte de verdade o dono quer que eu use neste unlock?
se a oficial -> sigo o dataset do registry sem consultar terceiros
se a medição -> recalibro pelo ledger e sigo o número medido
OQ
  fi
  echo "stub runner: wrote owner-question.md ($ORACFIT_STUB_QUESTION)"
fi

echo "stub runner: wrote $WD/.dispatch/stub-proof"
exit 0
