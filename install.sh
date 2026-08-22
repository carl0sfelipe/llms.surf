#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

DRY_RUN=0
HOST=""
ALL_HOSTS=0
LIVE=0

usage() {
  cat <<'EOF'
Usage: install.sh --host <claude|opencode|cursor|hermes|zcode|all> [--live] [--dry-run] [--help]

Install Oracfit core and thin skill for the specified host.
Use --host all to install every supported host skill.
Use --live to symlink ~/.llms-surf/current → this checkout (no copy).

Oracfit — Carlos Felipe
EOF
}

for arg in "$@"; do
  if [ "$arg" = "--help" ]; then
    usage
    exit 0
  fi
done

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --live)
      LIVE=1
      shift
      ;;
    --host)
      if [ -z "${2:-}" ]; then
        echo "ERROR: --host requires an argument" >&2
        exit 2
      fi
      HOST="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$HOST" ] && [ $DRY_RUN -eq 0 ]; then
  echo "ERROR: --host is required for real install" >&2
  usage >&2
  exit 2
fi

case "$HOST" in
  claude|opencode|cursor|hermes|zcode|all|"") ;;
  *)
    echo "ERROR: unsupported host: $HOST (valid: claude, opencode, cursor, hermes, zcode, all)" >&2
    exit 2
    ;;
esac

[ "$HOST" = "all" ] && ALL_HOSTS=1

VERSION="dev"
# Canonical base is ~/.llms-surf (owner '10b', 2026-08-22). Legacy installs
# under ~/.oracfit keep working untouched — we never migrate or delete them.
BASE_DIR="$HOME/.llms-surf"
INSTALL_DIR="$BASE_DIR/$VERSION"
CURRENT_LINK="$BASE_DIR/current"
LEGACY_BASE="$HOME/.oracfit"

install_core() {
  if [ "$LIVE" = "1" ]; then
    echo "Live install: linking $CURRENT_LINK → $REPO_ROOT"
    mkdir -p "$BASE_DIR"
    rm -f "$CURRENT_LINK"
    ln -sfn "$REPO_ROOT" "$CURRENT_LINK"
    INSTALL_DIR="$REPO_ROOT"
    echo "  symlink: $CURRENT_LINK -> $REPO_ROOT"
    return 0
  fi

  echo "Installing llms.surf core to $INSTALL_DIR ..."
  if [ -e "$LEGACY_BASE/current" ] && [ ! -e "$CURRENT_LINK" ]; then
    echo "  note: legacy install found at $LEGACY_BASE (left untouched and working)"
  fi
  echo "Note: local usage telemetry may be written under <workdir>/.dispatch/usage/ (see docs/TELEMETRY.md)."
  echo "Opt-out: ORACFIT_TELEMETRY=0 or DISPATCH_USAGE_FEEDBACK=0. Remote POST only if ORACFIT_TELEMETRY_URL is set."
  mkdir -p "$INSTALL_DIR"

  for item in bin core fluxos model-registry.json adapters specs panel SKILL.md README.md VERSION; do
    src="$REPO_ROOT/$item"
    if [ ! -e "$src" ]; then
      echo "  skipping (not found): $item"
      continue
    fi
    echo "  copying $item ..."
    rm -rf "$INSTALL_DIR/$item"
    if [ -d "$src" ]; then
      cp -R "$src" "$INSTALL_DIR/$item"
    else
      cp "$src" "$INSTALL_DIR/$item"
    fi
  done

  # runners must stay executable after copy
  chmod +x "$INSTALL_DIR"/adapters/*/runner.sh "$INSTALL_DIR"/adapters/*/env.sh "$INSTALL_DIR"/adapters/*/install.sh 2>/dev/null || true
  chmod +x "$INSTALL_DIR"/bin/* 2>/dev/null || true

  rm -f "$CURRENT_LINK"
  ln -sf "$INSTALL_DIR" "$CURRENT_LINK"
  echo "  symlink: $CURRENT_LINK -> $INSTALL_DIR"
}

install_host() {
  local h="$1"
  export ORACFIT_ROOT="$INSTALL_DIR"
  export DISPATCH_ROOT="$INSTALL_DIR"
  case "$h" in
    claude)
      echo "Installing claude-code thin skill ..."
      bash "$INSTALL_DIR/adapters/claude-code/install.sh"
      ;;
    opencode)
      echo "Installing opencode thin skill ..."
      bash "$INSTALL_DIR/adapters/opencode/install.sh"
      ;;
    cursor)
      echo "Installing cursor thin skill ..."
      bash "$INSTALL_DIR/adapters/cursor/install.sh"
      ;;
    hermes)
      echo "Installing hermes WhatsApp skill ..."
      bash "$INSTALL_DIR/adapters/hermes/install.sh"
      ;;
    zcode)
      echo "Installing zcode adapter bits ..."
      bash "$INSTALL_DIR/adapters/zcode/install.sh"
      ;;
    *)
      echo "ERROR: unsupported host: $h" >&2
      exit 2
      ;;
  esac
}

if [ $DRY_RUN -eq 1 ]; then
  echo "[dry-run] Would install Oracfit core to: $INSTALL_DIR"
  echo "[dry-run] Would symlink: $CURRENT_LINK -> $INSTALL_DIR"
  echo "[dry-run] Would install thin skill for host: ${HOST:-<not specified>}"
  exit 0
fi

install_core

if [ $ALL_HOSTS -eq 1 ]; then
  for h in opencode claude cursor hermes zcode; do
    install_host "$h"
  done
else
  install_host "$HOST"
fi

# Convenience: ORACFIT_ROOT in a file Hermes/cron can source
echo "$INSTALL_DIR" > "$BASE_DIR/ORACFIT_ROOT"
# Profile snippet
PROFILE_SNIPPET="$BASE_DIR/env.sh"
cat > "$PROFILE_SNIPPET" <<EOF
# llms.surf — sourced by Hermes / shells (env names stay ORACFIT_* by design)
export ORACFIT_ROOT="\$HOME/.llms-surf/current"
export DISPATCH_ROOT="\$ORACFIT_ROOT"
export PATH="\$HOME/.local/bin:\$PATH"
EOF
echo "  wrote $PROFILE_SNIPPET"

# Single command on PATH (owner '10b': the public command is llms-surf)
mkdir -p "$HOME/.local/bin"
ln -sf "$INSTALL_DIR/bin/llms-surf" "$HOME/.local/bin/llms-surf"
echo "  command: $HOME/.local/bin/llms-surf → $INSTALL_DIR/bin/llms-surf (menu: run 'llms-surf' with no args)"

echo "Done. llms.surf installed at $INSTALL_DIR"
echo "Default: export ORACFIT_ROOT=\$HOME/.llms-surf/current"
echo "llms.surf — Carlos Felipe"
