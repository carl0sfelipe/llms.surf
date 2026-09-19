#!/usr/bin/env bash
# measure-home-relocation.sh — D-INC3 step 1 (measure, do not guess)
#
# writes: /tmp/zc-measure-<pid>/* (scratch only; never the owner's ~/.zcode)
# reads:  the real zcode binary on THIS machine
#
# Owner runs this on the machine that has the AppImage. The cloud agent
# does not have that binary and must not invent sim/não.
#
# stdout is exactly three lines:
#   HOME relocado: sim|não
#   XDG_CONFIG_HOME: sim|não
#   --user-data-dir: sim|não
#
# sim = unique model token appeared in output, or the stub provider URL
# was hit. não = ran the binary and saw neither. Missing binary → exit 3
# on stderr only.

set -uo pipefail

SCRATCH="${TMPDIR:-/tmp}/zc-measure-$$"
mkdir -p "$SCRATCH"
LISTENER_PIDS=""
cleanup() {
  # shellcheck disable=SC2086
  [ -n "$LISTENER_PIDS" ] && kill $LISTENER_PIDS 2>/dev/null || true
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

if [ -n "${ZCODE_BIN:-}" ] && [ -x "${ZCODE_BIN}" ]; then
  BIN="$ZCODE_BIN"
elif command -v zcode >/dev/null 2>&1; then
  BIN="$(command -v zcode)"
elif [ -x "${HOME}/.local/bin/zcode" ]; then
  BIN="${HOME}/.local/bin/zcode"
else
  echo "measure-home-relocation: zcode binary not found (set ZCODE_BIN). Do not invent the result." >&2
  exit 3
fi

write_cfg() {
  local dest="$1" token="$2" port="$3"
  mkdir -p "$(dirname "$dest")"
  cat >"$dest" <<EOF
{
  "model": { "main": "inc3measure/${token}" },
  "provider": {
    "inc3measure": {
      "kind": "openai-compatible",
      "options": {
        "baseURL": "http://127.0.0.1:${port}/v1",
        "apiKey": "measure-only"
      }
    }
  }
}
EOF
}

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

start_listener() {
  local port="$1" tag="$2"
  python3 - "$port" "$SCRATCH/hit-$tag" <<'PY' &
import pathlib, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

class H(BaseHTTPRequestHandler):
    def log_message(self, *_args):
        return
    def _hit(self):
        pathlib.Path(sys.argv[2]).write_text("hit\n")
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"{}")
    def do_GET(self):
        self._hit()
    def do_POST(self):
        self._hit()

HTTPServer(("127.0.0.1", int(sys.argv[1])), H).handle_request()
PY
  LISTENER_PIDS="$LISTENER_PIDS $!"
}

honoured() {
  local token="$1" tag="$2" log="$3"
  [ -f "$SCRATCH/hit-$tag" ] && return 0
  [ -f "$log" ] && grep -Fq "$token" "$log" && return 0
  return 1
}

run_capped() {
  local log="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout 12s "$@" >"$log" 2>&1 || true
  else
    "$@" >"$log" 2>&1 || true
  fi
}

token() { python3 -c 'import secrets;print(secrets.token_hex(4))'; }

# ── HOME ────────────────────────────────────────────────────────────────
TOKEN_HOME="home$(token)"
PORT_HOME="$(pick_port)"
HOME_DIR="$SCRATCH/reloc-home"
write_cfg "$HOME_DIR/.zcode/cli/config.json" "$TOKEN_HOME" "$PORT_HOME"
start_listener "$PORT_HOME" home
sleep 0.15
run_capped "$SCRATCH/log-home" env HOME="$HOME_DIR" "$BIN" --prompt "ping" --mode yolo --json
if honoured "$TOKEN_HOME" home "$SCRATCH/log-home"; then HOME_V=sim; else HOME_V=não; fi

# ── XDG_CONFIG_HOME ─────────────────────────────────────────────────────
TOKEN_XDG="xdg$(token)"
PORT_XDG="$(pick_port)"
XDG_DIR="$SCRATCH/xdg"
# Try the two layouts Electron/zcode might use; one token, one listener.
write_cfg "$XDG_DIR/zcode/cli/config.json" "$TOKEN_XDG" "$PORT_XDG"
write_cfg "$XDG_DIR/.zcode/cli/config.json" "$TOKEN_XDG" "$PORT_XDG"
start_listener "$PORT_XDG" xdg
sleep 0.15
# Keep HOME at a empty scratch so a HOME hit cannot masquerade as XDG.
EMPTY_HOME="$SCRATCH/empty-home"
mkdir -p "$EMPTY_HOME"
run_capped "$SCRATCH/log-xdg" env HOME="$EMPTY_HOME" XDG_CONFIG_HOME="$XDG_DIR" \
  "$BIN" --prompt "ping" --mode yolo --json
if honoured "$TOKEN_XDG" xdg "$SCRATCH/log-xdg"; then XDG_V=sim; else XDG_V=não; fi

# ── --user-data-dir ─────────────────────────────────────────────────────
TOKEN_UDD="udd$(token)"
PORT_UDD="$(pick_port)"
UDD_DIR="$SCRATCH/udd"
write_cfg "$UDD_DIR/cli/config.json" "$TOKEN_UDD" "$PORT_UDD"
write_cfg "$UDD_DIR/.zcode/cli/config.json" "$TOKEN_UDD" "$PORT_UDD"
start_listener "$PORT_UDD" udd
sleep 0.15
run_capped "$SCRATCH/log-udd" env HOME="$EMPTY_HOME" \
  "$BIN" --user-data-dir "$UDD_DIR" --prompt "ping" --mode yolo --json
if honoured "$TOKEN_UDD" udd "$SCRATCH/log-udd"; then UDD_V=sim; else UDD_V=não; fi

printf 'HOME relocado: %s\n' "$HOME_V"
printf 'XDG_CONFIG_HOME: %s\n' "$XDG_V"
printf '--user-data-dir: %s\n' "$UDD_V"
