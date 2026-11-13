# lib-oracfit-supervisor.sh — apply a supervisor order at the attempt boundary.
# Source me. Public: oracfit_supervisor_apply_order <workdir> <accum> <run_id> <attempt>
#
# The policy writes the order; this library is who executes it. This rung
# executes INJECT_HINT (the hint goes on the accumulator the next attempt
# composes into the spec). CONTINUE is a no-op. RESET and ESCALATE are
# refused: nothing is executed by half, and the reason is visible.

# Apply the order in ORACFIT_SUPERVISOR_DECISION. Always returns 0.
oracfit_supervisor_apply_order() {
  local workdir="${1:-}"
  local accum="${2:-}"
  local run_id="${3:-}"
  local attempt="${4:-}"
  local action="CONTINUE"
  local result="noop"
  local reason="no decision record"
  local path="${ORACFIT_SUPERVISOR_DECISION:-}"
  local parsed=""
  local restore_e=0

  case "$-" in
    *e*) set +e; restore_e=1 ;;
  esac

  if [ -n "$path" ] && [ -f "$path" ]; then
    parsed="$(python3 - "$accum" "$attempt" "$path" <<'PY'
import json
import os
import sys

accum, attempt, path = sys.argv[1], sys.argv[2], sys.argv[3]
KNOWN = ("CONTINUE", "INJECT_HINT", "RESET", "ESCALATE")


def emit(action, result, reason, err=""):
    if err:
        print("supervisor: " + err, file=sys.stderr)
    def one_line(value):
        return str(value).replace("\r", " ").replace("\n", " ").replace("\t", " ")
    sys.stdout.write(one_line(action) + "\n")
    sys.stdout.write(one_line(result) + "\n")
    sys.stdout.write(one_line(reason) + "\n")


def refuse(action, reason, err):
    emit(action, "refused", reason, err)


try:
    with open(path, encoding="utf-8") as fh:
        raw = fh.read()
except OSError as exc:
    refuse("", "unreadable decision record", "unreadable decision record: " + str(exc))
    raise SystemExit(0)

try:
    rec = json.loads(raw)
except ValueError:
    refuse("", "invalid JSON", "decision record is not valid JSON")
    raise SystemExit(0)

if not isinstance(rec, dict) or "decision" not in rec:
    refuse("", "missing decision key", "decision record has no decision key")
    raise SystemExit(0)

decision = rec.get("decision")
if not isinstance(decision, str) or not decision.strip():
    refuse("", "missing decision key", "decision record has no decision key")
    raise SystemExit(0)

action = decision.strip()
record_reason = rec.get("reason")
if not isinstance(record_reason, str):
    record_reason = ""
record_reason = record_reason.strip()

if action not in KNOWN:
    refuse(action, "unknown action", "unknown action: " + action)
    raise SystemExit(0)

if action == "CONTINUE":
    emit(action, "noop", record_reason or "continue")
    raise SystemExit(0)

if action in ("RESET", "ESCALATE"):
    refuse(
        action,
        "action is not executable on this rung",
        action + " is not executable on this rung",
    )
    raise SystemExit(0)

order = rec.get("order") if isinstance(rec.get("order"), dict) else {}
hint = order.get("hint") if "hint" in order else None
if not isinstance(hint, str) or not hint.strip():
    refuse(action, "INJECT_HINT order has no hint", "INJECT_HINT order has no hint")
    raise SystemExit(0)

try:
    parent = os.path.dirname(accum)
    if parent:
        os.makedirs(parent, exist_ok=True)
    with open(accum, "a", encoding="utf-8") as fh:
        fh.write("\n")
        fh.write(
            "## SUPERVISOR ORDER (attempt %s) — apply this hint before resubmitting\n"
            % attempt
        )
        fh.write("\n")
        fh.write(hint.rstrip() + "\n")
except OSError as exc:
    refuse(action, "could not write hint", "could not write hint: " + str(exc))
    raise SystemExit(0)

emit(action, "applied", record_reason or "injected hint")
PY
)"
    if [ -n "$parsed" ]; then
      action="$(printf '%s\n' "$parsed" | sed -n '1p')"
      result="$(printf '%s\n' "$parsed" | sed -n '2p')"
      reason="$(printf '%s\n' "$parsed" | sed -n '3p')"
    else
      action=""
      result="refused"
      reason="unreadable decision record"
      echo "supervisor: unreadable decision record" >&2
    fi
  elif [ -n "$path" ] && [ ! -f "$path" ]; then
    action="CONTINUE"
    result="noop"
    reason="no decision record"
  fi

  printf 'supervisor_order action=%s attempt=%s result=%s reason=%s\n' \
    "$action" "$attempt" "$result" "$reason"

  if command -v oracfit_emit_event >/dev/null 2>&1; then
    ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$workdir}" \
      ORACFIT_RUN_ID="${ORACFIT_RUN_ID:-$run_id}" \
      oracfit_emit_event supervisor_order \
        attempt="$attempt" action="$action" result="$result" reason="$reason" || true
  fi

  [ "$restore_e" -eq 1 ] && set -e
  return 0
}
