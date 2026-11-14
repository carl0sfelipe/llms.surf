#!/bin/bash
# test-supervisor-ask.sh — the runtime asks the supervisor at the attempt
# boundary and the answers become an order. Hermetic: temp workdir, temp
# ORACFIT_ROOT, stub runner, local HTTP stub on 127.0.0.1 (port from a
# file). No model, no network beyond localhost, never writes the real
# checkout.
set -uo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="$REAL_ROOT/bin/dispatch-mode.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-ask.XXXXXX")"
STUB_PID=""
cleanup() {
  if [ -n "${STUB_PID:-}" ]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
  fi
  rm -rf "$SCRATCH"
}
trap cleanup EXIT

export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"

export ORACFIT_ROOT="$SCRATCH/oracfit-root"
mkdir -p "$ORACFIT_ROOT"
ln -s "$REAL_ROOT/bin" "$ORACFIT_ROOT/bin"

export DISPATCH_USAGE_FEEDBACK=0
unset DISPATCH_ROOT
unset DISPATCH_MODEL_REF
unset ORACFIT_WORKDIR
unset ORACFIT_EVENTS_FILE
unset ORACFIT_NTFY_TOPIC
unset ORACFIT_RUN_ID
unset ORACFIT_SUPERVISOR_DECISION
unset ORACFIT_SUPERVISOR_ENDPOINT
unset ORACFIT_SUPERVISOR_POLICY
unset ORACFIT_SUPERVISOR_TIMEOUT

# A git hook or an outer dispatch may export GIT_DIR; the scratch repos must
# not inherit them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
printf '[user]\n\tuseConfigOnly = true\n[init]\n\tdefaultBranch = main\n' \
  >"$GIT_CONFIG_GLOBAL"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

count_jsonl() {
  python3 -c '
import json, sys
path = sys.argv[1]
filters = {}
for arg in sys.argv[2:]:
    k, v = arg.split("=", 1)
    filters[k] = v
n = 0
try:
    fh = open(path)
except OSError:
    print(0)
    raise SystemExit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    if all(str(obj.get(k, "")) == v for k, v in filters.items()):
        n += 1
print(n)
' "$@"
}

run_id_of() {
  python3 -c '
import json, sys
try:
    fh = open(sys.argv[1])
except OSError:
    raise SystemExit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    rid = obj.get("run_id") or ""
    if rid:
        print(rid)
        raise SystemExit(0)
' "$1/.dispatch/logs/events.jsonl"
}

HINT="ASK_CHAIN_HINT put the prescription in the next attempt spec"
Q_NOUL="r16-recurring-failure-becomes-a-rule"
Q_WITHHELD="r10-fork-needs-real-session-id"

SPEC="$SCRATCH/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Supervisor ask fixture

## Objetivo
Nao invente numero, prazo, citacao ou fonte alem dos listados.

## Dados verificados
O fixture nao precisa de fatos numericos.

## Verificacao
test -f marker.txt && grep -q "work done" marker.txt

## Oraculo
- comando: test -f marker.txt && grep -q "work done" marker.txt
- exit esperado: 0

## Barra
- nome: supervisor ask fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$SCRATCH/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
wd="${ORACFIT_WORKDIR:-$PWD}"
count_file="$wd/attempt-count"
count=0
if [ -f "$count_file" ]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ -n "${2:-}" ] && [ -f "$2" ]; then
  cp "$2" "$wd/received-spec-${count}.md"
fi
if [ "$count" -ge 2 ]; then
  printf 'work done\n' >"$wd/marker.txt"
fi
exit 0
EOF
chmod +x "$FAKE_RUNNER"

write_mode() {
  mkdir -p "$1/core/modes"
  cat >"$1/core/modes/supervisor-ask-fixture.yaml" <<'YAML'
id: supervisor-ask-fixture
version: "1"
max_attempts: 2
stages:
  - role: run
    model_ref: fixture-model
    max_attempts: 2
gauntlet:
  enabled: false
  inject_feedback: false
  until_approved: false
on_fail: halt
YAML
}

accum_of() {
  local wd="$1"
  local f=""
  f="$(ls -1 "$wd"/.dispatch/logs/inbox/*.gauntlet/feedback.md 2>/dev/null | head -1)"
  printf '%s' "$f"
}

accum_body() {
  local f
  f="$(accum_of "$1")"
  if [ -n "$f" ] && [ -f "$f" ]; then
    cat "$f"
  fi
}

