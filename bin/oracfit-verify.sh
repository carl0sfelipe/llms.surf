#!/bin/bash
# oracfit verify — the orchestrator implements DIRECTLY, but the run still shows up in the panel and the ledger.
#
#   oracfit verify <spec> <task> --before    # the oracle must be RED; opens the run
#   (the orchestrator implements)
#   oracfit verify <spec> <task>             # runs the oracle, closes the run (pass/fail) in the ledger
#
# Why: delegating a small task to a paid executor costs more than doing it directly
# (docs/delegation-check.md §1, three runs on 2026-10-02) — but "direct" must not vanish from the panel.
# Same oracle, same proof, model_id "orchestrator", no round trip to any model.
# Exit: 0 pass · 1 fail · 2 oracle already green on --before · 3 usage.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-oracfit-root.sh"
source "$SCRIPT_DIR/lib-oracfit-events.sh"
source "$SCRIPT_DIR/lib-oracfit-metrics.sh"
source "$SCRIPT_DIR/lib-oracfit-gauntlet.sh"

usage() { echo "usage: oracfit verify <spec> <task> [--before]" >&2; exit 3; }
spec="${1:-}"; task="${2:-}"; phase="${3:-}"
[ -n "$spec" ] && [ -n "$task" ] || usage
[ -f "$spec" ] || { echo "verify: spec not found: $spec" >&2; exit 3; }
case "$phase" in ""|--before) ;; *) usage ;; esac

export ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
state_dir="$ORACFIT_WORKDIR/.dispatch/verify"
state="$state_dir/$task.json"
mkdir -p "$state_dir"
log="$state_dir/$task.oracle.log"

if [ "$phase" = "--before" ]; then
  oracfit_gauntlet_run_oracle_capture "$spec" "$ORACFIT_WORKDIR" "$log"
  rc=$?
  [ "$rc" -eq 3 ] && exit 3
  if [ "$rc" -eq 0 ]; then
    echo "verify: the oracle is ALREADY green before the work — it proves nothing. Make the oracle stricter." >&2
    exit 2
  fi
  RUN_ID="$(oracfit_mint_run_id)"; export ORACFIT_RUN_ID="$RUN_ID"
  oracfit_emit_event run_started mode=direct stage=run task="$task" model_id=orchestrator
  oracfit_emit_event oracle_result exit="$rc" attempt=0 command=from-spec
  python3 -c 'import json,sys,time; json.dump({"run_id": sys.argv[1], "t0": time.time(), "spec": sys.argv[2]}, open(sys.argv[3], "w"))' \
    "$RUN_ID" "$spec" "$state"
  echo "run_id: $RUN_ID"
  echo "oracle red (exit $rc) — implement, then run: oracfit verify $spec $task"
  exit 0
fi

[ -f "$state" ] || { echo "verify: no open run for '$task' — start with: oracfit verify $spec $task --before" >&2; exit 3; }
read -r RUN_ID t0 < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["run_id"], d["t0"])' "$state")
export ORACFIT_RUN_ID="$RUN_ID"
oracfit_gauntlet_run_oracle_capture "$spec" "$ORACFIT_WORKDIR" "$log"
rc=$?
oracfit_emit_event oracle_result exit="$rc" attempt=1 command=from-spec
status=fail; [ "$rc" -eq 0 ] && status=pass
wall_s=$(python3 -c "import time; print(round(time.time()-float('$t0'), 3))")
# The ledger requires estimated_cost; the orchestrator's own cost is not measured, so 0 is tagged as such.
oracfit_emit_metric_and_ledger mode_id=direct stage=run oracle_exit="$rc" attempt=1 model_id=orchestrator \
  flash_work_s="$wall_s" frontier_wait_s="$wall_s" estimated_cost=0 cost_source=orchestrator-unmeasured \
  task="$task" status="$status" runner=orchestrator
oracfit_emit_event run_finished status="$status" attempt=1 oracle_exit="$rc"
rm -f "$state"
echo "run_id: $RUN_ID"
echo "status: $status"
echo "oracle_exit: $rc"
[ "$status" = pass ] || { echo "--- oracle:"; tail -20 "$log"; exit 1; }
