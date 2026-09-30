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
# Incidente 2026-09-29 (gui-tunnel herda config e derruba a GUI junto):
#   1. O cloudflared herdava ~/.cloudflared/config.yml de outro túnel nomeado
#      da máquina; o ingress de lá terminava em 404 pra todo pedido. Fix:
#      cada subida usa --config apontando pra um YAML vazio recém-criado —
#      nunca o default do usuário, nunca um túnel nomeado.
#   2. GUI e túnel tinham ciclo de vida amarrado (um `wait "$CF_PID"` só);
#      matar o cloudflared por fora (ex.: pra corrigir OUTRO túnel na
#      máquina) derrubava a GUI atrás. Fix: supervisor que checa os dois
#      PIDs; se um cair sozinho, avisa e sobe ele de novo — o outro continua.
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
      sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
CF_LOG="/tmp/oracfit-gui-tunnel-cf-$PORT.log"
: > "$GUI_LOG"
: > "$CF_LOG"

# config isolado por subida: nunca ~/.cloudflared/config.yml nem qualquer
# túnel nomeado da máquina (incidente 2026-09-29 — ingress alheio → 404).
CF_CONFIG="$(mktemp /tmp/oracfit-gui-tunnel-cf-config-XXXXXX.yml)"

GUI_PID=""
CF_PID=""
CLEANED=0

start_gui() {
  bash "$SCRIPT_DIR/oracfit-gui.sh" "${GUI_ARGS[@]}" >> "$GUI_LOG" 2>&1 &
  GUI_PID=$!
}

wait_gui_up() { # bounded: ~10s
  local up=0
  for _ in $(seq 1 50); do
    if curl -sf -m 2 -o /dev/null "http://127.0.0.1:$PORT/login"; then up=1; break; fi
    kill -0 "$GUI_PID" 2>/dev/null || break
    sleep 0.2
  done
  [ "$up" = "1" ]
}

start_tunnel() {
  # trunca antes: senão um restart acha a URL VELHA no grep (ainda no
  # arquivo) achando que já subiu, sem esperar o processo novo escrever.
  : > "$CF_LOG"
  "$CF_BIN" tunnel --config "$CF_CONFIG" --url "http://127.0.0.1:$PORT" \
    --no-autoupdate >> "$CF_LOG" 2>&1 &
  CF_PID=$!
}

tunnel_url() {
  grep -oE 'https://[A-Za-z0-9.-]+\.trycloudflare\.com' "$CF_LOG" | tail -1
}

wait_tunnel_url() { # bounded: ~10s; ecoa a URL achada (vazio se nada)
  local url=""
  for _ in $(seq 1 40); do
    url="$(tunnel_url)"
    [ -n "$url" ] && break
    kill -0 "$CF_PID" 2>/dev/null || break
    sleep 0.25
  done
  echo "$url"
}

cleanup() {
  [ "$CLEANED" = "1" ] && return
  CLEANED=1
  [ -n "$CF_PID" ] && kill "$CF_PID" 2>/dev/null
  [ -n "$GUI_PID" ] && kill "$GUI_PID" 2>/dev/null
  wait 2>/dev/null
  rm -f "$CF_CONFIG"
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "subindo GUI em 127.0.0.1:$PORT (log: $GUI_LOG)..."
start_gui
if ! wait_gui_up; then
  echo "ERROR: GUI não subiu — log:" >&2; tail -5 "$GUI_LOG" >&2
  exit 3
fi

echo "GUI no ar. Subindo túnel..."
start_tunnel
URL="$(wait_tunnel_url)"
if [ -z "$URL" ]; then
  echo "ERROR: cloudflared não imprimiu a URL do túnel — log:" >&2
  tail -20 "$CF_LOG" >&2
  exit 3
fi

# smoke test best-effort (não bloqueia): quick tunnel às vezes demora a
# propagar, então uma falha aqui é aviso, não motivo pra derrubar tudo.
smoke=0
for _ in $(seq 1 15); do
  code="$(curl -s -m 3 -o /dev/null -w '%{http_code}' "$URL/login" 2>/dev/null || echo 000)"
  [ "$code" = "200" ] && smoke=1 && break
  sleep 0.4
done

echo ""
if [ "$smoke" = "1" ]; then
  echo "Túnel OK: $URL/login → 200"
else
  echo "AVISO: $URL/login não respondeu 200 ainda (código $code)." >&2
  echo "       Pode ser só propagação do quick tunnel (alguns segundos) —" >&2
  echo "       tente recarregar. Se continuar, o cloudflared pode estar" >&2
  echo "       usando a config de outro túnel (ver docs/gui-remote.md)." >&2
fi
echo "No celular: abra $URL e entre com o token."
echo "Ctrl+C derruba túnel e GUI."
echo ""

# supervisor: ciclo de vida independente — GUI e túnel são checados cada
# um por si; se um cair sozinho (ex.: alguém mata o cloudflared errado por
# fora), o script avisa e sobe SÓ ele de novo, sem derrubar o outro.
while :; do
  sleep 1
  if ! kill -0 "$GUI_PID" 2>/dev/null; then
    echo "AVISO: a GUI caiu — subindo de novo..." >&2
    start_gui
    wait_gui_up || echo "AVISO: a GUI não voltou a responder — log: $GUI_LOG" >&2
  fi
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    echo "AVISO: o túnel caiu — subindo de novo (a URL muda)..." >&2
    start_tunnel
    NEWURL="$(wait_tunnel_url)"
    if [ -n "$NEWURL" ]; then
      echo "Nova URL: $NEWURL" >&2
    else
      echo "AVISO: o túnel não voltou a imprimir URL — log: $CF_LOG" >&2
    fi
  fi
done