init_workdir() {
  local wd="$1"
  mkdir -p "$wd"
  write_mode "$wd"
  cp "$SPEC" "$wd/spec.md"
  printf '.dispatch/\n' >"$wd/.gitignore"
  git -C "$wd" init -q
  git -C "$wd" -c user.name=test -c user.email=test@localhost add -A
  git -C "$wd" -c user.name=test -c user.email=test@localhost commit -q -m init
}

run_dispatch() {
  local wd="$1"
  local usage_flag="${2:-0}"
  init_workdir "$wd"
  unset ORACFIT_SUPERVISOR_DECISION
  local rc=0
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    DISPATCH_USAGE_FEEDBACK="$usage_flag" \
    ORACFIT_USAGE_DIR="$wd/usage" \
    ORACFIT_USO_DIR="$wd/uso" \
    LOG_DIR="$wd/.dispatch/logs" \
    "$MODE" supervisor-ask-fixture "$wd/spec.md" "sup-$(basename "$wd")" \
    --workdir "$wd" >"$wd/dispatch.out" 2>"$wd/dispatch.err" || rc=$?
  printf '%s' "$rc"
}

inbox_of() {
  printf '%s' "$1/.dispatch/logs/inbox"
}

cat >"$SCRATCH/stub.py" <<'PY'
#!/usr/bin/env python3
"""Local System-One stub. Answers every asked id."""
from __future__ import annotations

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any


def make_answer(qid: str, question: Any) -> dict[str, Any]:
    qtype = question.get("type") if isinstance(question, dict) else None
    if qtype == "choice":
        criteria = question.get("criteria") if isinstance(question.get("criteria"), dict) else {}
        first = next(iter(criteria), "a")
        return {
            "type": "choice",
            "probabilities": {first: 0.71},
            "choice": first,
            "confidence": 0.71,
        }
    if qtype == "score":
        return {
            "type": "score",
            "probabilities": {"0": 0.1, "1": 0.9},
            "score": 1.0,
            "legend": {"0": "low", "1": "high"},
        }
    return {"type": "noul", "noul": 0.83}


