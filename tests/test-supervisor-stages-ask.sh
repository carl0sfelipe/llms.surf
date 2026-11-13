#!/bin/bash
# test-supervisor-stages-ask.sh — the multi-stage runtime asks the supervisor
# at the stage attempt boundary and the hint reaches the next attempt.
# Hermetic: temp workdir, temp ORACFIT_ROOT, stub runner, local HTTP stub on
# 127.0.0.1 (port from a file). No model, no network beyond localhost, never
# writes the real checkout.
set -uo pipefail

REAL_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGES="$REAL_ROOT/bin/dispatch-stages.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/oracfit-supervisor-stages-ask.XXXXXX")"
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
unset ORACFIT_SUPERVISOR_RESTORE_REF

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

HINT="STAGES_ASK_HINT put the prescription in the next stage attempt spec"
Q_NOUL="r16-recurring-failure-becomes-a-rule"
TRACKED_CLEAN="tracked clean"
TRACKED_DIRTY="tracked dirty"
STAGE1_CLEAN="stage1 clean"
STAGE1_DONE="stage1 done"
PERGUNTA="which watchdog should cover this long-running job?"
SE1="se keep it outside dispatch -> leave it running and ask after one attempt"
SE2="se bring it under dispatch -> stop the orphan and relaunch through dispatch.sh"

SPEC="$SCRATCH/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Supervisor stages ask fixture

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
- nome: supervisor stages ask fixture

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
  exit 0
fi
printf 'tracked dirty\n' >"$wd/tracked.txt"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

TWO_STAGE_RUNNER="$SCRATCH/two-stage-runner.sh"
cat >"$TWO_STAGE_RUNNER" <<EOF
#!/bin/bash
set -euo pipefail
wd="\${ORACFIT_WORKDIR:-\$PWD}"
role="\${ORACFIT_STAGE_ROLE:-}"
attempt="\${ORACFIT_STAGE_ATTEMPT:-1}"
if [ -n "\${2:-}" ] && [ -f "\$2" ]; then
  cp "\$2" "\$wd/received-spec-\${role}-\${attempt}.md"
fi
if [ "\$role" = "plan" ]; then
  printf '%s\n' "$STAGE1_DONE" >"\$wd/stage1.txt"
  exit 0
fi
if [ "\$attempt" -ge 2 ]; then
  printf 'work done\n' >"\$wd/marker.txt"
  exit 0
fi
printf '%s\n' "$TRACKED_DIRTY" >"\$wd/tracked.txt"
exit 0
EOF
chmod +x "$TWO_STAGE_RUNNER"

write_mode() {
  mkdir -p "$1/core/modes"
  cat >"$1/core/modes/supervisor-stages-ask-fixture.yaml" <<'YAML'
id: supervisor-stages-ask-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    oracle: true
    max_attempts: 2
on_fail: halt
YAML
}

write_decision() {
  python3 -c '
import json, sys
path = sys.argv[1]
doc = json.load(sys.stdin)
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
' "$1"
}

inbox_of() {
  printf '%s' "$1/.dispatch/logs/inbox"
}

init_workdir() {
  local wd="$1"
  mkdir -p "$wd"
  write_mode "$wd"
  cp "$SPEC" "$wd/spec.md"
  printf '%s\n' "$TRACKED_CLEAN" >"$wd/tracked.txt"
  printf '.dispatch/\n' >"$wd/.gitignore"
  git -C "$wd" init -q
  git -C "$wd" -c user.name=test -c user.email=test@localhost add -A
  git -C "$wd" -c user.name=test -c user.email=test@localhost commit -q -m init
}

