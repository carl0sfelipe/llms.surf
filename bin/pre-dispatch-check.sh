#!/bin/bash
# pre-dispatch-check.sh — Gate antes de despachar (concorrência + token plan + quota)
# Uso: bin/pre-dispatch-check.sh <provider_id>
# Exit: 0=GO, 1=WAIT, 2=SWITCH, 4=quota/token plan exausto
#
# v3.5: quota vem do hub BUILT-IN (bin/usage-hub.py — opencode.db + limites
# calibrados + observações RF-08), não mais do daemon HTTP do ~/ai-usage-hub.
# O daemon nunca entregou dado confiável (API do Go inexistente, OAuth Claude
# bloqueado, limits todos null) e exigia processo vivo em :6737. AI_USAGE_HUB_URL
# deixou de existir. Fail-open continua: sensor ausente nunca trava o gate.
#
# Env opcional: DISPATCH_SKIP_CONCURRENCY=1 (pula o gate de concorrência)

PROVIDER="${1:?Uso: pre-dispatch-check.sh <provider_id>}"

# ── Gate 0: concorrência ──────────────────────────────────────────────────────
# Incidente incidents/2026-07-24-travamento-silencioso.md: nunca dois agentes no mesmo repositório.
# Incidente 2026-07-24 (lessons/2026-07-24-dispatch-travado.md): um dispatch ficou
# 52min travado SEM criar sessão no DB enquanto outro agente rodava; voltou a
# responder em 2-6s assim que o outro ficou ocioso. O lock de bin/dispatch.sh
# (RNF-07) não enxerga agentes externos — este gate enxerga.
if [ "${DISPATCH_SKIP_CONCURRENCY:-0}" != "1" ]; then
  BUSY=""
  # Inclui a TUI (`opencode` puro, sem subcomando): uma sessão interativa aberta
  # contende pelo mesmo store e pendura o dispatch igual — observado em
  # 2026-07-24, TTY ttys001, 20min de sessão aberta travando toda chamada.
  # O padrão antigo ("opencode run") não pegava a TUI.
  for PROC in "opencode run" "^opencode$" "hermes -z" "hermes chat"; do
    PIDS=$(pgrep -f "$PROC" 2>/dev/null | grep -v "^$$\$" | tr '\n' ' ')
    [ -n "$PIDS" ] && BUSY="$BUSY $PROC(pid:${PIDS% })"
  done
  if [ -n "$BUSY" ]; then
    echo "WAIT agente-concorrente-ativo —$BUSY. Dois agentes no mesmo repo travam o dispatch (incidente incidents/2026-07-24-travamento-silencioso.md). Espere terminar ou use DISPATCH_SKIP_CONCURRENCY=1."
    exit 1
  fi
fi

# ── Gate 1: token plan local (não depende do ai-usage-hub) ────────────────────
if [ "$PROVIDER" = "qwen-token-plan" ]; then
  TP="$(cd "$(dirname "$0")/.." && pwd)/adapters/qwen-code/token-plan.sh"
  if [ -x "$TP" ]; then
    TP_OUT=$("$TP" status 2>&1)
    TP_EXIT=$?
    if [ $TP_EXIT -eq 4 ]; then
      echo "EXHAUSTED $TP_OUT"
      exit 4
    fi
  fi
fi

# ── Gate 2: quota via hub built-in (bin/usage-hub.py) ─────────────────────────
# Pergunta SOBRE o provider que queremos usar, não "qual você recomenda" — a
# resposta sobre outro provider deixava passar rate limit já observado neste
# (incidente incidents/2026-07-24-rate-limit-chega-como-timeout-nao-como-e.md).
# O hub lê opencode.db (tokens reais por providerID), core/usage-limits.json e
# .dispatch/usage/observations.jsonl (eventos RF-08). Exit do hub = contrato
# deste gate: 0=use, 1=wait, 4=exhausted.
HUB="$(cd "$(dirname "$0")" && pwd)/usage-hub.py"
if [ ! -f "$HUB" ]; then
  echo "GO usage-hub-ausente (fail-open) — esperado em $HUB"
  exit 0
fi

REC=$(python3 "$HUB" recommend --provider "$PROVIDER" 2>/dev/null)
RC=$?

case "$RC" in
  1)
    echo "WAIT ${REC#WAIT }"
    exit 1
    ;;
  4)
    echo "EXHAUSTED ${REC#EXHAUSTED }"
    exit 4
    ;;
  0)
    echo "GO ${REC#USE }"
    exit 0
    ;;
  *)
    # hub quebrado é sensor ausente, não veto — fail-open com aviso
    echo "GO usage-hub-erro-rc=$RC (fail-open) $REC"
    exit 0
    ;;
esac
