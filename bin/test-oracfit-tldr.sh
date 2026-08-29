#!/bin/bash
# test-oracfit-tldr.sh — automated TL;DR ≤3 commands (Story 1.8 / FR-10)
# Uses stub runner (no OpenRouter). Exit 0 = onboarding path OK.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "── Oracfit TL;DR smoke (≤3 commands) ──"

# Command 1: point at core + stub runner (no model network)
export ORACFIT_ROOT="$ROOT"
export DISPATCH_RUNNER="$ROOT/adapters/stub/runner.sh"
export ORACFIT_WORKDIR="$ROOT"
# ensure clean proof file
rm -f "$ROOT/.dispatch/stub-proof"

# Command 2: first successful normal
"$ROOT/bin/dispatch-mode.sh" normal "$ROOT/tests/fixtures/oracfit-smoke-normal.md" first-proof

# Command 3: panel serves (Epic 2) — start, curl, stop
echo "── step 3 panel ──"
PORT=18766
python3 "$ROOT/bin/oracfit-panel-server.py" \
  --panel-dir "$ROOT/panel" \
  --logs-dir "$ROOT/.dispatch/logs" \
  --port "$PORT" \
  --bind 127.0.0.1 &
PANEL_PID=$!
cleanup_panel() { kill "$PANEL_PID" 2>/dev/null || true; wait "$PANEL_PID" 2>/dev/null || true; }
trap cleanup_panel EXIT
for i in 1 2 3 4 5 6 7 8 9 10; do
  curl -sf "http://127.0.0.1:$PORT/" >/dev/null 2>&1 && break
  sleep 0.2
done
curl -sf "http://127.0.0.1:$PORT/" | grep -q "Oracfit — Carlos Felipe"
curl -sf "http://127.0.0.1:$PORT/logs/events.jsonl" | grep -q run_id
cleanup_panel
trap - EXIT
echo "── panel step green ──"

# Proof
test -f "$ROOT/.dispatch/logs/events.jsonl"
test -f "$ROOT/.dispatch/ledger/mode.jsonl"
grep -q '"type": "metric"' "$ROOT/.dispatch/logs/events.jsonl" || grep -q '"type":"metric"' "$ROOT/.dispatch/logs/events.jsonl"
grep -q stub_ok "$ROOT/.dispatch/stub-proof"

echo "✅ TL;DR smoke PASS (3 commands incl. panel)"
exit 0
