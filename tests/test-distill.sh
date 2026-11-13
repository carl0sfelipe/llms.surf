#!/usr/bin/env bash
# tests/test-distill.sh — post-loop distiller: a finished run becomes a gotcha draft.
# Hermetic: every file lives under $TMPDIR. No network, no model, no writes to this checkout.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISTILL="$ROOT/bin/oracfit-distill.py"
GOTCHA="$ROOT/bin/oracfit-gotcha.py"
HEALTHY="$ROOT/tests/fixtures/gotchas/healthy.json"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/test-distill.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# A git hook or an outer dispatch may export GIT_DIR & co; the scratch repo must not inherit them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null || true)
unset DISPATCH_ROOT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
printf '[user]\n\tuseConfigOnly = true\n[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"

export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$SCRATCH/last.log" 2>&1; echo $?; set -e; }

git_t() {
  local repo="$1"
  shift
  git -C "$repo" -c user.name=test -c user.email=test@localhost -c core.hooksPath=/dev/null "$@"
}

# english-ok-begin: fake usage reports must match emit-usage-feedback.sh (heading Contexto, dirty=sim/nao).
write_report() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys
dest, workdir, git_field, task, result, exit_code = sys.argv[1:7]
text = f"""---
id: 2026-11-13-{task}-000000
titulo: uso-dispatch dispatch/{task} → {result}
data: 2026-11-13
kind: uso-dispatch
source: dispatch
status: uso-auto
task: {task}
result: {result}
---

# automatic usage: dispatch / {task} → {result}

## Contexto

| Campo | Valor |
|---|---|
| ts (UTC) | 2026-11-13T12:00:00Z |
| source | `dispatch` |
| task | `{task}` |
| result | `{result}` |
| mode | 1 |
| exit_code | {exit_code} |
| harness | `shell` |
| workdir | `{workdir}` |
| git | `{git_field}` dirty=`sim` |
| spec | `spec.md` (0 bytes, sha256=`—`) |
| oracle | `true` |
"""
open(dest, "w", encoding="utf-8").write(text)
PY
}
# english-ok-end

echo "== the diff becomes the symptom"
REPO="$SCRATCH/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q
echo "v1" >"$REPO/tracked.txt"
git_t "$REPO" add tracked.txt
git_t "$REPO" commit -q -m init
SHA="$(git -C "$REPO" rev-parse --short HEAD)"
BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
python3 - "$REPO/tracked.txt" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write("v2\n" + ("x" * 3000) + "\n")
PY
REPORT="$SCRATCH/uso-diff.md"
OUT="$SCRATCH/drafts"
mkdir -p "$OUT"
write_report "$REPORT" "$REPO" "${BRANCH}@${SHA}" "diff-symptom" "failed" "1"
git -C "$REPO" diff "$SHA" >"$SCRATCH/full.diff"
rc="$(rc_of python3 "$DISTILL" distill --incident "$REPORT" --out "$OUT")"
if [ "$rc" -eq 0 ] && [ -f "$OUT/diff-symptom.json" ]; then
  ok "distill exit 0"
else
  not "distill exit 0 (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi
if python3 - "$OUT/diff-symptom.json" "$SCRATCH/full.diff" <<'PY'
import json, sys
draft = json.load(open(sys.argv[1], encoding="utf-8"))
full = open(sys.argv[2], encoding="utf-8").read()
assert "tracked.txt" in draft["symptom"], draft["symptom"][:200]
assert len(draft["symptom"]) <= 1200, len(draft["symptom"])
assert len(full) > 1200, len(full)
assert draft["symptom"] == full[:1200], (len(draft["symptom"]), draft["symptom"][:80], full[:80])
PY
then
  ok "symptom is the truncated workdir-vs-sha diff"
else
  not "symptom is the truncated workdir-vs-sha diff"
fi

echo "== the draft keeps the trigger empty"
if python3 - "$OUT/diff-symptom.json" "$REPORT" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d["id"] == "diff-symptom"
assert d["title"] == "diff-symptom: failed (exit 1)"
assert d["source_incident"] == sys.argv[2]
assert d["prescription"] == ""
assert d["trigger"]["class"] == ""
assert d["trigger"]["clauses"] == []
assert d["status"] == "draft"
assert d["needs"] == ["prescription", "trigger", "canary.fire_fixture"]
assert d["canary"]["quiet_fixture"] == "tests/fixtures/gotchas/healthy.json"
assert d["canary"]["fire_fixture"] == "tests/fixtures/gotchas/diff-symptom.fire.json"
PY
then
  ok "trigger, prescription, status and needs"
