#!/usr/bin/env bash
# tests/test-cursor-ledger.sh — a cursor dispatch closes the ledger without a
# session database, filling session_id and tokens from the run log.
#
# Hermetic: LOG_DIR, PID_DIR, LEDGER_DIR, ORACFIT_USAGE_DIR and ORACFIT_USO_DIR
# live under $TMPDIR. A fake cursor-agent on PATH replays
# tests/fixtures/cursor-stream-sample.jsonl. No network, no model, no GPU.
# Do not run this suite in parallel with another suite that dispatches in the
# same repository: bin/dispatch.sh refuses a second dispatch on the same repo.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FINALIZE="$REPO_ROOT/bin/ledger-finalize.sh"
RUNNER="$REPO_ROOT/adapters/cursor/runner.sh"
FIX="$REPO_ROOT/tests/fixtures/cursor-stream-sample.jsonl"
# Session id and token counts from the `result` event in the fixture above.
FIX_SID="5f4642a1-9996-4d2e-8e95-7d1663766240"
FIX_IN=13279
FIX_OUT=138
FIX_READ=26048
FIX_WRITE=0

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/test-cursor-ledger.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
export TMPDIR="$WORKDIR/tmp"
mkdir -p "$TMPDIR"

# A parent dispatch may export these; this suite must not inherit them.
unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID ORACFIT_WORKDIR
unset DB_PATH CURSOR_AGENT_BIN CURSOR_AGENT_SUBCOMMAND
unset LEDGER_DIR ORACFIT_USAGE_DIR ORACFIT_USO_DIR
export DISPATCH_USAGE_FEEDBACK=1

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# setup_run <dir> [log-source] — meta, empty-or-copied log, exit 0. No pid file
# (the runner is already dead). Spec has no oracle section, so the finalizer
# does not run a command. Prints nothing; STARTED_AT is in <dir>/started.
setup_run() {
  local dest="$1"
  local src="${2:-}"
  mkdir -p "$dest/logs" "$dest/pids" "$dest/ledger" "$dest/usage" "$dest/uso"
  printf '%s\n' "# fixture spec without an oracle section" >"$dest/spec.md"
  local started
  started=$(date +%s)
  printf '%s\n' "$started" >"$dest/started"
  cat >"$dest/pids/dispatch-t.meta" <<EOF
TASK_NAME='t'
SPEC_FILE='$dest/spec.md'
MODEL='grok'
STARTED_AT='$started'
EOF
  printf '0\n' >"$dest/pids/dispatch-t.exit"
  if [ -n "$src" ] && [ -f "$src" ]; then
    cp "$src" "$dest/logs/dispatch-t.log"
  else
    : >"$dest/logs/dispatch-t.log"
  fi
}

# run_finalize <dir> [NAME=value ...] — DB_PATH is stripped first, then any
# extra assignments (so a test can put it back).
run_finalize() {
  local dest="$1"
  shift
  env -u DB_PATH \
    LOG_DIR="$dest/logs" \
    PID_DIR="$dest/pids" \
    LEDGER_DIR="$dest/ledger" \
    ORACFIT_USAGE_DIR="$dest/usage" \
    ORACFIT_USO_DIR="$dest/uso" \
    "$@" \
    bash "$FINALIZE" t
}

assert_ledger_row() {
  python3 - "$@" <<'PY'
import json, sys
path, sid, tin, tout, tread, twrite = sys.argv[1:7]
raw = open(path, encoding="utf-8").read().splitlines()
assert raw, "ledger is empty"
row = json.loads(raw[-1])
assert row.get("session_id") == sid, row
assert int(row.get("tokens_input") or 0) == int(tin), row
assert int(row.get("tokens_output") or 0) == int(tout), row
assert int(row.get("tokens_cache_read") or 0) == int(tread), row
assert int(row.get("tokens_cache_write") or 0) == int(twrite), row
PY
}

write_e2e_spec() {
  cat >"$1" <<'EOF'
# Task: mark the target

Do not invent numbers, dates or sources beyond those listed.
Never use declare const as a workaround — import for real.

## Verified data
- alvo.txt exists in the workdir (verified)

## Verification
VERIFICATION: grep -q done alvo.txt

## Oracle
- command: grep -q done alvo.txt
- expected exit: 0
EOF
}