run_dispatch() {
  local wd="$1"
  local decision="${2:-}"
  local usage_flag="${3:-0}"
  init_workdir "$wd"
  unset ORACFIT_SUPERVISOR_DECISION
  if [ -n "$decision" ]; then
    export ORACFIT_SUPERVISOR_DECISION="$decision"
  fi
  local rc=0
  DISPATCH_RUNNER="$FAKE_RUNNER" \
    DISPATCH_USAGE_FEEDBACK="$usage_flag" \
    ORACFIT_USAGE_DIR="$wd/usage" \
    ORACFIT_USO_DIR="$wd/uso" \
    LOG_DIR="$wd/.dispatch/logs" \
    "$STAGES" supervisor-stages-ask-fixture "$wd/spec.md" "sup-$(basename "$wd")" \
    --workdir "$wd" >"$wd/dispatch.out" 2>"$wd/dispatch.err" || rc=$?
  unset ORACFIT_SUPERVISOR_DECISION
  printf '%s' "$rc"
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
  rm -f "$SCRATCH/stub.port" "$SCRATCH/stub.request.json"
  python3 "$SCRATCH/stub.py" \
    --port-file "$SCRATCH/stub.port" \
    --record "$SCRATCH/stub.request.json" \
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

python3 - "$SCRATCH/calibrated-policy.json" "$Q_NOUL" "$HINT" <<'PY'
import json, sys
path, qid, hint = sys.argv[1], sys.argv[2], sys.argv[3]
doc = {
    "version": 1,
    "calibration": {
        "ring": "test-ring",
        "line": "copied calibration line from ring test-ring",
    },
    "thresholds": {"act_above": 0.8},
    "rules": {
        qid: {"action": "INJECT_HINT", "hint": hint},
    },
}
with open(path, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY

RESET_JSON="$SCRATCH/reset.json"
write_decision "$RESET_JSON" <<JSON
{
  "decision": "RESET",
  "reason": "fixture reset",
  "order": {
    "action": "RESET",
    "question_id": "r16-recurring-failure-becomes-a-rule",
    "value": 0.9,
    "hint": "$HINT"
  }
}
JSON

ESC_JSON="$SCRATCH/escalate.json"
write_decision "$ESC_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "$PERGUNTA",
    "se": [
      "$SE1",
      "$SE2"
    ]
  }
}
JSON

NOFORK_JSON="$SCRATCH/escalate-no-fork.json"
write_decision "$NOFORK_JSON" <<JSON
{
  "decision": "ESCALATE",
  "reason": "fixture escalate without fork",
  "order": {
    "action": "ESCALATE",
    "question_id": "r42-long-job-outside-dispatch-is-orphan",
    "value": 0.9,
    "pergunta": "$PERGUNTA",
    "se": [
      "$SE1"
    ]
  }
}
JSON

# ── 1. without an endpoint the multi-stage asks nothing ─────────────────
BASE="$SCRATCH/base"
unset ORACFIT_SUPERVISOR_ENDPOINT
unset ORACFIT_SUPERVISOR_POLICY
base_rc="$(run_dispatch "$BASE")"
BASE_RID="$(run_id_of "$BASE")"
BASE_INBOX="$(inbox_of "$BASE")"
n_ask="$(count_jsonl "$BASE/.dispatch/logs/events.jsonl" type=supervisor_ask)"
if [ "$base_rc" -eq 0 ] \
  && [ ! -f "$BASE_INBOX/${BASE_RID}.answers.json" ] \
  && [ ! -f "$BASE_INBOX/${BASE_RID}.json" ] \
  && [ "$n_ask" -eq 0 ]; then
  ok "without an endpoint the multi-stage asks nothing"
else
  not "without an endpoint the multi-stage asks nothing (rc=$base_rc rid=$BASE_RID ask=$n_ask answers=$([ -f "$BASE_INBOX/${BASE_RID}.answers.json" ] && echo yes || echo no) decision=$([ -f "$BASE_INBOX/${BASE_RID}.json" ] && echo yes || echo no) err=$(head -c 300 "$BASE/dispatch.err"))"
fi

# ── 2–3. stub + calibrated policy ───────────────────────────────────────
if ! start_stub; then
  not "the multi-stage asks the supervisor endpoint"
  not "the hint reaches the next stage attempt"
