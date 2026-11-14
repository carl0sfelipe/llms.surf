#!/bin/bash
# lib-oracfit-json-schema.sh — the answer shape a stage declares, kept by the runtime.
#
# `json_schema: NAME` used to be a promise nobody kept: the loader accepted
# the field, four shipped stages declared it, and neither dispatcher read the
# file. A stage that named a schema received the same spec as a stage that
# named nothing.
#
# What lives here:
#   oracfit_json_schema_resolve <name>
#     prints the path of the file and returns 0; returns 1 when the file
#     does not exist. Resolution:
#       - a value that already ends in `.json` or contains `/` is a path
#         relative to $ORACFIT_WORKDIR
#       - otherwise the first existing file of:
#           $ORACFIT_WORKDIR/core/schemas/<name>.json
#           $ORACFIT_ROOT/core/schemas/<name>.json
#   oracfit_json_schema_emit <name> <path>
#     writes the `## Stage answer schema (json_schema: <name>)` section, with
#     the file's content, to stdout. Call it after the prompt template (when
#     the stage has one) and before ground truth / gauntlet feedback / the
#     human message.
#
# A declared schema that is not found is a broken promise: the stage fails
# with `JSON SCHEMA NOT FOUND: <name>` before any model is called. The
# runtime hands the schema to the model; it does not validate the model's
# answer against it.

# Resolve the file a stage named. Prints the path on success.
oracfit_json_schema_resolve() {
  local name="${1:-}"
  local workdir="${ORACFIT_WORKDIR:-.}"
  local root="${ORACFIT_ROOT:-}"
  local candidate=""

  if [ -z "$name" ]; then
    return 1
  fi

  case "$name" in
    *.json|*/*)
      candidate="${workdir%/}/${name}"
      if [ -f "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      return 1
      ;;
  esac

  candidate="${workdir%/}/core/schemas/${name}.json"
  if [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if [ -n "$root" ]; then
    candidate="${root%/}/core/schemas/${name}.json"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  return 1
}

# Write the stage-answer-schema section to stdout.
oracfit_json_schema_emit() {
  local name="${1:-}"
  local path="${2:-}"
  echo ""
  echo "## Stage answer schema (json_schema: ${name})"
  echo ""
  cat "$path"
}
