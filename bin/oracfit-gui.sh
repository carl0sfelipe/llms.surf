#!/bin/bash
# oracfit-gui.sh — GUI local do oracfit: home, calibração HITL, anéis,
# TODO/backlog, dispatches, run ao vivo, incidents, registry. Servidor único
# (python3 stdlib: oracfit-todo-server.py = oracfit-panel-server.py do painel
# + /api/gui/todo, por herança). Tudo read-only, EXCETO o endpoint de score
# do HITL (POST /api/ring-score -> oracfit ring score). Com --enable-dispatch
# liga também o POST /api/dispatch (despachar da GUI/celular pelo mesmo
# `oracfit run` do terminal). Com --auth-token, TODO pedido exige login.
#
# Usage: oracfit-gui.sh [--target DIR] [--workdir DIR] [--port N] [--bind ADDR]
#                       [--auth-token SEGREDO] [--enable-dispatch]
#   --target DIR       alvo com ring/ (habilita a página de calibração HITL)
#   --workdir DIR      projeto com .dispatch/logs (default: $PWD)
#   --auth-token       token de acesso (login /login · Bearer); obrigatório
#                      se --bind fora do loopback (fail-closed); env ORACFIT_GUI_TOKEN
#   --enable-dispatch  liga o POST /api/dispatch (ver docs/gui-remote.md)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-oracfit-root.sh
source "$SCRIPT_DIR/lib-oracfit-root.sh"

WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
PORT="${ORACFIT_GUI_PORT:-8766}"
BIND="127.0.0.1"
TARGET=""
TOKEN="${ORACFIT_GUI_TOKEN:-}"
ENABLE_DISPATCH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) shift; TARGET="${1:?--target requer dir}"; shift ;;
    --workdir) shift; WORKDIR="${1:?}"; shift ;;
    --port) shift; PORT="${1:?}"; shift ;;
    --bind) shift; BIND="${1:?}"; shift ;;
    --auth-token) shift; TOKEN="${1:?--auth-token requer segredo}"; shift ;;
    --enable-dispatch) ENABLE_DISPATCH=1; shift ;;
    --help|-h)
      cat <<EOF
Usage: oracfit-gui.sh [--target DIR] [--workdir DIR] [--port N] [--bind ADDR]
                      [--auth-token SEGREDO] [--enable-dispatch]

GUI local do oracfit num servidor só (python3 stdlib):
  /home.html        agora: runs vivos, anéis abertos, disco, audit
  /hitl.html        calibração de anéis (nota real 0-10; requer --target)
  /todo.html        TODO/backlog do alvo: checklist feito/andamento/fila
  /rings.html       anéis por run do ledger central
  /dispatches.html  runs dos 3 ledgers declarados + despachar (--enable-dispatch)
  /index.html       run ao vivo (painel observe-only clássico)
  /incidents.html   incident.sh audit + incidents recentes
  /registry.html    model-registry + usage-hub
  /login            entrada quando --auth-token está ativo

Read-only por default; writes: score do HITL e (com --enable-dispatch) o
POST /api/dispatch. Acesso remoto (túnel/--bind) exige --auth-token.
Remote/celular: docs/gui-remote.md · oracfit gui-tunnel
Oracfit — Carlos Felipe
EOF
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(oracfit_resolve_root)" || exit 1
WORKDIR="$(cd "$WORKDIR" && pwd -P)"
PANEL_DIR="$ROOT/panel"
LOGS_DIR="$WORKDIR/.dispatch/logs"

if [ ! -d "$PANEL_DIR" ]; then
  echo "ERROR: panel não encontrado em $PANEL_DIR" >&2
  exit 3
fi

EXTRA=()
if [ -n "$TARGET" ]; then
  TARGET="$(cd "$TARGET" && pwd -P)"
  [ -f "$TARGET/ring/state.json" ] || {
    echo "ERROR: $TARGET/ring/state.json não existe — alvo sem 'oracfit ring init'" >&2
    exit 3
  }
  EXTRA+=(--ring-target "$TARGET")
fi

mkdir -p "$LOGS_DIR"

if [ -n "$TOKEN" ]; then
  EXTRA+=(--auth-token "$TOKEN")
fi
if [ "$ENABLE_DISPATCH" = "1" ]; then
  EXTRA+=(--enable-dispatch)
fi

echo "workdir=$WORKDIR"
[ -n "$TARGET" ] && echo "ring-target=$TARGET (calibração: http://$BIND:$PORT/hitl.html)"
[ -n "$TOKEN" ] && echo "auth: token ATIVO (login: http://$BIND:$PORT/login)"
[ "$ENABLE_DISPATCH" = "1" ] && echo "dispatch: ATIVO (formulário em /dispatches.html)"
echo "GUI: http://$BIND:$PORT/home.html"
exec python3 "$SCRIPT_DIR/oracfit-todo-server.py" \
  --panel-dir "$PANEL_DIR" \
  --logs-dir "$LOGS_DIR" \
  --oracfit-root "$ROOT" \
  --port "$PORT" \
  --bind "$BIND" \
  ${EXTRA[@]+"${EXTRA[@]}"}