else
  not "trigger, prescription, status and needs"
fi
rc="$(rc_of python3 "$DISTILL" list --dir "$OUT")"
if [ "$rc" -eq 0 ] && grep -q "diff-symptom  status=draft  " "$SCRATCH/last.log" \
  && grep -q "needs=prescription,trigger,canary.fire_fixture" "$SCRATCH/last.log"; then
  ok "list one line per draft"
else
  not "list one line per draft (rc=$rc log=$(cat "$SCRATCH/last.log"))"
fi

echo "== a run without a diff gets a factual symptom"
NODIFF_OUT="$SCRATCH/drafts-nodiff"
mkdir -p "$NODIFF_OUT"
NODIFF_REPORT="$SCRATCH/uso-nodiff.md"
write_report "$NODIFF_REPORT" "/no/such/workdir-distill-xyz" "main@deadbee" "no-diff-run" "blocked" "4"
rc="$(rc_of python3 "$DISTILL" distill --incident "$NODIFF_REPORT" --out "$NODIFF_OUT")"
if [ "$rc" -eq 0 ]; then
  ok "factual distill exit 0"
else
  not "factual distill exit 0 (rc=$rc log=$(cat "$SCRATCH/last.log"))"
fi
if python3 - "$NODIFF_OUT/no-diff-run.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
s = d["symptom"]
assert "blocked" in s, s
assert "exit_code=4" in s, s
assert "tracked.txt" not in s, s
assert "diff --git" not in s, s
assert "deadbee" not in s, s
assert "no-such-file-invented.py" not in s, s
PY
then
  ok "factual symptom names result and exit_code, invents no file"
else
  not "factual symptom names result and exit_code, invents no file"
fi

echo "== the distiller refuses to overwrite a draft"
OVER_OUT="$SCRATCH/drafts-over"
mkdir -p "$OVER_OUT"
OVER_REPORT="$SCRATCH/uso-over.md"
write_report "$OVER_REPORT" "$REPO" "${BRANCH}@${SHA}" "no-overwrite" "failed" "1"
rc="$(rc_of python3 "$DISTILL" distill --incident "$OVER_REPORT" --out "$OVER_OUT")"
if [ "$rc" -eq 0 ]; then
  ok "first distill of no-overwrite"
else
  not "first distill of no-overwrite (rc=$rc)"
fi
cp "$OVER_OUT/no-overwrite.json" "$SCRATCH/no-overwrite.first.json"
echo "second-pass" >>"$REPO/tracked.txt"
rc="$(rc_of python3 "$DISTILL" distill --incident "$OVER_REPORT" --out "$OVER_OUT")"
if [ "$rc" -eq 1 ] && cmp -s "$OVER_OUT/no-overwrite.json" "$SCRATCH/no-overwrite.first.json"; then
  ok "second distill refused, first draft unchanged"
else
  not "second distill refused, first draft unchanged (rc=$rc)"
fi
rc="$(rc_of python3 "$DISTILL" distill --incident "$OVER_REPORT" --out "$OVER_OUT" --force)"
if [ "$rc" -eq 0 ] && ! cmp -s "$OVER_OUT/no-overwrite.json" "$SCRATCH/no-overwrite.first.json"; then
  ok "--force rewrites the draft"
else
  not "--force rewrites the draft (rc=$rc)"
fi

echo "== the draft does not enter the bank"
TREE="$SCRATCH/tree"
mkdir -p "$TREE/core/gotchas/drafts"
BANK_REPORT="$SCRATCH/uso-bank.md"
write_report "$BANK_REPORT" "$REPO" "${BRANCH}@${SHA}" "bank-draft" "failed" "1"
rc="$(rc_of python3 "$DISTILL" distill --incident "$BANK_REPORT" --out "$TREE/core/gotchas/drafts")"
if [ "$rc" -eq 0 ] && [ -f "$TREE/core/gotchas/drafts/bank-draft.json" ]; then
  ok "draft written under core/gotchas/drafts"
else
  not "draft written under core/gotchas/drafts (rc=$rc)"
