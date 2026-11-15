#!/bin/bash
# lib-oracfit-supervisor-env.sh — turn the supervisor on from a local file.
#
# The repo pins no host, port or URL for the supervisor (D1 is the owner's).
# The owner writes them once, in a file outside the repo:
#
#   ${XDG_CONFIG_HOME:-$HOME/.config}/llms-surf/supervisor.env
#
# (or the path in ORACFIT_SUPERVISOR_ENV), with KEY=VALUE lines. Each adapter's
# env.sh calls oracfit_supervisor_load_env, so sourcing an adapter is enough.
#
# Only the ORACFIT_SUPERVISOR_* keys the runtimes read are taken; any other
# line is ignored. The file is parsed, never sourced, so it cannot run code.
# A value already in the environment wins over the file.

oracfit_supervisor_load_env() {
  local file="${ORACFIT_SUPERVISOR_ENV:-${XDG_CONFIG_HOME:-$HOME/.config}/llms-surf/supervisor.env}"
  local line key value
  [ -n "$file" ] && [ -r "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    [ "$key" != "$line" ] || continue
    case "$key" in
      ORACFIT_SUPERVISOR_ENDPOINT|ORACFIT_SUPERVISOR_TIMEOUT|ORACFIT_SUPERVISOR_POLICY) ;;
      *) continue ;;
    esac
    value="${value#\"}"; value="${value%\"}"
    value="${value#\'}"; value="${value%\'}"
    if [ -z "${!key:-}" ]; then
      export "$key=$value"
    fi
  done < "$file"
  return 0
}
