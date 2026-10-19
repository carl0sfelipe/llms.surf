#!/bin/bash
# test-knowledge-niches-claims.sh — check-claims.py catches uncovered numbers,
# changed sources and conflicting values, and passes a fully supported post. Offline (file:// sources).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/fluxos/knowledge-niches/bin/check-claims.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; pass() { echo "  ok   $1"; }; bad() { echo "  FAIL $1"; fail=1; }

printf '<html><body><p>Battery: Up to 240 minutes (1080p/24fps).</p><p>Weight: 190.5 g</p></body></html>' > "$T/spec.html"
SRC="file://$T/spec.html"

post() { printf -- '---\ntitle: "x"\n---\n\nThe battery lasts up to 240 minutes and it weighs 190,5 g.\n\n## Fontes\n- %s\n' "$SRC" > "$T/$1.md"; }
claim() { printf '{"id":"%s","fact":"%s","post_text":"%s","value":"%s","url":"%s","source_quote":"%s"}' "$@"; }

# 1. fully supported post passes
post good
printf '[%s,%s]' "$(claim c1 battery 'up to 240 minutes' '240' "$SRC" 'Up to 240 minutes (1080p/24fps)')" \
                 "$(claim c2 weight 'weighs 190,5 g' '190,5' "$SRC" 'Weight: 190.5 g')" > "$T/good.claims.json"
python3 "$CHECK" "$T/good.md" --cache "$T/c" >/dev/null && pass "supported post passes" || bad "supported post passes"

# 2. a number without a claim is reported
post uncovered
printf '[%s]' "$(claim c1 battery 'up to 240 minutes' '240' "$SRC" 'Up to 240 minutes (1080p/24fps)')" > "$T/uncovered.claims.json"
python3 "$CHECK" "$T/uncovered.md" --cache "$T/c" >/dev/null; [ $? -eq 1 ] && grep -q 'numbers without a claim: 1 1905' "$T/uncovered.claims-check.md" \
  && pass "uncovered number flagged" || bad "uncovered number flagged"

# 3. snippet no longer on the page -> source_changed
post changed
printf '[%s,%s]' "$(claim c1 battery 'up to 240 minutes' '240' "$SRC" 'Up to 300 minutes')" \
                 "$(claim c2 weight 'weighs 190,5 g' '190,5' "$SRC" 'Weight: 190.5 g')" > "$T/changed.claims.json"
python3 "$CHECK" "$T/changed.md" --cache "$T/c2" >/dev/null; grep -q '| c1 | source_changed |' "$T/changed.claims-check.md" \
  && pass "changed source flagged" || bad "changed source flagged"

# 4. same fact with two values -> conflict
post conflict
printf '[%s,%s,%s]' "$(claim c1 battery 'up to 240 minutes' '240' "$SRC" 'Up to 240 minutes (1080p/24fps)')" \
                    "$(claim c2 weight 'weighs 190,5 g' '190,5' "$SRC" 'Weight: 190.5 g')" \
                    "$(claim c3 battery 'up to 240 minutes' '24' "$SRC" 'Up to 240 minutes (1080p/24fps)')" > "$T/conflict.claims.json"
python3 "$CHECK" "$T/conflict.md" --cache "$T/c3" >/dev/null; grep -q 'facts with two values: battery' "$T/conflict.claims-check.md" \
  && pass "conflicting values flagged" || bad "conflicting values flagged"

# 5. missing manifest fails
post nomanifest
python3 "$CHECK" "$T/nomanifest.md" --cache "$T/c" >/dev/null; [ $? -eq 1 ] && pass "missing manifest fails" || bad "missing manifest fails"

[ $fail -eq 0 ] && echo "✅ check-claims PASS" || { echo "❌ check-claims FAIL"; exit 1; }