fi
set +e
(cd "$TREE" && python3 "$GOTCHA" validate >"$SCRATCH/bank.log" 2>&1)
bank_rc=$?
set -e
if [ "$bank_rc" -eq 0 ]; then
  ok "validate with no arguments ignores drafts/"
else
  not "validate with no arguments ignores drafts/ (rc=$bank_rc log=$(cat "$SCRATCH/bank.log"))"
fi

echo "== a completed draft becomes an active triad"
PROMOTE_OUT="$SCRATCH/drafts-promote"
mkdir -p "$PROMOTE_OUT"
PROMOTE_REPORT="$SCRATCH/uso-promote.md"
write_report "$PROMOTE_REPORT" "$REPO" "${BRANCH}@${SHA}" "promote-draft" "failed" "1"
rc="$(rc_of python3 "$DISTILL" distill --incident "$PROMOTE_REPORT" --out "$PROMOTE_OUT")"
if [ "$rc" -eq 0 ]; then
  ok "promote distill exit 0"
else
  not "promote distill exit 0 (rc=$rc)"
fi
FIRE="$SCRATCH/promote-draft.fire.json"
printf '%s\n' '{"oracle_exit":1,"behavior_flags":[]}' >"$FIRE"
python3 - "$PROMOTE_OUT/promote-draft.json" "$FIRE" "$HEALTHY" "$PROMOTE_REPORT" <<'PY'
import json, sys
path, fire, quiet, source = sys.argv[1:5]
d = json.load(open(path, encoding="utf-8"))
d["prescription"] = "Write the trigger by hand before promoting the draft."
d["trigger"] = {
    "class": "deterministic",
    "clauses": [{"kind": "oracle_exit", "value": 1}],
}
d["canary"] = {"fire_fixture": fire, "quiet_fixture": quiet}
d["status"] = "active"
d["source_incident"] = source
d.pop("needs", None)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(d, fh, indent=2, sort_keys=True, ensure_ascii=False)
    fh.write("\n")
PY
rc="$(rc_of python3 "$GOTCHA" validate "$PROMOTE_OUT/promote-draft.json")"
if [ "$rc" -eq 0 ]; then
  ok "completed draft validate exit 0"
else
  not "completed draft validate exit 0 (rc=$rc log=$(cat "$SCRATCH/last.log"))"
fi
BANK="$SCRATCH/promote-bank"
mkdir -p "$BANK"
cp "$PROMOTE_OUT/promote-draft.json" "$BANK/promote-draft.json"
set +e
fire_out="$(python3 "$GOTCHA" evaluate --signals "$FIRE" --bank "$BANK" 2>"$SCRATCH/eval.err")"
fire_rc=$?
quiet_out="$(python3 "$GOTCHA" evaluate --signals "$HEALTHY" --bank "$BANK" 2>>"$SCRATCH/eval.err")"
quiet_rc=$?
set -e
if [ "$fire_rc" -eq 0 ] && printf '%s\n' "$fire_out" | grep -q '"id": "promote-draft"'; then
  ok "canary fires on the fire fixture"
else
  not "canary fires on the fire fixture (rc=$fire_rc out='$fire_out')"
fi
if [ "$quiet_rc" -eq 0 ] && [ -z "$quiet_out" ]; then
  ok "canary stays quiet on healthy.json"
else
  not "canary stays quiet on healthy.json (rc=$quiet_rc out='$quiet_out')"
fi

echo "== the distiller refuses a report it cannot read"
BAD_OUT="$SCRATCH/drafts-bad"
mkdir -p "$BAD_OUT"
BAD_REPORT="$SCRATCH/uso-bad.md"
cat >"$BAD_REPORT" <<'EOF'
---
id: unreadable-report
task: unreadable-report
result: failed
---

# usage report with no context table

The table is missing on purpose.
EOF
rc="$(rc_of python3 "$DISTILL" distill --incident "$BAD_REPORT" --out "$BAD_OUT")"
if [ "$rc" -eq 1 ] && [ ! -f "$BAD_OUT/unreadable-report.json" ] \
  && [ -z "$(ls -A "$BAD_OUT")" ]; then
  ok "missing table exits 1 and writes no draft"
else
  not "missing table exits 1 and writes no draft (rc=$rc files=$(ls -A "$BAD_OUT" 2>/dev/null))"
fi

echo
echo "test-distill: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
