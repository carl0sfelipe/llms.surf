#!/bin/bash
# dispatch.sh — Despacha task em background para modelos free (sem timeout), agnóstico de CLI
# Uso: bin/dispatch.sh <model_id> <spec_file> [task_name]
# Env obrigatória: DISPATCH_RUNNER, LOG_DIR, PID_DIR
# Env opcional: DISPATCH_RUNNER_NAME (repassado ao ledger-finalize.sh via RF-07)
#
# Interface do runner (core/runner-contract.md): $DISPATCH_RUNNER <model_id> <spec_file> [--session ID] [--fork]
# Não concatena prefixo de provider — o model_id vem pronto do model-registry.json.

set -euo pipefail

: "${DISPATCH_RUNNER:?Erro: env DISPATCH_RUNNER não definida. Aponte para adapters/<cli>/runner.sh (ver core/runner-contract.md).}"
: "${LOG_DIR:?Erro: env LOG_DIR não definida. Defina o diretório onde logs de dispatch são gravados.}"
: "${PID_DIR:?Erro: env PID_DIR não definida. Defina o diretório onde PID files são gravados.}"

MODEL="${1:?Uso: dispatch.sh <model_id> <spec_file> [task_name]}"
SPEC_FILE="${2:?Uso: dispatch.sh <model_id> <spec_file> [task_name]}"
TASK_NAME="${3:-task-$(date +%s)}"

# D-DISPATCH 1 / T20: tier:* without a mode YAML is the p1-inc-1 smell.
# dispatch.sh still runs the free path; modes go through dispatch-mode.sh.
if [[ "$MODEL" == tier:* ]]; then
  echo "hint: tier:* via modo (kernel_test, BMAD cheap/dev) → bin/dispatch-mode.sh <mode> <spec> <task>" >&2
fi

mkdir -p "$LOG_DIR" "$PID_DIR"

LOG_FILE="$LOG_DIR/dispatch-${TASK_NAME}.log"
PID_FILE="$PID_DIR/dispatch-${TASK_NAME}.pid"
META_FILE="$PID_DIR/dispatch-${TASK_NAME}.meta"
STARTED_AT=$(date +%s)

if [ ! -e "$SPEC_FILE" ]; then
  echo "❌ Erro: spec file não encontrado: $SPEC_FILE"
  exit 1
fi

BIN_DIR="$(cd "$(dirname "$0")" && pwd)"

# Regras 37/39 (fluxos/_comum/mapa-regras.md): check-spec/facts/oracle só
# cobriam o caminho do LOTE — "dispatch.sh chamado direto segue sem ele" era
# dívida declarada ("vira C quando o gate for do dispatch, não do modo").
# O gate agora é do dispatch. Workdir = $PWD porque o runner herda o cwd
# deste script — é onde o modelo trabalha e onde o oráculo tem de falhar
# pelo motivo certo ANTES de gastar token.
# Subshell: a lib religa errexit por dentro; só o rc dela interessa
# (0=ok, 1=gate reprovou, 2=oráculo quebrado, 3=uso).
PF_RC=0
# shellcheck source=lib-oracfit-preflight.sh
( source "$BIN_DIR/lib-oracfit-preflight.sh" && oracfit_preflight "$SPEC_FILE" "$PWD" ) || PF_RC=$?
if [ "$PF_RC" -ne 0 ]; then
  echo "❌ preflight reprovou (rc=$PF_RC) — nenhum modelo chamado, nenhum token gasto." >&2
  exit "$PF_RC"
fi

# RNF-07: recusa 2 dispatches simultâneos no mesmo .git
GIT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
LOCK_HASH=$(printf '%s' "$GIT_ROOT" | shasum -a 1 2>/dev/null | cut -d' ' -f1 || printf '%s' "$GIT_ROOT" | md5sum | cut -d' ' -f1)
LOCK_FILE="$PID_DIR/dispatch-repo-${LOCK_HASH}.lock"

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "❌ Erro: já existe um dispatch em andamento neste repositório (PID: $LOCK_PID). Aguarde terminar ou verifique $LOCK_FILE."
    exit 3
  fi
fi

