#!/bin/bash
# plugin.sh — sourced por .opencode/ (ou pelo shell do usuário) para setar env
# do adapter opencode automaticamente. Idempotente.
#
# Uso: source adapters/opencode/plugin.sh

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

source "$PLUGIN_DIR/env.sh"

if [ ! -f "$DB_PATH" ]; then
  echo "⚠️  adapters/opencode/plugin.sh: DB não encontrado em $DB_PATH — opencode já rodou alguma vez?" >&2
fi
