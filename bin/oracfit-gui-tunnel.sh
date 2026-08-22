#!/usr/bin/env bash
# oracfit-gui-tunnel.sh — link público AUTENTICADO para a GUI (celular).
#
# Sobe a GUI em 127.0.0.1 com --auth-token e na frente dela um túnel
# cloudflared quick (https://<random>.trycloudflare.com, sem conta Cloudflare).
# Abra o link no celular, entre com o token, e a GUI é a mesma do desktop.
#
# Fail-closed: SEM --auth-token nem tenta — túnel sem autenticação é a GUI
# inteira (ledgers, specs, HITL, dispatch) exposta na internet (docs/gui-remote.md).
#
# Usage: oracfit-gui-tunnel.sh --auth-token SEGREDO [--target DIR] [--workdir DIR]
#                              [--port N] [--enable-dispatch] [--cloudflared PATH]
#
# A URL muda a cada vez que o túnel sobe (quick tunnel). Para URL fixa +
# login Google/e-mail (Cloudflare Access), ver docs/gui-remote.md.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOKEN="${ORACFIT_GUI_TOKEN:-}"
PORT="${ORACFIT_GUI_TUNNEL_PORT:-8799}"
TARGET=""
WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
ENABLE_DISPATCH=0
CF_BIN="cloudflared"

while [ $# -gt 0 ]; do
  case "$1" in
    --auth-token) shift; TOKEN="${1:?--auth-token requer segredo}"; shift ;;
    --target) shift; TARGET="${1:?--target requer dir}"; shift ;;
    --workdir) shift; WORKDIR="${1:?}"; shift ;;
    --port) shift; PORT="${1:?}"; shift ;;
    --enable-dispatch) ENABLE_DISPATCH=1; shift ;;
    --cloudflared) shift; CF_BIN="${1:?}"; shift ;;
    --help|-h)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TOKEN" ]; then
  echo "ERROR: --auth-token é obrigatório — túnel sem autenticação não sobe (fail-closed)." >&2
  echo "       gere um: openssl rand -hex 24" >&2
  exit 3
fi
if [ "${#TOKEN}" -lt 16 ]; then
  echo "ERROR: token curto demais (mínimo 16 caracteres)" >&2
  exit 3
fi
if ! command -v "$CF_BIN" >/dev/null 2>&1; then
  echo "ERROR: cloudflared não achado no PATH ($CF_BIN)" >&2
  echo "       Arch: pacman -S cloudflared · macOS: brew install cloudflared" >&2
  echo "       ou aponte um binário: --cloudflared /caminho/do/cloudflared" >&2
  exit 3
fi

GUI_ARGS=(--workdir "$WORKDIR" --port "$PORT" --auth-token "$TOKEN")
[ -n "$TARGET" ] && GUI_ARGS+=(--target "$TARGET")
[ "$ENABLE_DISPATCH" = "1" ] && GUI_ARGS+=(--enable-dispatch)

GUI_LOG="/tmp/oracfit-gui-tunnel-$PORT.log"
echo "subindo GUI em 127.0.0.1:$PORT (log: $GUI_LOG)..."
bash "$SCRIPT_DIR/oracfit-gui.sh" "${GUI_ARGS[@]}" > "$GUI_LOG" 2>&1 &
GUI_PID=$!

CF_PID=""
cleanup() {
  [ -n "$CF_PID" ] && kill "$CF_PID" 2>/dev/null
  [ -n "$GUI_PID" ] && kill "$GUI_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# espera a GUI aceitar conexão (login responde 200 com token ativo)
up=0
for _ in $(seq 1 50); do
  if curl -sf -o /dev/null "http://127.0.0.1:$PORT/login"; then up=1; break; fi
  sleep 0.2
done
if [ "$up" != "1" ]; then
  echo "ERROR: GUI não subiu — log:" >&2; tail -5 "$GUI_LOG" >&2
  exit 3
fi

echo ""
echo "GUI no ar. Subindo túnel (URL aparece abaixo em instantes)..."
echo "No celular: abra a URL https://…trycloudflare.com e entre com o token."
echo "Ctrl+C derruba túnel e GUI."
echo ""
# foreground: a URL do quick tunnel é impressa no stderr do cloudflared
"$CF_BIN" tunnel --url "http://127.0.0.1:$PORT" --no-autoupdate &
CF_PID=$!
wait "$CF_PID"