else
  ASK="$SCRATCH/ask"
  export ORACFIT_SUPERVISOR_ENDPOINT="$(endpoint_url)"
  export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/calibrated-policy.json"
  ask_rc="$(run_dispatch "$ASK")"
  ASK_RID="$(run_id_of "$ASK")"
  ASK_INBOX="$(inbox_of "$ASK")"
  ASK_ANSWERS="$ASK_INBOX/${ASK_RID}.answers.json"
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
    ok "the multi-stage asks the supervisor endpoint"
  else
    not "the multi-stage asks the supervisor endpoint (rc=$ask_rc answers=$([ -f "$ASK_ANSWERS" ] && echo yes || echo no) err=$(head -c 400 "$ASK/dispatch.err"))"
  fi

  if [ "$ask_rc" -eq 0 ] && [ -f "$ASK_SPEC2" ] \
    && grep -q "$HINT" "$ASK_SPEC2" \
    && [ "$n_applied" -eq 1 ]; then
    ok "the hint reaches the next stage attempt"
  else
    not "the hint reaches the next stage attempt (rc=$ask_rc spec2=$([ -f "$ASK_SPEC2" ] && echo yes || echo missing) applied=$n_applied hint=$( [ -f "$ASK_SPEC2" ] && grep -c "$HINT" "$ASK_SPEC2" || echo 0) err=$(head -c 400 "$ASK/dispatch.err"))"
  fi
fi

stop_stub
unset ORACFIT_SUPERVISOR_ENDPOINT
unset ORACFIT_SUPERVISOR_POLICY

# ── 4. a RESET order restores the stage checkpoint ──────────────────────
RESET_WD="$SCRATCH/reset"
mkdir -p "$RESET_WD/core/modes"
cat >"$RESET_WD/core/modes/supervisor-stages-ask-fixture.yaml" <<'YAML'
id: supervisor-stages-ask-fixture
version: "1"
stages:
  - role: plan
    model_ref: fixture-model
    max_attempts: 1
  - role: run
    model_ref: fixture-model
    oracle: true
    max_attempts: 2
on_fail: halt
YAML
cp "$SPEC" "$RESET_WD/spec.md"
printf '%s\n' "$STAGE1_CLEAN" >"$RESET_WD/stage1.txt"
printf '%s\n' "$TRACKED_CLEAN" >"$RESET_WD/tracked.txt"
printf '.dispatch/\n' >"$RESET_WD/.gitignore"
git -C "$RESET_WD" init -q
git -C "$RESET_WD" -c user.name=test -c user.email=test@localhost add -A
git -C "$RESET_WD" -c user.name=test -c user.email=test@localhost commit -q -m init
unset ORACFIT_SUPERVISOR_DECISION
export ORACFIT_SUPERVISOR_DECISION="$RESET_JSON"
reset_rc=0
DISPATCH_RUNNER="$TWO_STAGE_RUNNER" \
  DISPATCH_USAGE_FEEDBACK=0 \
  ORACFIT_USAGE_DIR="$RESET_WD/usage" \
  ORACFIT_USO_DIR="$RESET_WD/uso" \
  LOG_DIR="$RESET_WD/.dispatch/logs" \
  "$STAGES" supervisor-stages-ask-fixture "$RESET_WD/spec.md" "sup-$(basename "$RESET_WD")" \
  --workdir "$RESET_WD" >"$RESET_WD/dispatch.out" 2>"$RESET_WD/dispatch.err" || reset_rc=$?
unset ORACFIT_SUPERVISOR_DECISION
n_reset_applied="$(count_jsonl "$RESET_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied action=RESET)"
n_reset_refused="$(count_jsonl "$RESET_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused action=RESET)"
if [ "$reset_rc" -eq "$base_rc" ] \
  && [ "$(cat "$RESET_WD/tracked.txt" 2>/dev/null)" = "$TRACKED_CLEAN" ] \
  && [ "$(cat "$RESET_WD/stage1.txt" 2>/dev/null)" = "$STAGE1_DONE" ] \
  && [ "$n_reset_applied" -ge 1 ] \
  && [ "$n_reset_refused" -eq 0 ]; then
  ok "a RESET order restores the stage checkpoint"