echo "=== test-cursor-ledger ==="

# ── 1. the cursor dispatch closes the ledger ────────────────────────────────
echo "== 1. the cursor dispatch closes the ledger"
E2E="$WORKDIR/e2e"
mkdir -p "$E2E/wd" "$E2E/bin" "$E2E/logs" "$E2E/pids" "$E2E/ledger" "$E2E/usage" "$E2E/uso"
printf '%s\n' "not yet" >"$E2E/wd/alvo.txt"
write_e2e_spec "$E2E/wd/spec.md"
printf '%s\n' '{"models":[{"id":"grok","provider":"cursor","cli_hints":{"cursor":"cursor-grok-4.6-xhigh-fast"}}]}' \
  >"$E2E/reg.json"
cat >"$E2E/bin/cursor-agent" <<EOF
#!/usr/bin/env bash
cat "$FIX"
EOF
chmod +x "$E2E/bin/cursor-agent"

E2E_RC=0
( cd "$E2E/wd" && env -u DB_PATH -u ORACFIT_EVENTS_FILE -u ORACFIT_RUN_ID \
    -u ORACFIT_WORKDIR -u CURSOR_AGENT_BIN -u CURSOR_AGENT_SUBCOMMAND \
    PATH="$E2E/bin:$PATH" \
    DISPATCH_RUNNER="$RUNNER" \
    DISPATCH_RUNNER_NAME=cursor \
    DISPATCH_RUNNER_FORMAT_JSON=1 \
    MODEL_REGISTRY="$E2E/reg.json" \
    CURSOR_API_KEY=x \
    LOG_DIR="$E2E/logs" \
    PID_DIR="$E2E/pids" \
    LEDGER_DIR="$E2E/ledger" \
    ORACFIT_USAGE_DIR="$E2E/usage" \
    ORACFIT_USO_DIR="$E2E/uso" \
    DISPATCH_USAGE_FEEDBACK=1 \
    DISPATCH_TIMEOUT=60 \
    DISPATCH_SILENT_LIMIT=30 \
    bash "$REPO_ROOT/bin/dispatch.sh" grok "$E2E/wd/spec.md" cursor-ledger-e2e \
    >"$E2E/dispatch.out" 2>"$E2E/dispatch.err" ) || E2E_RC=$?

E2E_LEDGER="$E2E/ledger/ledger.jsonl"
deadline=$((SECONDS + 30))
while [ "$SECONDS" -lt "$deadline" ]; do
  if [ -s "$E2E_LEDGER" ]; then
    break
  fi
  sleep 0.2
done

if [ "$E2E_RC" -eq 0 ] && assert_ledger_row "$E2E_LEDGER" "$FIX_SID" "$FIX_IN" "$FIX_OUT" "$FIX_READ" "$FIX_WRITE"
then
  ok "the cursor dispatch closes the ledger"
else
  not "the cursor dispatch closes the ledger (rc=$E2E_RC ledger=$(ls -l "$E2E_LEDGER" 2>/dev/null || true) err=$(head -c 400 "$E2E/dispatch.err" 2>/dev/null) log=$(head -c 400 "$E2E/logs/dispatch-cursor-ledger-e2e.log" 2>/dev/null))"
fi

# ── 2. the finalizer writes a row without a session database ─────────────────
echo "== 2. the finalizer writes a row without a session database"
P2="$WORKDIR/p2"
setup_run "$P2" "$FIX"
P2_RC=0
run_finalize "$P2" >/dev/null 2>"$P2/finalize.err" || P2_RC=$?
if [ "$P2_RC" -eq 0 ] && [ -s "$P2/ledger/ledger.jsonl" ]; then
  ok "the finalizer writes a row without a session database"
else
  not "the finalizer writes a row without a session database (rc=$P2_RC err=$(head -c 300 "$P2/finalize.err" 2>/dev/null))"
fi

