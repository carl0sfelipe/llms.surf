#!/usr/bin/env bash
# oracle.sh — T20 mechanical judge for one P1 spec (README rule 2)
#
# writes: none
# reads:  kernel/test-specs/reports/<ID>.md, kernel/
#
# Exit 0 iff: report exists; first ## Verdict is PASS|FAIL|BLOCKED;
# ## Promoted is non-empty or Verdict is PASS; cargo test --release exits 0.

set -uo pipefail
ID="${1:?uso: oracle.sh <ID>  (ex.: T01)}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPORT="$ROOT/kernel/test-specs/reports/${ID}.md"

if [ ! -f "$REPORT" ]; then
  echo "oracle: missing $REPORT" >&2
  exit 1
fi

verdict="$(grep -m1 '^## Verdict:' "$REPORT" || true)"
if ! printf '%s\n' "$verdict" | grep -qE '^## Verdict: (PASS|FAIL|BLOCKED)\b'; then
  echo "oracle: first Verdict line must be PASS|FAIL|BLOCKED (got: $verdict)" >&2
  exit 1
fi

if ! printf '%s\n' "$verdict" | grep -q 'PASS'; then
  if ! grep -q '^## Promoted' "$REPORT"; then
    echo "oracle: FAIL/BLOCKED requires ## Promoted" >&2
    exit 1
  fi
  # non-empty: at least one list item or path after the heading, before next ##
  promo="$(awk '/^## Promoted/{p=1;next} /^## /{p=0} p' "$REPORT" | sed '/^$/d')"
  if [ -z "$promo" ]; then
    echo "oracle: ## Promoted is empty and Verdict is not PASS" >&2
    exit 1
  fi
fi

(cd "$ROOT/kernel" && cargo test --release)