echo "🚀 Despachando em background:"
echo "   Modelo: $MODEL"
echo "   Task: $TASK_NAME"
echo "   Log: $LOG_FILE"
echo "   PID: $PID_FILE"

cat > "$META_FILE" << METAEOF
TASK_NAME='$TASK_NAME'
SPEC_FILE='$SPEC_FILE'
MODEL='$MODEL'
STARTED_AT='$STARTED_AT'
METAEOF

# Usa a cadeia de fallback do RF-08 quando disponível: rate limit (exit 2) ou
# saldo (exit 4) passam para o próximo modelo do registry em vez de falhar.
RUNNER_ENTRY="$(cd "$(dirname "$0")" && pwd)/run-with-fallback.sh"
[ -x "$RUNNER_ENTRY" ] || RUNNER_ENTRY="$DISPATCH_RUNNER"

# E5-M6: run-with-fallback registra quem SERVIU de verdade (ref + provider)
# neste arquivo; ledger-finalize grava provider_efetivo e assertiona a
# allowlist do dono (R4) sobre ele.
DISPATCH_EFETIVO_FILE="$PID_DIR/dispatch-${TASK_NAME}.efetivo"
export DISPATCH_EFETIVO_FILE
rm -f "$DISPATCH_EFETIVO_FILE"

# EXIT_FILE é a única forma confiável de saber o exit code real do runner:
# ledger-finalize.sh roda como processo IRMÃO, não pai, do runner — não pode
# usar `wait $PID` (só o pai reaps status). O `bash -c` abaixo é filho direto
# desta shell, roda o runner, e escreve o próprio exit code no arquivo depois
# que o runner termina. Se o watchdog matar o grupo antes disso, o arquivo
# nunca aparece — ledger-finalize.sh trata "sem arquivo" como "killed", não
# como sucesso silencioso (era exatamente esse buraco: log não-vazio virava
# "ok" mesmo quando nada rodou de verdade).
EXIT_FILE="$PID_DIR/dispatch-${TASK_NAME}.exit"
rm -f "$EXIT_FILE"

set -m   # job control: runner vira líder do próprio grupo (incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md)
nohup bash -c '"$0" "$1" "$2"; echo $? > "$3"' \
  "$RUNNER_ENTRY" "$MODEL" "$SPEC_FILE" "$EXIT_FILE" > "$LOG_FILE" 2>&1 &
set +m
PID=$!
echo "$PID" > "$PID_FILE"
echo "$PID" > "$LOCK_FILE"

# ── Watchdog: mata travamento silencioso ─────────────────────────────────────
# Incidente 2026-07-24 (lessons/2026-07-24-dispatch-travado.md): dispatch ficou
# 52min vivo sem produzir 1 byte nem criar sessão. macOS não tem `timeout(1)`,
# então o teto é este watchdog.
#
#   DISPATCH_TIMEOUT       teto absoluto em segundos (default 1800 = 30min)
#   DISPATCH_SILENT_LIMIT  segundos sem NENHUM byte no log = travado (default 300)
#
# Teto generoso para free model (nunca menos de 30min) continua valendo:
# o teto é generoso; quem mata cedo é o detector de silêncio, e só quando o log
# não cresce nada — modelo lento porém vivo escreve, e não é morto.
# O detector de silêncio só é válido para runner que ESCREVE durante a execução.
# `claude -p` imprime a resposta inteira no fim: qualquer tarefa honesta acima de
# 5min seria morta como se estivesse travada. O adapter declara o comportamento em
# capabilities.env (STREAMS_OUTPUT); quem não streama fica sem detector de
# silêncio e é protegido só pelo teto absoluto, que continua valendo.
# Ausência da declaração é tratada como não-streaming — o conservador aqui é não
# matar, porque matar trabalho bom é pior que esperar o teto.
TIMEOUT="${DISPATCH_TIMEOUT:-1800}"
STREAMS=1
if [ -n "${CAPABILITIES_FILE:-}" ] && [ -f "$CAPABILITIES_FILE" ]; then
  STREAMS=$(grep -E '^STREAMS_OUTPUT=' "$CAPABILITIES_FILE" | tail -1 | cut -d= -f2 | tr -d '[:space:]')
  [ -n "$STREAMS" ] || STREAMS=0
