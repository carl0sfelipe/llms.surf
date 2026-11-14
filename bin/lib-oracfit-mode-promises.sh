#!/bin/bash
# lib-oracfit-mode-promises.sh — a mode that names a missing file is refused
# here, at creation time, by calling the same two libs the runtime uses.
#
# The loader only *declares* (JSON: which stages name a prompt_template or a
# json_schema). This conference *resolves*: it sources
# lib-oracfit-prompt-template.sh and lib-oracfit-json-schema.sh and calls
# oracfit_prompt_template_resolve / oracfit_json_schema_resolve. There is no
# second copy of "where the file lives".
#
# Source me, or run:
#   lib-oracfit-mode-promises.sh check <path.yaml> [--root DIR] [--workdir DIR]
#   lib-oracfit-mode-promises.sh resolve <prompt_template|json_schema> <name> \
#       [--root DIR] [--workdir DIR]
#
# check: silent on success. A broken promise prints
#   PROMPT TEMPLATE NOT FOUND: <name>
#   JSON SCHEMA NOT FOUND: <name>
# and returns non-zero.
# resolve: prints the path the runtime lib returns (for the suite to compare).

_ORACFIT_MODE_PROMISES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib-oracfit-prompt-template.sh
. "$_ORACFIT_MODE_PROMISES_DIR/lib-oracfit-prompt-template.sh"
# shellcheck source=lib-oracfit-json-schema.sh
. "$_ORACFIT_MODE_PROMISES_DIR/lib-oracfit-json-schema.sh"

# Resolve one declared name through the runtime lib. Prints the path.
oracfit_mode_promises_resolve() {
  local kind="${1:-}"
  local name="${2:-}"
  case "$kind" in
    prompt_template)
      oracfit_prompt_template_resolve "$name"
      ;;
    json_schema)
      oracfit_json_schema_resolve "$name"
      ;;
    *)
      echo "ERROR: unknown promise type: $kind" >&2
      return 2
      ;;
  esac
}

# Read the declared list from the loader, resolve each name. $1 = yaml path.
# Optional $2 = 1 to print "type<TAB>name<TAB>path" for each resolved promise.
oracfit_mode_promises_check() {
  local yaml="${1:-}"
  local print_resolved="${2:-0}"
  local json kind name path
  if [ -z "$yaml" ]; then
    echo "Usage: oracfit_mode_promises_check <path.yaml>" >&2
    return 2
  fi
  json="$(python3 "$_ORACFIT_MODE_PROMISES_DIR/lib-oracfit-mode-loader.py" promises "$yaml")" || return $?

  # Two lines per promise (type, then name). Names in this grammar have no
  # newlines; the loader is the reader, this loop only walks what it declared.
  while IFS= read -r kind; do
    [ -n "$kind" ] || continue
    IFS= read -r name || true
    if [ -z "$name" ]; then
      echo "ERROR: declared promise is missing a name" >&2
      return 2
    fi
    if ! path="$(oracfit_mode_promises_resolve "$kind" "$name")"; then
      case "$kind" in
        prompt_template)
          echo "PROMPT TEMPLATE NOT FOUND: $name" >&2
          ;;
        json_schema)
          echo "JSON SCHEMA NOT FOUND: $name" >&2
          ;;
        *)
          echo "PROMISE NOT FOUND: $kind $name" >&2
          ;;
      esac
      return 1
    fi
    if [ "$print_resolved" = 1 ]; then
      printf '%s\t%s\t%s\n' "$kind" "$name" "$path"
    fi
  done <<EOF
$(printf '%s\n' "$json" | python3 -c '
import json, sys
data = json.load(sys.stdin)
for p in data.get("promises") or []:
    kind = p.get("type") or ""
    name = p.get("name") or ""
    if kind and name:
        sys.stdout.write(kind + "\n" + name + "\n")
')
EOF
  return 0
}

_oracfit_mode_promises_main() {
  local cmd="${1:-}"
  shift || true
  local yaml="" kind="" name="" root="" workdir=""
  local print_resolved=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --root)
        root="${2:?}"
        shift 2
        ;;
      --workdir)
        workdir="${2:?}"
        shift 2
        ;;
      --print-resolved)
        print_resolved=1
        shift
        ;;
      -*)
        echo "ERROR: unknown flag: $1" >&2
        exit 2
        ;;
      *)
        if [ "$cmd" = "resolve" ]; then
          if [ -z "$kind" ]; then
            kind="$1"
          elif [ -z "$name" ]; then
            name="$1"
          else
            echo "ERROR: unexpected argument: $1" >&2
            exit 2
          fi
        else
          if [ -z "$yaml" ]; then
            yaml="$1"
          else
            echo "ERROR: unexpected argument: $1" >&2
            exit 2
          fi
        fi
        shift
        ;;
    esac
  done

  if [ -n "$root" ]; then
    export ORACFIT_ROOT="$root"
  fi
  if [ -n "$workdir" ]; then
    export ORACFIT_WORKDIR="$workdir"
  fi
  export ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
  if [ -z "${ORACFIT_ROOT:-}" ]; then
    export ORACFIT_ROOT="$(cd "$_ORACFIT_MODE_PROMISES_DIR/.." && pwd)"
  fi

  case "$cmd" in
    check)
      if [ -z "$yaml" ]; then
        echo "Usage: lib-oracfit-mode-promises.sh check <path.yaml> [--root DIR] [--workdir DIR]" >&2
        exit 2
      fi
      oracfit_mode_promises_check "$yaml" "$print_resolved"
      ;;
    resolve)
      if [ -z "$kind" ] || [ -z "$name" ]; then
        echo "Usage: lib-oracfit-mode-promises.sh resolve <prompt_template|json_schema> <name> [--root DIR] [--workdir DIR]" >&2
        exit 2
      fi
      oracfit_mode_promises_resolve "$kind" "$name"
      ;;
    *)
      echo "Usage:" >&2
      echo "  lib-oracfit-mode-promises.sh check <path.yaml> [--root DIR] [--workdir DIR]" >&2
      echo "  lib-oracfit-mode-promises.sh resolve <prompt_template|json_schema> <name> [--root DIR] [--workdir DIR]" >&2
      exit 2
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  set -euo pipefail
  _oracfit_mode_promises_main "$@"
fi
