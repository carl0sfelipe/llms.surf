#!/bin/bash
# lib-oracfit-prompt-template.sh — the prompt a stage declares, kept by the runtime.
#
# `prompt_template: NAME` used to be a promise nobody kept: the loader accepted
# the field, four shipped stages declared it, and neither dispatcher read the
# file. A stage that named a prompt received the same spec as a stage that
# named nothing.
#
# What lives here:
#   oracfit_prompt_template_resolve <name>
#     prints the path of the file and returns 0; returns 1 when the file
#     does not exist. Resolution:
#       - a value that already ends in `.md` or contains `/` is a path
#         relative to $ORACFIT_WORKDIR
#       - otherwise the first existing file of:
#           $ORACFIT_WORKDIR/core/prompts/<name>.md
#           $ORACFIT_ROOT/core/prompts/<name>.md
#   oracfit_prompt_template_emit <name> <path>
#     writes the `## Stage prompt (prompt_template: <name>)` section, with
#     the file's content, to stdout. Call it after the base spec and before
#     prev_stage / ground truth / the human message.
#
# A declared template that is not found is a broken promise: the stage fails
# with `PROMPT TEMPLATE NOT FOUND: <name>` (same doctrine as `artifacts:`).

# Resolve the file a stage named. Prints the path on success.
oracfit_prompt_template_resolve() {
  local name="${1:-}"
  local workdir="${ORACFIT_WORKDIR:-.}"
  local root="${ORACFIT_ROOT:-}"
  local candidate=""

  if [ -z "$name" ]; then
    return 1
  fi

  case "$name" in
    *.md|*/*)
      candidate="${workdir%/}/${name}"
      if [ -f "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      return 1
      ;;
  esac

  candidate="${workdir%/}/core/prompts/${name}.md"
  if [ -f "$candidate" ]; then
    printf '%s\n' "$candidate"
    return 0
  fi
  if [ -n "$root" ]; then
    candidate="${root%/}/core/prompts/${name}.md"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi
  return 1
}

# Write the stage-prompt section to stdout.
oracfit_prompt_template_emit() {
  local name="${1:-}"
  local path="${2:-}"
  echo ""
  echo "## Stage prompt (prompt_template: ${name})"
  echo ""
  cat "$path"
}
