#!/bin/bash
# tests/test-systemone-client.sh — System-One client, against a local stub.
# Hermetic: work files live under $TMPDIR. No network beyond 127.0.0.1, no
# model, no writes to the workdir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLIENT="$ROOT/bin/oracfit-systemone.py"
EXPORT="$ROOT/bin/oracfit-questions.py"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/systemone-client.XXXXXX")"
STUB_PID=""
trap 'if [ -n "${STUB_PID:-}" ]; then kill "$STUB_PID" 2>/dev/null || true; wait "$STUB_PID" 2>/dev/null || true; fi; rm -rf "$WORKDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() {
  set +e
  "$@" >"$WORKDIR/last.out" 2>"$WORKDIR/last.err"
  echo $?
  set -e
}

cat >"$WORKDIR/stub.py" <<'PY'
#!/usr/bin/env python3
"""Local System-One stub. Modes: ok, missing, error, garbage, slow."""
from __future__ import annotations

import argparse
import json
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from typing import Any

SLOW_SLEEP_S = 60


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
    parser.add_argument("--mode", required=True, choices=("ok", "missing", "error", "garbage", "slow"))
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
            if args.mode == "error":
                self._send(500, b"internal error", "text/plain")
                return
            if args.mode == "garbage":
                self._send(200, b"this is not json {{{", "text/plain")
                return
            if args.mode == "slow":
                time.sleep(SLOW_SLEEP_S)
            questions = parsed.get("questions") if isinstance(parsed, dict) else {}
            answers = answers_for(questions)
            if args.mode == "missing":
                keys = list(answers)
                if keys:
                    del answers[keys[0]]
            payload = {
                "answers": answers,
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
  local mode="$1"
  stop_stub
  rm -f "$WORKDIR/stub.port" "$WORKDIR/stub.request.json"
  python3 "$WORKDIR/stub.py" \
    --mode "$mode" \
    --port-file "$WORKDIR/stub.port" \
    --record "$WORKDIR/stub.request.json" \
    >"$WORKDIR/stub.log" 2>&1 &
  STUB_PID=$!
  if ! wait_port_file "$WORKDIR/stub.port"; then
    echo "  stub in mode $mode did not write a port file" >&2
    cat "$WORKDIR/stub.log" >&2 || true
    return 1
  fi
}

endpoint_url() {
  local port
  port="$(tr -d '[:space:]' < "$WORKDIR/stub.port")"
  printf 'http://127.0.0.1:%s/v1/systemone' "$port"
}

write_state() {
  cat >"$WORKDIR/state.json" <<'JSON'
{"round": 2, "oracle_exit": 1, "behavior_flags": ["B2"]}
JSON
}

write_small_questions() {
  cat >"$WORKDIR/questions.json" <<'JSON'
{
  "questions": {
    "angry": {
      "type": "noul",
      "instructions": "Is the owner angry?"
    },
    "route": {
      "type": "choice",
      "instructions": "Which route?",
      "criteria": {"a": "one", "b": "two"}
    }
  }
}
JSON
}

write_state
write_small_questions

echo "== 1. the client asks the System-One endpoint"
start_stub ok
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json" \
  --out "$WORKDIR/out-ok.json")"
if [ "$rc" -eq 0 ]; then
  ok "client exit 0 against stub ok"
else
  not "client exit 0 against stub ok (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi
if python3 - "$WORKDIR/stub.request.json" "$WORKDIR/state.json" <<'PY'
import json, sys
req = json.load(open(sys.argv[1], encoding="utf-8"))
state = json.load(open(sys.argv[2], encoding="utf-8"))
assert req["method"] == "POST", req.get("method")
assert req["content_type"] == "application/json", req.get("content_type")
body = req["body"]
assert isinstance(body, dict), body
assert "state" in body and "questions" in body, body.keys()
assert body["state"] == state, (body["state"], state)
assert "angry" in body["questions"] and "route" in body["questions"]
PY
then
  ok "stub received POST application/json with matching state"
else
  not "stub received POST application/json with matching state"
fi

echo "== 2. the question set composes with the client"
python3 "$EXPORT" export --asked-only >"$WORKDIR/asked.json"
start_stub ok
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/asked.json" \
  --state "$WORKDIR/state.json" \
  --out "$WORKDIR/out-asked.json")"
if [ "$rc" -eq 0 ]; then
  ok "client exit 0 on the asked-only export"
else
  not "client exit 0 on the asked-only export (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi
if python3 - "$WORKDIR/stub.request.json" "$WORKDIR/asked.json" <<'PY'
import json, sys
req = json.load(open(sys.argv[1], encoding="utf-8"))
exported = json.load(open(sys.argv[2], encoding="utf-8"))
body = req["body"]
got = body["questions"]
want = exported["questions"]
assert set(got) == set(want), (sorted(got), sorted(want))
assert len(got) == 26, len(got)
for qid, q in got.items():
    src = want[qid]
    assert q["type"] in ("noul", "choice", "score"), q
    assert "instructions" in q, qid
    if q["type"] == "noul":
        assert "criteria" not in q, qid
        assert set(q) == set(src)
    else:
        assert "criteria" in q, qid
        assert q["criteria"] == src["criteria"], qid
        if q["type"] == "choice":
            assert isinstance(q["criteria"], dict) and len(q["criteria"]) >= 2
        if q["type"] == "score":
            assert isinstance(q["criteria"], list) and len(q["criteria"]) >= 2
PY
then
  ok "request body has the 26 asked ids in the API shape"
else
  not "request body has the 26 asked ids in the API shape"
fi

echo "== 3. a noul answer is reported as an abstention mass"
start_stub ok
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json" \
  --ids angry \
  --out "$WORKDIR/out-noul.json")"
