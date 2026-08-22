#!/bin/bash
# oracfit-panel.sh — open observe-only fitness panel (FR-7, AD-8)
# Usage: oracfit-panel.sh [--workdir DIR] [--port N] [--bind ADDR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib-oracfit-root.sh
source "$SCRIPT_DIR/lib-oracfit-root.sh"

WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
PORT="${ORACFIT_PANEL_PORT:-8765}"
BIND="127.0.0.1"

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) shift; WORKDIR="${1:?}"; shift ;;
    --port) shift; PORT="${1:?}"; shift ;;
    --bind) shift; BIND="${1:?}"; shift ;;
    --help|-h)
      cat <<EOF
Usage: oracfit-panel.sh [--workdir DIR] [--port N] [--bind ADDR]

Serves \$ORACFIT_ROOT/panel/ and mounts <workdir>/.dispatch/logs at /logs/.
Observe-only — no model calls. Stop/rerun/switch stay in the CLI.

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
  echo "ERROR: panel not found at $PANEL_DIR (install/copy panel/ into core)" >&2
  exit 3
fi

mkdir -p "$LOGS_DIR"

echo "workdir=$WORKDIR"
echo "panel=$PANEL_DIR"
exec python3 "$SCRIPT_DIR/oracfit-panel-server.py" \
  --panel-dir "$PANEL_DIR" \
  --logs-dir "$LOGS_DIR" \
  --port "$PORT" \
  --bind "$BIND"