else
  not "a RESET order restores the stage checkpoint (rc=$reset_rc base=$base_rc tracked=$(cat "$RESET_WD/tracked.txt" 2>/dev/null) stage1=$(cat "$RESET_WD/stage1.txt" 2>/dev/null) applied=$n_reset_applied refused=$n_reset_refused err=$(head -c 400 "$RESET_WD/dispatch.err"))"
fi

# ── 4b. a RESET without a checkpoint is refused ─────────────────────────
NOCKPT_WD="$SCRATCH/no-checkpoint"
mkdir -p "$NOCKPT_WD"
write_mode "$NOCKPT_WD"
cp "$SPEC" "$NOCKPT_WD/spec.md"
printf '%s\n' "$TRACKED_CLEAN" >"$NOCKPT_WD/tracked.txt"
printf '.dispatch/\n' >"$NOCKPT_WD/.gitignore"
unset ORACFIT_SUPERVISOR_DECISION
export ORACFIT_SUPERVISOR_DECISION="$RESET_JSON"
nockpt_rc=0
DISPATCH_RUNNER="$FAKE_RUNNER" \
  DISPATCH_USAGE_FEEDBACK=0 \
  ORACFIT_USAGE_DIR="$NOCKPT_WD/usage" \
  ORACFIT_USO_DIR="$NOCKPT_WD/uso" \
  LOG_DIR="$NOCKPT_WD/.dispatch/logs" \
  "$STAGES" supervisor-stages-ask-fixture "$NOCKPT_WD/spec.md" "sup-$(basename "$NOCKPT_WD")" \
  --workdir "$NOCKPT_WD" >"$NOCKPT_WD/dispatch.out" 2>"$NOCKPT_WD/dispatch.err" || nockpt_rc=$?
unset ORACFIT_SUPERVISOR_DECISION
n_nockpt_applied="$(count_jsonl "$NOCKPT_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied action=RESET)"
n_nockpt_refused="$(count_jsonl "$NOCKPT_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused action=RESET)"
if [ "$nockpt_rc" -eq "$base_rc" ] \
  && [ "$(cat "$NOCKPT_WD/tracked.txt" 2>/dev/null)" = "$TRACKED_DIRTY" ] \
  && [ "$n_nockpt_applied" -eq 0 ] \
  && [ "$n_nockpt_refused" -ge 1 ]; then
  ok "a RESET without a checkpoint is refused"
else
  not "a RESET without a checkpoint is refused (rc=$nockpt_rc base=$base_rc tracked=$(cat "$NOCKPT_WD/tracked.txt" 2>/dev/null) applied=$n_nockpt_applied refused=$n_nockpt_refused err=$(head -c 400 "$NOCKPT_WD/dispatch.err"))"
fi

# ── 5. an ESCALATE order pauses the multi-stage run ─────────────────────
ESC_WD="$SCRATCH/escalate"
esc_rc="$(run_dispatch "$ESC_WD" "$ESC_JSON")"
ESC_RID="$(run_id_of "$ESC_WD")"
ESC_Q="$ESC_WD/.dispatch/logs/inbox/${ESC_RID}.question.md"
ESC_LEDGER="$ESC_WD/.dispatch/ledger/mode.jsonl"
n_ledger_oq="$(count_jsonl "$ESC_LEDGER" status=owner_question oracle_exit=7)"
if [ "$esc_rc" -eq 7 ] \
  && grep -q "status: owner_question" "$ESC_WD/dispatch.out" \
  && [ "$n_ledger_oq" -ge 1 ] \
  && [ -f "$ESC_Q" ] \
  && grep -q "^pergunta:" "$ESC_Q" \
  && [ "$(grep -cE '^se .+ -> ' "$ESC_Q")" -ge 2 ] \
  && [ "$(cat "$ESC_WD/attempt-count" 2>/dev/null)" = "1" ]; then
  ok "an ESCALATE order pauses the multi-stage run"