if [ "$rc" -eq 0 ]; then
  ok "noul ask exit 0"
else
  not "noul ask exit 0 (rc=$rc err=$(head -c 200 "$WORKDIR/last.err"))"
fi
if python3 - "$WORKDIR/last.out" "$WORKDIR/out-noul.json" <<'PY'
import json, sys
line = open(sys.argv[1], encoding="utf-8").read().splitlines()[0]
parts = line.split("  ")
assert parts[0] == "angry", parts
assert parts[1] == "0.83", parts
assert parts[2] == "\u2014", parts
record = json.load(open(sys.argv[2], encoding="utf-8"))
answer = record["answers"]["angry"]
assert answer == {"type": "noul", "noul": 0.83}, answer
assert set(answer) == {"type", "noul"}
PY
then
  ok "stdout shows the mass and the file keeps the raw noul answer"
else
  not "stdout shows the mass and the file keeps the raw noul answer"
fi

echo "== 4. the client writes no decision"
FAKE_WD="$WORKDIR/fake-workdir"
mkdir -p "$FAKE_WD"
before="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
start_stub ok
EP="$(endpoint_url)"
rc="$(
  set +e
  (
    cd "$FAKE_WD"
    python3 "$CLIENT" ask \
      --endpoint "$EP" \
      --questions "$WORKDIR/questions.json" \
      --state "$WORKDIR/state.json" \
      --out "$WORKDIR/out-nodecision.json"
  ) >"$WORKDIR/last.out" 2>"$WORKDIR/last.err"
  echo $?
  set -e
)"
after="$(find "$FAKE_WD" -mindepth 1 | wc -l)"
if [ "$rc" -eq 0 ] && [ "$before" -eq 0 ] && [ "$after" -eq 0 ]; then
  ok "client wrote nothing in the workdir"
else
  not "client wrote nothing in the workdir (rc=$rc before=$before after=$after)"
fi
if python3 - "$WORKDIR/out-nodecision.json" <<'PY'
import json, sys
record = json.load(open(sys.argv[1], encoding="utf-8"))
banned = ("decision", "verdict", "action")

def walk(obj):
    if isinstance(obj, dict):
        for key, value in obj.items():
            low = str(key).lower()
            for word in banned:
                if word in low:
                    raise SystemExit(f"banned key {key!r}")
            walk(value)
    elif isinstance(obj, list):
        for item in obj:
            walk(item)

walk(record)
assert set(record) == {"endpoint", "requested_at", "questions", "answers", "usage"}
PY
then
  ok "output file has no decision/verdict/action key"
else
  not "output file has no decision/verdict/action key"
fi

echo "== 5. a missing answer is an error"
start_stub missing
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json" \
  --out "$WORKDIR/out-missing.json")"
if [ "$rc" -eq 1 ] && grep -q "angry" "$WORKDIR/last.err"; then
  ok "missing answer exits 1 and names the id"
else
  not "missing answer exits 1 and names the id (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 6. a server error is an error"
start_stub error
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json")"
if [ "$rc" -eq 1 ] && grep -q "500" "$WORKDIR/last.err"; then
  ok "HTTP 500 exits 1 and names the code"
else
  not "HTTP 500 exits 1 and names the code (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 7. a malformed answer is an error"
start_stub garbage
EP="$(endpoint_url)"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json")"
if [ "$rc" -eq 1 ]; then
  ok "malformed body exits 1"
else
  not "malformed body exits 1 (rc=$rc err=$(head -c 240 "$WORKDIR/last.err"))"
fi

echo "== 8. the request has a time ceiling"
start_stub slow
EP="$(endpoint_url)"
if python3 - "$CLIENT" "$EP" "$WORKDIR/questions.json" "$WORKDIR/state.json" <<'PY'
import subprocess, sys, time
client, endpoint, questions, state = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
cmd = [
    "python3", client, "ask",
    "--endpoint", endpoint,
    "--questions", questions,
    "--state", state,
    "--timeout", "1",
]
t0 = time.monotonic()
try:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
except subprocess.TimeoutExpired:
    raise SystemExit("client did not return before the suite ceiling")
elapsed = time.monotonic() - t0
if proc.returncode != 1:
    raise SystemExit(f"expected exit 1, got {proc.returncode}: {proc.stderr}")
if elapsed >= 5:
    raise SystemExit(f"elapsed {elapsed:.2f}s reached the suite ceiling")
text = (proc.stderr or "").lower()
if "ceiling" not in text and "exceeded" not in text:
    raise SystemExit(f"stderr did not say the ceiling was exceeded: {proc.stderr!r}")
print(f"elapsed={elapsed:.2f}s")
PY
then
  ok "timeout exits 1 before the suite ceiling"
else
  not "timeout exits 1 before the suite ceiling"
fi

echo "== 9. an unknown id is a usage error"
start_stub ok
EP="$(endpoint_url)"
rm -f "$WORKDIR/stub.request.json"
rc="$(rc_of python3 "$CLIENT" ask \
  --endpoint "$EP" \
  --questions "$WORKDIR/questions.json" \
  --state "$WORKDIR/state.json" \
  --ids does-not-exist)"
if [ "$rc" -eq 3 ] && [ ! -f "$WORKDIR/stub.request.json" ]; then
  ok "unknown id exits 3 without calling the stub"
else
  not "unknown id exits 3 without calling the stub (rc=$rc called=$([ -f "$WORKDIR/stub.request.json" ] && echo yes || echo no) err=$(head -c 200 "$WORKDIR/last.err"))"
fi

stop_stub

echo
echo "test-systemone-client: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
