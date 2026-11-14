#!/usr/bin/env bash
# bin/check-owner-suites.sh — verifies the owner's acceptance suites are intact,
# by HASH (the executor may move a suite file, never change it).
#
# Portable: works in any repo. The manifest lives at the repo root:
#   .owner-suites.sha256   ->   "<sha256>  <path>"
#
# Usage: bash bin/check-owner-suites.sh [repo-path]
# Exit: 0 = all suites intact; 1 = a suite changed or is missing; 2 = bad repo path.
set -uo pipefail
REPO="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$REPO" || exit 2

MANIFEST=".owner-suites.sha256"
[ -f "$MANIFEST" ] || { echo "MISSING: manifest $MANIFEST not found in $REPO" >&2; exit 1; }

declare -A INDEX
while read -r hash path; do
  [ -n "${hash:-}" ] || continue
  INDEX["$hash"]="$path"
done < <(find . -type f \
  -not -path "./node_modules/*" -not -path "./.git/*" -not -path "./dist/*" \
  -not -path "./.dispatch/*" -not -path "./_bmad-output/*" -print0 \
  | xargs -0 sha256sum 2>/dev/null)

FAILED=0
while read -r expected path; do
  [ -n "${expected:-}" ] || continue
  if [[ -n "${INDEX[$expected]:-}" ]]; then
    echo "ok: owner suite intact (${INDEX[$expected]})"
  else
    echo "MISSING: owner suite changed or missing: ${path} (sha256 ${expected})" >&2
    FAILED=1
  fi
done < "$MANIFEST"

exit "$FAILED"
