#!/bin/bash
# dispatch-bg.sh — lança um dispatch IMUNE à morte do shell lançador.
#
# Incidente 2026-08-12-dispatch-de-shell-de-agente-morre-com-o-grupo: dispatch
# lançado com `nohup ... &` de um shell de agente (Cursor) morreu quando o
# harness matou o process group do lançador — nohup protege de SIGHUP, não de
# kill de grupo. O opencode (que cria pgid próprio) sobreviveu ÓRFÃO: sem
# watchdog, sem oráculo, sem run_finished.
#
# Aqui: double-fork + os.setsid() = nova SESSÃO, fora do alcance de SIGHUP e
# de kill -PID de grupo do lançador. PID do processo final fica em <log>.pid.
#
# Uso: bin/dispatch-bg.sh <log_file> <cmd> [args...]
# Ex.: bin/dispatch-bg.sh /tmp/run.log bin/dispatch-stages.sh modo spec.md task
#
# Exit codes: 0=lançado, 3=erro de uso

set -uo pipefail

LOG="${1:?Uso: dispatch-bg.sh <log_file> <cmd> [args...]}"
shift
[ $# -ge 1 ] || { echo "Uso: dispatch-bg.sh <log_file> <cmd> [args...]" >&2; exit 3; }

python3 - "$LOG" "$@" <<'PY'
import os, sys
log, cmd = sys.argv[1], sys.argv[2:]
if os.fork() > 0:
    sys.exit(0)
os.setsid()
if os.fork() > 0:
    os._exit(0)
with open(log + ".pid", "w") as f:
    f.write(str(os.getpid()) + "\n")
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o644)
os.dup2(fd, 1)
os.dup2(fd, 2)
devnull = os.open(os.devnull, os.O_RDONLY)
os.dup2(devnull, 0)
os.execvp(cmd[0], cmd)
PY

echo "dispatch-bg: lançado em sessão própria — log: $LOG  pid: $LOG.pid"
