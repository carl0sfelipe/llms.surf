#!/usr/bin/env bash
# oracfit-daemon.sh — processo longo IMUNE à morte da sessão do agente (v4).
#
# Classe de incidente com 4+ ocorrências em 24h (2026-08-12): cadeia-fonte e
# vigia do ouroboros, servidor da demo, dispatch de shell, despertador do aion
# (morto aos 102s) — tudo que era `nohup ... &` em terminal de sessão morreu
# com o grupo. `nohup` protege de SIGHUP, não de kill de grupo do harness.
# Só double-fork + os.setsid() sobreviveu (medido no incident do ouroboros).
#
# Este wrapper dá lifecycle por cima do bin/dispatch-bg.sh (o mecanismo):
#   oracfit daemon start  <log> <cmd> [args...]   lança em sessão própria
#   oracfit daemon status <log>                   vivo/morto pelo pidfile
#   oracfit daemon stop   <log>                   TERM → KILL no pid
#
# Exit: 0=ok · 1=morto/parado (status) · 3=uso
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cmd="${1:-}"
shift || true

pid_of() { # $1=log
  [ -f "$1.pid" ] && head -1 "$1.pid" | tr -d '[:space:]' || true
}

alive() { # $1=pid
  [ -n "$1" ] && kill -0 "$1" 2>/dev/null
}

case "$cmd" in
  start)
    LOG="${1:?uso: oracfit daemon start <log> <cmd> [args...]}"
    shift
    [ $# -ge 1 ] || { echo "uso: oracfit daemon start <log> <cmd> [args...]" >&2; exit 3; }
    existing=$(pid_of "$LOG")
    if alive "$existing"; then
      echo "RECUSADO: já vivo (pid $existing, log $LOG) — idempotente, não relanço." >&2
      exit 0
    fi
    exec bash "$SCRIPT_DIR/dispatch-bg.sh" "$LOG" "$@"
    ;;
  status)
    LOG="${1:?uso: oracfit daemon status <log>}"
    pid=$(pid_of "$LOG")
    if alive "$pid"; then
      echo "VIVO: pid $pid (log $LOG)"
      exit 0
    fi
    if [ -n "$pid" ]; then
      echo "MORTO: pid $pid não existe mais (log $LOG)" >&2
    else
      echo "MORTO: sem pidfile $LOG.pid" >&2
    fi
    exit 1
    ;;
  stop)
    LOG="${1:?uso: oracfit daemon stop <log>}"
    pid=$(pid_of "$LOG")
    if ! alive "$pid"; then
      echo "já morto (${pid:-sem pidfile})"
      exit 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      alive "$pid" || { echo "parado: pid $pid (TERM)"; exit 0; }
      sleep 1
    done
    kill -KILL "$pid" 2>/dev/null || true
    echo "parado: pid $pid (KILL)"
    ;;
  *)
    sed -n '3,17p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 3
    ;;
esac
