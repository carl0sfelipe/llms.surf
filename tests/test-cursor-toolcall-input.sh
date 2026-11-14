#!/usr/bin/env bash
# tests/test-cursor-toolcall-input.sh — cursor adapter emits native `input` on
# tool_call (docs/decision-supervisor.md §6 rung B). Hermetic: temp dir, stdin
# NDJSON, no network, no cursor-agent binary.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADAPTER="$REPO_ROOT/adapters/cursor/stream-events.py"

# A parent dispatch exports these; this suite must not write into that log.
unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID ORACFIT_WORKDIR

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

W=$(mktemp -d "${TMPDIR:-/tmp}/test-cursor-toolcall-input.XXXXXX")
trap 'rm -rf "$W"' EXIT
EV="$W/events.jsonl"
IN="$W/stdin.ndjson"
OUT="$W/stdout.txt"
ERR="$W/stderr.txt"

python3 - "$IN" <<'PY'
import json
import sys

path = sys.argv[1]
long_path = "x" * 1000
feed = [
    {
        "type": "tool_call",
        "subtype": "started",
        "call_id": "c1",
        "tool_call": {"readToolCall": {"args": {"path": "/tmp/sample.txt"}}},
    },
    {
        "type": "tool_call",
        "subtype": "started",
        "call_id": "c2",
        "tool_call": {"shellToolCall": {"args": {"command": "ls -la /tmp"}}},
    },
    {
        "type": "tool_call",
        "subtype": "started",
        "call_id": "c3",
        "tool_call": {"readToolCall": {"args": {"path": long_path}}},
    },
    "this is not json {",
    {
        "type": "tool_call",
        "subtype": "started",
        "call_id": "c4",
        "tool_call": {"readToolCall": {}},
    },
]
with open(path, "w", encoding="utf-8") as fh:
    for item in feed:
        if isinstance(item, str):
            fh.write(item + "\n")
        else:
            fh.write(json.dumps(item, ensure_ascii=False) + "\n")
PY

ORACFIT_RUN_ID=r1 ORACFIT_EVENTS_FILE="$EV" python3 -u "$ADAPTER" <"$IN" >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 0 ] && ok "adapter exit 0 on mixed feed" || not "adapter exit $RC"
if [ -s "$ERR" ]; then
  not "stderr was not empty"
else
  ok "stderr empty"
fi
grep -q 'this is not json {' "$OUT" && ok "malformed line streamed to stdout" || not "malformed line dropped from stdout"

J() { python3 -c "import json,sys; ev=[json.loads(l) for l in open('$EV')]; $1"; }

J "t=[e for e in ev if e.get('type')=='tool_call']; r=t[0]; assert r['tool']=='read' and isinstance(r.get('input'), dict) and r['input'].get('path')=='/tmp/sample.txt'" 2>/dev/null \
  && ok "readToolCall: tool=read, input.path, input is object" \
  || not "readToolCall input"

J "t=[e for e in ev if e.get('type')=='tool_call']; s=t[1]; assert s['tool']=='shell' and isinstance(s.get('input'), dict) and s['input'].get('command')=='ls -la /tmp'" 2>/dev/null \
  && ok "shellToolCall: tool=shell, input.command" \
  || not "shellToolCall input"

J "t=[e for e in ev if e.get('type')=='tool_call']; p=t[2].get('input',{}).get('path',''); assert isinstance(t[2].get('input'), dict) and len(p)==300" 2>/dev/null \
  && ok "1000-char string truncated to 300" \
  || not "truncation"

J "t=[e for e in ev if e.get('type')=='tool_call']; assert 'input' not in t[3] and t[3].get('tool')=='read'" 2>/dev/null \
  && ok "tool call without args has no input" \
  || not "missing-args still carried input"

J "t=[e for e in ev if e.get('type')=='tool_call']; assert len(t)==4" 2>/dev/null \
  && ok "tool_call count matches tool calls fed in" \
  || not "tool_call count"

J "raw=open('$EV').read(); assert '\"input\": {' in raw and '\"input\": \"' not in raw" 2>/dev/null \
  && ok "input serialized as object, not dumped string" \
  || not "input dumped as string"

echo "test-cursor-toolcall-input: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
