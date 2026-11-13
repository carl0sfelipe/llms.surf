#!/bin/bash
# oracfit-supervisor-ask.sh — export questions, ask System-One, turn answers
# into one order. Asks and translates. Does not decide, inject, restore, or
# pause. The policy engine writes the record; this command only runs it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKOUT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_QUESTIONS="$CHECKOUT/core/supervisor/questions.json"
DEFAULT_POLICY="$CHECKOUT/core/supervisor/policy.json"
DEFAULT_TIMEOUT=20
QUESTIONS_PY="$SCRIPT_DIR/oracfit-questions.py"
CLIENT_PY="$SCRIPT_DIR/oracfit-systemone.py"
POLICY_PY="$SCRIPT_DIR/oracfit-policy.py"
PROG="oracfit-supervisor-ask"

usage() {
  echo "usage: $PROG --endpoint <url> --state <file> --out <record> [--questions <set>] [--policy <file>] [--timeout <seconds>] [--ids <a,b,c>]" >&2
  exit 1
}

die() {
  echo "$PROG: $1" >&2
  exit 1
}

endpoint=""
state=""
out=""
questions="$DEFAULT_QUESTIONS"
policy="$DEFAULT_POLICY"
timeout="$DEFAULT_TIMEOUT"
ids=""

while [ $# -gt 0 ]; do
  case "$1" in
    --endpoint)
      [ $# -ge 2 ] || die "--endpoint needs a value"
      endpoint="$2"
      shift 2
      ;;
    --state)
      [ $# -ge 2 ] || die "--state needs a value"
      state="$2"
      shift 2
      ;;
    --out)
      [ $# -ge 2 ] || die "--out needs a value"
      out="$2"
      shift 2
      ;;
    --questions)
      [ $# -ge 2 ] || die "--questions needs a value"
      questions="$2"
      shift 2
      ;;
    --policy)
      [ $# -ge 2 ] || die "--policy needs a value"
      policy="$2"
      shift 2
      ;;
    --timeout)
      [ $# -ge 2 ] || die "--timeout needs a value"
      timeout="$2"
      shift 2
      ;;
    --ids)
      [ $# -ge 2 ] || die "--ids needs a value"
      ids="$2"
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[ -n "$endpoint" ] || die "--endpoint is required"
[ -n "$state" ] || die "--state is required"
[ -n "$out" ] || die "--out is required"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-ask.XXXXXX")" || die "cannot create temp directory"
trap 'rm -rf "$tmp"' EXIT

exported="$tmp/questions.json"
if ! python3 "$QUESTIONS_PY" export --set "$questions" >"$exported"; then
  die "failed to export questions"
fi

out_dir="$(dirname "$out")"
out_base="$(basename "$out")"
answers_out="${out_dir}/${out_base%.*}.answers.json"
mkdir -p "$out_dir" || die "cannot create output directory"

if [ -n "$ids" ]; then
  if ! python3 "$CLIENT_PY" ask \
    --endpoint "$endpoint" \
    --questions "$exported" \
    --state "$state" \
    --timeout "$timeout" \
    --ids "$ids" \
    --out "$answers_out"
  then
    die "ask failed"
  fi
else
  if ! python3 "$CLIENT_PY" ask \
    --endpoint "$endpoint" \
    --questions "$exported" \
    --state "$state" \
    --timeout "$timeout" \
    --out "$answers_out"
  then
    die "ask failed"
  fi
fi

out_existed=0
[ -f "$out" ] && out_existed=1

if ! python3 "$POLICY_PY" decide \
  --answers "$answers_out" \
  --policy "$policy" \
  --out "$out"
then
  if [ "$out_existed" -eq 0 ]; then
    rm -f "$out"
  fi
  die "decide failed"
fi

printf '%s\n' "$out"
exit 0
