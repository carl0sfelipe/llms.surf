#!/bin/bash
# test-context-map.sh — check-context.py flags broken pointers; purge-context.py removes dead
# context now, marks stale context, removes it after the grace period and unmarks fixed claims.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/fluxos/context-map/bin"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
fail=0; pass() { echo "  ok   $1"; }; bad() { echo "  FAIL $1"; fail=1; }

mkdir -p "$T/src" "$T/test"
printf 'export function handleOrder(order, cart) {\n  order.metadata.attribution = cart.metadata.attribution\n}\n' > "$T/src/order.js"
printf 'test("copies cart attribution", () => {})\n' > "$T/test/order.test.js"
printf 'export const legacy = 1\n' > "$T/src/legacy.js"
cat > "$T/CONTEXT.md" <<'MD'
# Orders

- Orders inherit the attribution of their cart.
  <!-- claim: path=src/order.js symbol=handleOrder quote="order.metadata.attribution = cart.metadata.attribution" test="test/order.test.js::copies cart attribution" verified=2026-10-01 -->
- The legacy flag lives in legacy.js.
  <!-- claim: path=src/legacy.js symbol=legacy -->
- We chose Postgres over SQLite for concurrent writers.
  <!-- claim: kind=decision -->
MD

python3 "$BIN/check-context.py" --root "$T" >/dev/null && pass "clean map passes" || bad "clean map passes"
python3 "$BIN/check-context.py" --root "$T" --coverage 'src/*.js' >/dev/null && pass "coverage of cited files" || bad "coverage of cited files"

# break one anchor and delete one file
sed -i 's/order.metadata.attribution = cart.metadata.attribution/order.attribution = pick(cart)/' "$T/src/order.js"
rm "$T/src/legacy.js"
out=$(python3 "$BIN/check-context.py" --root "$T"); rc=$?
[ $rc -eq 1 ] && echo "$out" | grep -q 'stale_quote' && echo "$out" | grep -q 'dead' && pass "broken pointers flagged" || bad "broken pointers flagged"

# purge day 0: dead removed, stale marked, decision untouched
python3 "$BIN/purge-context.py" --root "$T" --today 2026-10-19 --apply >/dev/null
! grep -q 'legacy' "$T/CONTEXT.md" && pass "dead claim removed" || bad "dead claim removed"
grep -q 'stale=2026-10-19' "$T/CONTEXT.md" && pass "stale claim marked" || bad "stale claim marked"
grep -q 'kind=decision' "$T/CONTEXT.md" && pass "decision kept" || bad "decision kept"
grep -q '| dead |' "$T/PURGE-LOG.md" && pass "removal logged" || bad "removal logged"

# purge inside grace: nothing removed
python3 "$BIN/purge-context.py" --root "$T" --today 2026-10-25 --apply >/dev/null
grep -q 'inherit the attribution' "$T/CONTEXT.md" && pass "kept during grace" || bad "kept during grace"

# purge after grace: stale removed
cp "$T/CONTEXT.md" "$T/CONTEXT.bak"
python3 "$BIN/purge-context.py" --root "$T" --today 2026-11-05 --apply >/dev/null
! grep -q 'inherit the attribution' "$T/CONTEXT.md" && pass "stale removed after grace" || bad "stale removed after grace"

# a rewritten claim that passes again loses the mark
mv "$T/CONTEXT.bak" "$T/CONTEXT.md"
sed -i 's/quote="order.metadata.attribution = cart.metadata.attribution"/quote="order.attribution = pick(cart)"/' "$T/CONTEXT.md"
python3 "$BIN/purge-context.py" --root "$T" --today 2026-10-26 --apply >/dev/null
grep -q 'inherit the attribution' "$T/CONTEXT.md" && ! grep -q 'stale=' "$T/CONTEXT.md" && pass "fixed claim unmarked" || bad "fixed claim unmarked"

# dry run reports work with exit 1 and does not write
sed -i 's/symbol=handleOrder/symbol=handleOrderGone/' "$T/CONTEXT.md"; before=$(md5sum < "$T/CONTEXT.md")
python3 "$BIN/purge-context.py" --root "$T" --today 2026-10-26 >/dev/null; rc=$?
[ $rc -eq 1 ] && [ "$before" = "$(md5sum < "$T/CONTEXT.md")" ] && pass "dry run does not write" || bad "dry run does not write"

[ $fail -eq 0 ] && echo "✅ context-map PASS" || { echo "❌ context-map FAIL"; exit 1; }