def answers_for(questions: Any) -> dict[str, Any]:
    if not isinstance(questions, dict):
        return {}
    return {qid: make_answer(qid, q) for qid, q in questions.items()}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port-file", required=True)
    parser.add_argument("--record", required=True)
    parser.add_argument("--ids-file", required=True)
    args = parser.parse_args()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt: str, *rest: Any) -> None:
            return

        def _send(self, status: int, body: bytes, content_type: str) -> None:
            try:
                self.send_response(status)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except BrokenPipeError:
                return

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length") or "0")
            raw = self.rfile.read(length) if length else b""
            parsed: Any
            try:
                parsed = json.loads(raw.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                parsed = raw.decode("utf-8", "replace")
            record = {
                "method": self.command,
                "path": self.path,
                "content_type": self.headers.get("Content-Type", ""),
                "body": parsed,
            }
            Path(args.record).write_text(
                json.dumps(record, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            questions = parsed.get("questions") if isinstance(parsed, dict) else {}
            received_ids = list(questions) if isinstance(questions, dict) else []
            Path(args.ids_file).write_text(
                json.dumps(received_ids, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )
            payload = {
                "answers": answers_for(questions),
                "usage": {"input_tokens": 412, "output_tokens": 0},
            }
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self._send(200, body, "application/json")

    httpd = HTTPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    Path(args.port_file).write_text(f"{port}\n", encoding="utf-8")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
PY

stop_stub() {
  if [ -n "${STUB_PID:-}" ]; then
    kill "$STUB_PID" 2>/dev/null || true
    wait "$STUB_PID" 2>/dev/null || true
    STUB_PID=""
  fi
}

wait_port_file() {
  local f="$1"
  local i
  for i in $(seq 1 50); do
    if [ -s "$f" ]; then
      return 0
    fi
    if [ -n "${STUB_PID:-}" ] && ! kill -0 "$STUB_PID" 2>/dev/null; then
      return 1
    fi
    sleep 0.1
  done
  return 1
}

start_stub() {
  stop_stub
  rm -f "$SCRATCH/stub.port" "$SCRATCH/stub.request.json" "$SCRATCH/stub.ids.json"
  python3 "$SCRATCH/stub.py" \
    --port-file "$SCRATCH/stub.port" \
    --record "$SCRATCH/stub.request.json" \
    --ids-file "$SCRATCH/stub.ids.json" \
    >"$SCRATCH/stub.log" 2>&1 &
  STUB_PID=$!
  if ! wait_port_file "$SCRATCH/stub.port"; then
    echo "  stub did not write a port file" >&2
    cat "$SCRATCH/stub.log" >&2 || true
    return 1
  fi
}

endpoint_url() {
  local port
  port="$(tr -d '[:space:]' < "$SCRATCH/stub.port")"
  printf 'http://127.0.0.1:%s/v1/systemone' "$port"
}

python3 - "$SCRATCH/calibrated-policy.json" "$SCRATCH/uncalibrated-mapped-policy.json" \
  "$SCRATCH/empty-rules-policy.json" "$SCRATCH/withheld-policy.json" \
  "$Q_NOUL" "$HINT" "$Q_WITHHELD" <<'PY'
import json, sys
calibrated, uncalibrated, empty, withheld, qid, hint, q_withheld = sys.argv[1:8]
mapped = {
    "version": 1,
    "thresholds": {"act_above": 0.8},
    "rules": {
        qid: {"action": "INJECT_HINT", "hint": hint},
    },
}
cal = dict(mapped)
cal["calibration"] = {
    "ring": "test-ring",
    "line": "copied calibration line from ring test-ring",
}
uncal = dict(mapped)
uncal["calibration"] = {"ring": "", "line": ""}
nobody = {
    "version": 1,
    "calibration": {"ring": "", "line": ""},
    "thresholds": {"act_above": 0.8},
    "rules": {},
}
withheld_doc = {
    "version": 1,
    "calibration": {
        "ring": "test-ring",
        "line": "copied calibration line from ring test-ring",
    },
    "thresholds": {"act_above": 0.8},
    "rules": {
        q_withheld: {"action": "INJECT_HINT", "hint": hint},
    },
}
for path, doc in (
    (calibrated, cal),
    (uncalibrated, uncal),
    (empty, nobody),
    (withheld, withheld_doc),
):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
PY

# ── 1. without an endpoint the runtime asks nothing ─────────────────────
BASE="$SCRATCH/base"
unset ORACFIT_SUPERVISOR_ENDPOINT
unset ORACFIT_SUPERVISOR_POLICY
base_rc="$(run_dispatch "$BASE")"
BASE_RID="$(run_id_of "$BASE")"
BASE_INBOX="$(inbox_of "$BASE")"
BASE_ACCUM="$(accum_body "$BASE")"
n_ask="$(count_jsonl "$BASE/.dispatch/logs/events.jsonl" type=supervisor_ask)"
if [ "$base_rc" -eq 0 ] \
  && [ ! -f "$BASE_INBOX/${BASE_RID}.answers.json" ] \
  && [ ! -f "$BASE_INBOX/${BASE_RID}.json" ] \
  && [ "$n_ask" -eq 0 ]; then
  ok "without an endpoint the runtime asks nothing"
else
  not "without an endpoint the runtime asks nothing (rc=$base_rc rid=$BASE_RID ask=$n_ask answers=$([ -f "$BASE_INBOX/${BASE_RID}.answers.json" ] && echo yes || echo no) decision=$([ -f "$BASE_INBOX/${BASE_RID}.json" ] && echo yes || echo no) err=$(head -c 300 "$BASE/dispatch.err"))"
fi

# ── 2–3, 7. stub + calibrated policy ────────────────────────────────────
if ! start_stub; then
  not "the runtime asks the supervisor endpoint"
  not "the answers become an order"
  not "the decision record lands in the inbox"
  not "the runtime asks only the mapped questions"
else
  ASK="$SCRATCH/ask"
  export ORACFIT_SUPERVISOR_ENDPOINT="$(endpoint_url)"
  export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/calibrated-policy.json"
  ask_rc="$(run_dispatch "$ASK")"
  ASK_RID="$(run_id_of "$ASK")"
  ASK_INBOX="$(inbox_of "$ASK")"
  ASK_ANSWERS="$ASK_INBOX/${ASK_RID}.answers.json"
  ASK_DECISION="$ASK_INBOX/${ASK_RID}.json"
  ASK_EVENTS="$ASK/.dispatch/logs/events.jsonl"
  ASK_SPEC2="$ASK/received-spec-2.md"
  n_applied="$(count_jsonl "$ASK_EVENTS" type=supervisor_order result=applied)"

  if [ -f "$ASK_ANSWERS" ] && python3 - "$ASK_ANSWERS" "$Q_NOUL" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
qid = sys.argv[2]
assert "answers" in rec, rec.keys()
ans = rec["answers"]
assert qid in ans, sorted(ans)
assert ans[qid] == {"type": "noul", "noul": 0.83}, ans[qid]
PY
  then
    ok "the runtime asks the supervisor endpoint"
  else
    not "the runtime asks the supervisor endpoint (rc=$ask_rc answers=$([ -f "$ASK_ANSWERS" ] && echo yes || echo no) err=$(head -c 400 "$ASK/dispatch.err"))"
  fi

  if [ "$ask_rc" -eq 0 ] && [ -f "$ASK_SPEC2" ] \
    && grep -q "$HINT" "$ASK_SPEC2" \
    && [ "$n_applied" -eq 1 ]; then
    ok "the answers become an order"
  else
    not "the answers become an order (rc=$ask_rc spec2=$([ -f "$ASK_SPEC2" ] && echo yes || echo missing) applied=$n_applied hint=$( [ -f "$ASK_SPEC2" ] && grep -c "$HINT" "$ASK_SPEC2" || echo 0) err=$(head -c 400 "$ASK/dispatch.err"))"
  fi

  if [ -f "$ASK_DECISION" ] && python3 - "$ASK_DECISION" <<'PY'
import json, sys
rec = json.load(open(sys.argv[1], encoding="utf-8"))
assert "decision" in rec, rec
assert "reason" in rec, rec
assert "order" in rec, rec
PY
  then
    ok "the decision record lands in the inbox"
  else
    not "the decision record lands in the inbox (path=$ASK_DECISION exists=$([ -f "$ASK_DECISION" ] && echo yes || echo no))"
  fi

  if [ -f "$SCRATCH/stub.ids.json" ] && python3 - "$SCRATCH/stub.ids.json" "$Q_NOUL" \
    "$REAL_ROOT/core/supervisor/questions.json" <<'PY'
import json, sys
ids = json.load(open(sys.argv[1], encoding="utf-8"))
qid = sys.argv[2]
questions = json.load(open(sys.argv[3], encoding="utf-8")).get("questions") or []
all_ids = [q.get("id") for q in questions if isinstance(q, dict) and q.get("id")]
assert ids == [qid], ids
assert qid in all_ids
assert len(all_ids) > 1
assert len(ids) < len(all_ids)
PY
  then
    ok "the runtime asks only the mapped questions"
  else
    not "the runtime asks only the mapped questions (ids=$([ -f "$SCRATCH/stub.ids.json" ] && cat "$SCRATCH/stub.ids.json" || echo missing))"
  fi
fi

# ── 4. an uncalibrated policy decides CONTINUE ──────────────────────────
UNC="$SCRATCH/uncalibrated"
export ORACFIT_SUPERVISOR_ENDPOINT="$(endpoint_url)"
export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/uncalibrated-mapped-policy.json"
unc_rc="$(run_dispatch "$UNC")"
UNC_ACCUM="$(accum_body "$UNC")"
if [ "$unc_rc" -eq "$base_rc" ] \
  && ! printf '%s' "$UNC_ACCUM" | grep -q "SUPERVISOR ORDER" \
  && [ "$(printf '%s' "$UNC_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ]; then
  ok "an uncalibrated policy decides CONTINUE"
else
  not "an uncalibrated policy decides CONTINUE (rc=$unc_rc base=$base_rc accum=$(printf '%s' "$UNC_ACCUM" | head -c 200) err=$(head -c 300 "$UNC/dispatch.err"))"
fi

# ── a policy with no mapped question asks nobody ────────────────────────
rm -f "$SCRATCH/stub.request.json" "$SCRATCH/stub.ids.json"
NOBODY="$SCRATCH/nobody"
export ORACFIT_SUPERVISOR_ENDPOINT="$(endpoint_url)"
export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/empty-rules-policy.json"
nobody_rc="$(run_dispatch "$NOBODY")"
NOBODY_RID="$(run_id_of "$NOBODY")"
NOBODY_INBOX="$(inbox_of "$NOBODY")"
NOBODY_ACCUM="$(accum_body "$NOBODY")"
if [ "$nobody_rc" -eq "$base_rc" ] \
  && [ ! -f "$SCRATCH/stub.request.json" ] \
  && [ ! -f "$SCRATCH/stub.ids.json" ] \
  && [ ! -f "$NOBODY_INBOX/${NOBODY_RID}.answers.json" ] \
  && [ ! -f "$NOBODY_INBOX/${NOBODY_RID}.json" ] \
  && [ "$(printf '%s' "$NOBODY_ACCUM")" = "$(printf '%s' "$BASE_ACCUM")" ]; then
  ok "a policy with no mapped question asks nobody"
else
  not "a policy with no mapped question asks nobody (rc=$nobody_rc base=$base_rc request=$([ -f "$SCRATCH/stub.request.json" ] && echo yes || echo no) ids=$([ -f "$SCRATCH/stub.ids.json" ] && echo yes || echo no) decision=$([ -f "$NOBODY_INBOX/${NOBODY_RID}.json" ] && echo yes || echo no) err=$(head -c 300 "$NOBODY/dispatch.err"))"
fi

# ── the withheld question never reaches the wire ────────────────────────
rm -f "$SCRATCH/stub.request.json" "$SCRATCH/stub.ids.json"
WITHHELD="$SCRATCH/withheld"
export ORACFIT_SUPERVISOR_ENDPOINT="$(endpoint_url)"
export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/withheld-policy.json"
withheld_rc="$(run_dispatch "$WITHHELD")"
WITHHELD_EVENTS="$WITHHELD/.dispatch/logs/events.jsonl"
n_withheld_ask="$(count_jsonl "$WITHHELD_EVENTS" type=supervisor_ask result=failed)"
if [ "$withheld_rc" -eq "$base_rc" ] \
  && [ ! -f "$SCRATCH/stub.request.json" ] \
  && [ ! -f "$SCRATCH/stub.ids.json" ] \
  && [ "$n_withheld_ask" -ge 1 ]; then
  ok "the withheld question never reaches the wire"
else
  not "the withheld question never reaches the wire (rc=$withheld_rc base=$base_rc request=$([ -f "$SCRATCH/stub.request.json" ] && echo yes || echo no) ids=$([ -f "$SCRATCH/stub.ids.json" ] && echo yes || echo no) ask=$n_withheld_ask err=$(head -c 300 "$WITHHELD/dispatch.err"))"
fi

stop_stub

# ── 5–6. a failing endpoint does not fail the run ───────────────────────
closed_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
DEAD="$SCRATCH/dead"
export ORACFIT_SUPERVISOR_ENDPOINT="http://127.0.0.1:${closed_port}/v1/systemone"
export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/uncalibrated-mapped-policy.json"
dead_rc="$(run_dispatch "$DEAD" 1)"
DEAD_EVENTS="$DEAD/.dispatch/logs/events.jsonl"
DEAD_LEDGER="$DEAD/.dispatch/ledger/mode.jsonl"
DEAD_USAGE="$DEAD/usage/usage.jsonl"
DEAD_ACCUM="$(accum_body "$DEAD")"
n_dead_applied="$(count_jsonl "$DEAD_EVENTS" type=supervisor_order result=applied)"
n_dead_ask="$(count_jsonl "$DEAD_EVENTS" type=supervisor_ask result=failed)"
n_ledger="$(count_jsonl "$DEAD_LEDGER")"
n_usage=0
if [ -f "$DEAD_USAGE" ]; then
  n_usage="$(count_jsonl "$DEAD_USAGE")"
fi

if [ "$dead_rc" -eq "$base_rc" ] \
  && [ "$n_dead_applied" -eq 0 ] \
  && [ "$n_dead_ask" -ge 1 ] \
  && ! printf '%s' "$DEAD_ACCUM" | grep -q "SUPERVISOR ORDER"; then
  ok "a failing endpoint does not fail the run"
else
  not "a failing endpoint does not fail the run (rc=$dead_rc base=$base_rc applied=$n_dead_applied ask=$n_dead_ask err=$(head -c 400 "$DEAD/dispatch.err"))"
fi

if [ "$dead_rc" -eq "$base_rc" ] && [ "$n_ledger" -ge 1 ] && [ "$n_usage" -ge 1 ]; then
  ok "the ask never fails the run"
else
  not "the ask never fails the run (rc=$dead_rc ledger=$n_ledger usage=$n_usage err=$(head -c 400 "$DEAD/dispatch.err") out=$(head -c 200 "$DEAD/dispatch.out"))"
fi

echo
echo "test-supervisor-ask: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
