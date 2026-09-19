#!/usr/bin/env bash
# check-laws.sh — presence-only gate for kernel/laws (spec T13).
#
# Implements the CI check promised by kernel/laws/P1.md, "Rule for this
# directory": every law id `L<digits>[suffix]` written in a kernel/laws/*.md
# must appear literally (case-sensitive) in kernel/dispatch-policy/tests/
# or kernel/vectors/, and every kernel/laws/*.md must carry a `## Decisions`
# heading so design divergences get recorded where the laws live.
#
# Presence-only by design: content honesty stays human. A mechanism that is
# tagged but does not bite is T06's problem, not this script's.
#
# Exit 0 = green. Exit 1 = red, with one FAIL line per violation.
set -u

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LAWS_DIR="$ROOT/kernel/laws"
SEARCH_DIRS=("$ROOT/kernel/dispatch-policy/tests" "$ROOT/kernel/vectors")

if [ ! -d "$LAWS_DIR" ]; then
  echo "FAIL: no laws directory at $LAWS_DIR" >&2
  exit 1
fi

shopt -s nullglob
law_files=("$LAWS_DIR"/*.md)
if [ "${#law_files[@]}" -eq 0 ]; then
  echo "FAIL: no kernel/laws/*.md found" >&2
  exit 1
fi

fail=0

for f in "${law_files[@]}"; do
  # Gate: Decisions heading (design divergences must be recorded, not spoken).
  if ! grep -q '^## Decisions' "$f"; then
    echo "FAIL: $(basename "$f") has no '## Decisions' heading"
    fail=1
  fi

  # Gate: presence-only law ids (literal, case-sensitive, like the
  # AGENTS.md grep in bestmodel S25c).
  ids="$(grep -hoE '\bL[0-9]+[a-z]?\b' "$f" | sort -u)"
  for id in $ids; do
    found=0
    for d in "${SEARCH_DIRS[@]}"; do
      if [ -d "$d" ] && grep -rqF -- "$id" "$d"; then
        found=1
        break
      fi
    done
    if [ "$found" -ne 1 ]; then
      echo "FAIL: law id $id ($(basename "$f")) appears in neither kernel/dispatch-policy/tests/ nor kernel/vectors/"
      fail=1
    fi
  done
done

if [ "$fail" -ne 0 ]; then
  echo "check-laws: RED" >&2
  exit 1
fi
echo "check-laws: green (${#law_files[@]} file(s) scanned, ids present, Decisions headings in place)"
