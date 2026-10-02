#!/bin/bash
# tests/test-check-english.sh — new code must be in English (AGENTS.md, "Language").
# Pattern: tests/test-verify.sh (mktemp, counters, exit 1 on failure). Uses a throwaway git repo.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$ROOT/bin/check-english.py"
TMPDIR="$(mktemp -d /tmp/oracfit-check-english.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; (cd "$R" && python3 "$CHECK" "$@") >"$TMPDIR/last.log" 2>&1; echo $?; set -e; }
g() { git -C "$R" -c user.name=t -c user.email=t@t -c commit.gpgsign=false "$@" >/dev/null; }

# english-ok-begin: this test feeds Portuguese on purpose.
R="$TMPDIR/repo"; mkdir -p "$R/bin" "$R/incidents"
g init -q -b main
printf 'saida_tok = 1  # old debt\n' >"$R/bin/old.py"
g add -A; g commit -qm base
g checkout -qb work

echo "== 1. old debt is not blamed on the branch"
printf 'def total(): return 1\n' >"$R/bin/new.py"
[ "$(rc_of --base main)" -eq 0 ] && ok "clean branch passes" || not "clean branch passes"
[ "$(rc_of --base main --all)" -eq 1 ] && grep -q "old.py:1" "$TMPDIR/last.log" && ok "--all reports old debt" \
  || not "--all reports old debt"

echo "== 2. Portuguese identifiers, comments and messages are refused"
printf 'tentativas = 3\n' >"$R/bin/snake.py"
[ "$(rc_of --base main)" -eq 1 ] && grep -q "snake.py:1: Portuguese word(s): tentativas" "$TMPDIR/last.log" \
  && ok "snake_case word" || not "snake_case word"
rm "$R/bin/snake.py"
printf 'const custoTotal = 0;\n' >"$R/bin/camel.js"
[ "$(rc_of --base main)" -eq 1 ] && grep -q "custo" "$TMPDIR/last.log" && ok "camelCase part" || not "camelCase part"
rm "$R/bin/camel.js"
printf '#!/bin/bash\necho "arquivo não encontrado"\n' >"$R/bin/tool"
[ "$(rc_of --base main)" -eq 1 ] && grep -q "tool:2: non-English letter" "$TMPDIR/last.log" \
  && ok "accented message in a script without extension" || not "accented message in a script without extension"
rm "$R/bin/tool"

echo "== 3. committed and uncommitted lines both count"
printf 'x = 1\n' >"$R/bin/c.py"; g add -A; g commit -qm c
printf 'x = 1\nresultado = 2\n' >"$R/bin/c.py"
[ "$(rc_of --base main)" -eq 1 ] && grep -q "c.py:2" "$TMPDIR/last.log" && ! grep -q "c.py:1" "$TMPDIR/last.log" \
  && ok "only the added line is flagged" || not "only the added line is flagged"
printf 'x = 1\n' >"$R/bin/c.py"

echo "== 4. escape hatches and exempt paths"
printf 'HEADINGS = ("Dados verificados",)  # english-ok: legacy spec heading\n' >"$R/bin/mark.py"
printf '# english-ok-begin: parses Portuguese input\nA = "Oráculo"\n# english-ok-end\nB = 1\n' >"$R/bin/block.py"
printf 'O dono não viu o erro.\n' >"$R/incidents/2026-10-02-x.sh"
printf 'Use the model.\n' >"$R/README.md"
[ "$(rc_of --base main)" -eq 0 ] && ok "english-ok line, block, incidents/ and prose docs pass" \
  || { not "escape hatches"; cat "$TMPDIR/last.log"; }
printf '# english-ok-begin\nA = 1\n# english-ok-end\nfalha = 1\n' >"$R/bin/block.py"
[ "$(rc_of --base main)" -eq 1 ] && grep -q "block.py:4" "$TMPDIR/last.log" && ok "a block ends at english-ok-end" \
  || not "a block ends at english-ok-end"
rm "$R/bin/block.py"

echo "== 5. English words that look Portuguese are not flagged"
printf 'ESTATE = "data"; parameter = "model"; antennas = 1  # pass the result\n' >"$R/bin/eng.py"
[ "$(rc_of --base main)" -eq 0 ] && ok "no false positive" || { not "no false positive"; cat "$TMPDIR/last.log"; }
printf '#!/bin/bash\noracfit acao add x  # existing subcommand, renamed later\n' >"$R/bin/legacy"
[ "$(rc_of --base main)" -eq 0 ] && ok "calling a legacy interface name is allowed" || { not "legacy name"; cat "$TMPDIR/last.log"; }
# english-ok-end

echo "== 6. a base that does not exist is a usage error"
[ "$(rc_of --base no-such-ref)" -eq 3 ] && ok "exit 3" || not "exit 3"

echo
echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