fi
if [ "$STREAMS" = "1" ]; then
  SILENT_LIMIT="${DISPATCH_SILENT_LIMIT:-300}"
else
  # sem streaming, silêncio não distingue trabalho de travamento: desliga o
  # detector (valor maior que o teto nunca dispara) a menos que o humano peça.
  SILENT_LIMIT="${DISPATCH_SILENT_LIMIT:-$((TIMEOUT + 60))}"
  echo "   ⓘ runner não streama (STREAMS_OUTPUT=0) — detector de silêncio desligado; teto de ${TIMEOUT}s continua valendo."
fi
(
  ELAPSED=0
  LAST_SIZE=0
  SILENT=0
  while kill -0 "$PID" 2>/dev/null; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    SIZE=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$SIZE" -gt "$LAST_SIZE" ]; then
      SILENT=0
      LAST_SIZE=$SIZE
    else
      SILENT=$((SILENT + 10))
    fi
    if [ "$SILENT" -ge "$SILENT_LIMIT" ]; then
      echo "" >> "$LOG_FILE"
      echo "⏱️  WATCHDOG: ${SILENT}s sem output — dispatch considerado TRAVADO, matando PID $PID." >> "$LOG_FILE"
      echo "   Causa provável: outro agente ativo no mesmo repo (ver lessons/2026-07-24-dispatch-travado.md)." >> "$LOG_FILE"
      echo "   Cheque antes de redespachar: bin/pre-dispatch-check.sh <provider_id>" >> "$LOG_FILE"
      if [ -n "${DISPATCH_ARTEFATO:-}" ] && [ -f "$DISPATCH_ARTEFATO" ]; then
        sed -i '' -e 's/^status: .*/status: blocked/' -e "s/^bloqueio: .*/bloqueio: watchdog: silêncio de ${SILENT}s sem output/" "$DISPATCH_ARTEFATO" 2>/dev/null \
          || sed -i -e 's/^status: .*/status: blocked/' -e "s/^bloqueio: .*/bloqueio: watchdog: silêncio de ${SILENT}s sem output/" "$DISPATCH_ARTEFATO"
      fi
      kill -9 -"$PID" 2>/dev/null   # grupo inteiro (incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md): neto segura o pipe
      kill -9 "$PID" 2>/dev/null
      break
    fi
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
      echo "" >> "$LOG_FILE"
      echo "⏱️  WATCHDOG: teto de ${TIMEOUT}s atingido — matando grupo do PID $PID." >> "$LOG_FILE"
      if [ -n "${DISPATCH_ARTEFATO:-}" ] && [ -f "$DISPATCH_ARTEFATO" ]; then
        sed -i '' -e 's/^status: .*/status: blocked/' -e "s/^bloqueio: .*/bloqueio: watchdog: teto de ${TIMEOUT}s atingido/" "$DISPATCH_ARTEFATO" 2>/dev/null \
          || sed -i -e 's/^status: .*/status: blocked/' -e "s/^bloqueio: .*/bloqueio: watchdog: teto de ${TIMEOUT}s atingido/" "$DISPATCH_ARTEFATO"
      fi
      kill -9 -"$PID" 2>/dev/null   # grupo inteiro (incidente incidents/2026-07-24-timeout-matava-so-o-filho-neto-sobrevivi.md)
      kill -9 "$PID" 2>/dev/null
      break
    fi
  done
) > /dev/null 2>&1 &

LEDGER_FINALIZE="$BIN_DIR/ledger-finalize.sh"
if [ -f "$LEDGER_FINALIZE" ]; then
  DISPATCH_LOCK_FILE="$LOCK_FILE" LOG_DIR="$LOG_DIR" PID_DIR="$PID_DIR" \
    nohup bash "$LEDGER_FINALIZE" "$TASK_NAME" > /dev/null 2>&1 &
else
  # Sem finalizador — remove o lock quando o processo terminar
  ( while kill -0 "$PID" 2>/dev/null; do sleep 3; done; rm -f "$LOCK_FILE" ) &
fi

echo "✅ Despachado (PID: $PID)"
echo ""
echo "Para verificar: bin/poll-status.sh $TASK_NAME"
echo "Para ver log:   tail -f $LOG_FILE"
