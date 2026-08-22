#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<EOF
Usage: $(basename "$0") --class CLASS

Classify a dispatch task before preflight.

Arguments:
  --class CLASS  One of: MECANICO_TRANSFORM, T0, COPY, ARCH, SCAFFOLD
  --help         Print this help and exit.

Exit status:
  0  Allowed (MECANICO_TRANSFORM) — task suitable for dispatch.
  1  Rejected (any other class) — use the shell/orchestrator directly.
EOF
}

class_arg=

while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --class)
      shift
      if [ $# -eq 0 ]; then
        echo "ERROR: --class requires a value" >&2
        exit 2
      fi
      class_arg="$1"
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ -z "$class_arg" ]; then
  echo "ERROR: --class is required" >&2
  usage >&2
  exit 2
fi

case "$class_arg" in
  MECANICO_TRANSFORM)
    echo "allowed=true class=MECANICO_TRANSFORM"
    exit 0
    ;;
  T0|COPY|ARCH|SCAFFOLD)
    echo "allowed=false class=$class_arg"
    echo "Class '$class_arg' is not supported for dispatch via the model runner." >&2
    echo "Use the shell/orchestrator directly (rule 40)." >&2
    exit 1
    ;;
  *)
    echo "ERROR: Unknown class: $class_arg" >&2
    usage >&2
    exit 2
    ;;
esac