# ── 3. the log fills the session and the tokens ──────────────────────────────
echo "== 3. the log fills the session and the tokens"
P3="$WORKDIR/p3"
setup_run "$P3" "$FIX"
P3_RC=0
run_finalize "$P3" >/dev/null 2>"$P3/finalize.err" || P3_RC=$?
if [ "$P3_RC" -eq 0 ] && assert_ledger_row "$P3/ledger/ledger.jsonl" "$FIX_SID" "$FIX_IN" "$FIX_OUT" "$FIX_READ" "$FIX_WRITE"
then
  ok "the log fills the session and the tokens"
else
  not "the log fills the session and the tokens (rc=$P3_RC err=$(head -c 300 "$P3/finalize.err" 2>/dev/null))"
fi

# ── 4. the session database still wins ───────────────────────────────────────
echo "== 4. the session database still wins"
P4="$WORKDIR/p4"
setup_run "$P4" "$FIX"
P4_STARTED=$(cat "$P4/started")
P4_SID="db-session-primary"
sqlite3 "$P4/sessions.db" <<EOF
CREATE TABLE session (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  time_created INTEGER NOT NULL,
  tokens_input INTEGER DEFAULT 0,
  tokens_output INTEGER DEFAULT 0,
  tokens_reasoning INTEGER DEFAULT 0,
  tokens_cache_read INTEGER DEFAULT 0,
  tokens_cache_write INTEGER DEFAULT 0,
  cost REAL DEFAULT 0,
  model TEXT
);
INSERT INTO session (
  id, parent_id, time_created,
  tokens_input, tokens_output, tokens_reasoning,
  tokens_cache_read, tokens_cache_write, cost, model
) VALUES (
  '$P4_SID', NULL, $((P4_STARTED * 1000)),
  111, 222, 5,
  333, 444, 0,
  '{"id":"from-db","providerID":"sqlite"}'
);
EOF
P4_RC=0
run_finalize "$P4" DB_PATH="$P4/sessions.db" >/dev/null 2>"$P4/finalize.err" || P4_RC=$?
if [ "$P4_RC" -eq 0 ] && assert_ledger_row "$P4/ledger/ledger.jsonl" "$P4_SID" 111 222 333 444
then
  ok "the session database still wins"
else
  not "the session database still wins (rc=$P4_RC err=$(head -c 300 "$P4/finalize.err" 2>/dev/null) row=$(cat "$P4/ledger/ledger.jsonl" 2>/dev/null))"
fi

# ── 5. a log without a result event still writes the row ─────────────────────
echo "== 5. a log without a result event still writes the row"
P5="$WORKDIR/p5"
setup_run "$P5"
cat >"$P5/logs/dispatch-t.log" <<'EOF'
{"type":"assistant","session_id":"not-a-result"}
this line is not json
EOF
P5_RC=0
run_finalize "$P5" >/dev/null 2>"$P5/finalize.err" || P5_RC=$?
if [ "$P5_RC" -eq 0 ] && assert_ledger_row "$P5/ledger/ledger.jsonl" "" 0 0 0 0
then
  ok "a log without a result event still writes the row"
else
  not "a log without a result event still writes the row (rc=$P5_RC err=$(head -c 300 "$P5/finalize.err" 2>/dev/null))"
fi

# ── 6. the usage row carries the session id ──────────────────────────────────
echo "== 6. the usage row carries the session id"
P6="$WORKDIR/p6"
setup_run "$P6" "$FIX"
P6_RC=0
run_finalize "$P6" >/dev/null 2>"$P6/finalize.err" || P6_RC=$?
if [ "$P6_RC" -eq 0 ] && python3 - "$P6/usage/usage.jsonl" "$FIX_SID" <<'PY'
import json, sys
path, sid = sys.argv[1], sys.argv[2]
raw = open(path, encoding="utf-8").read().splitlines()
assert raw, "usage.jsonl is empty"
row = json.loads(raw[-1])
extra = row.get("extra") or {}
assert extra.get("session_id") == sid, row
PY
then
  ok "the usage row carries the session id"
else
  not "the usage row carries the session id (rc=$P6_RC err=$(head -c 300 "$P6/finalize.err" 2>/dev/null) usage=$(cat "$P6/usage/usage.jsonl" 2>/dev/null | head -c 400))"
fi

echo
echo "test-cursor-ledger: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