else
  not "an ESCALATE order pauses the multi-stage run (rc=$esc_rc status=$(grep -E '^status:' "$ESC_WD/dispatch.out" | head -1) ledger=$n_ledger_oq q=$([ -f "$ESC_Q" ] && echo yes || echo no) attempts=$(cat "$ESC_WD/attempt-count" 2>/dev/null) err=$(head -c 400 "$ESC_WD/dispatch.err"))"
fi

# ── 5b. an ESCALATE without the fork does not pause ─────────────────────
NOFORK_WD="$SCRATCH/no-fork"
nofork_rc="$(run_dispatch "$NOFORK_WD" "$NOFORK_JSON")"
NOFORK_RID="$(run_id_of "$NOFORK_WD")"
NOFORK_Q="$NOFORK_WD/.dispatch/logs/inbox/${NOFORK_RID}.question.md"
n_nofork_applied="$(count_jsonl "$NOFORK_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=applied)"
n_nofork_refused="$(count_jsonl "$NOFORK_WD/.dispatch/logs/events.jsonl" type=supervisor_order result=refused action=ESCALATE)"
if [ "$nofork_rc" -eq "$base_rc" ] \
  && [ "$nofork_rc" -ne 7 ] \
  && [ ! -f "$NOFORK_Q" ] \
  && [ "$n_nofork_applied" -eq 0 ] \
  && [ "$n_nofork_refused" -ge 1 ]; then
  ok "an ESCALATE without the fork does not pause the multi-stage run"
else
  not "an ESCALATE without the fork does not pause the multi-stage run (rc=$nofork_rc base=$base_rc q=$([ -f "$NOFORK_Q" ] && echo yes || echo no) applied=$n_nofork_applied refused=$n_nofork_refused err=$(head -c 400 "$NOFORK_WD/dispatch.err"))"
fi

# ── 6–7. a failing endpoint does not fail the multi-stage run ───────────
closed_port="$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')"
DEAD="$SCRATCH/dead"
export ORACFIT_SUPERVISOR_ENDPOINT="http://127.0.0.1:${closed_port}/v1/systemone"
export ORACFIT_SUPERVISOR_POLICY="$SCRATCH/calibrated-policy.json"
dead_rc="$(run_dispatch "$DEAD" "" 1)"
DEAD_EVENTS="$DEAD/.dispatch/logs/events.jsonl"
DEAD_LEDGER="$DEAD/.dispatch/ledger/mode.jsonl"
DEAD_USAGE="$DEAD/usage/usage.jsonl"
n_dead_applied="$(count_jsonl "$DEAD_EVENTS" type=supervisor_order result=applied)"
n_dead_ask="$(count_jsonl "$DEAD_EVENTS" type=supervisor_ask result=failed)"
n_ledger="$(count_jsonl "$DEAD_LEDGER")"
n_metric="$(count_jsonl "$DEAD_EVENTS" type=metric)"
n_usage=0
if [ -f "$DEAD_USAGE" ]; then
  n_usage="$(count_jsonl "$DEAD_USAGE")"
fi

if [ "$dead_rc" -eq "$base_rc" ] \
  && [ "$n_dead_applied" -eq 0 ] \
  && [ "$n_dead_ask" -ge 1 ]; then
  ok "a failing endpoint does not fail the multi-stage run"
else
  not "a failing endpoint does not fail the multi-stage run (rc=$dead_rc base=$base_rc applied=$n_dead_applied ask=$n_dead_ask err=$(head -c 400 "$DEAD/dispatch.err"))"
fi

if [ "$dead_rc" -eq "$base_rc" ] && [ "$n_ledger" -ge 1 ] \
  && { [ "$n_usage" -ge 1 ] || [ "$n_metric" -ge 1 ]; }; then
  ok "the ask never fails the multi-stage run"
else
  not "the ask never fails the multi-stage run (rc=$dead_rc ledger=$n_ledger usage=$n_usage metric=$n_metric err=$(head -c 400 "$DEAD/dispatch.err") out=$(head -c 200 "$DEAD/dispatch.out"))"
fi

echo
echo "test-supervisor-stages-ask: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
