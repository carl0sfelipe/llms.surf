# lib-oracfit-supervisor-ask.sh — ask the supervisor at the attempt boundary.
# Source me. Public:
#
#   oracfit_supervisor_ask_order <workdir> <run_id> <attempt> <state_file> [policy]
#
# Both runtimes write the round's state (the fields differ per runtime) and
# call this. This function reads the mapped question ids from the policy
# `rules` object, calls the ask chain with those ids, and never fails the
# run. It does not write the workdir, touch the ledger, apply an order, or
# decide.

_ORACFIT_SUPERVISOR_ASK_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_ORACFIT_SUPERVISOR_ASK_ROOT="$(cd "$_ORACFIT_SUPERVISOR_ASK_BIN/.." && pwd)"

_oracfit_supervisor_ask_ids() {
  python3 - "$1" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    doc = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(0)
if not isinstance(doc, dict):
    raise SystemExit(0)
rules = doc.get("rules")
if not isinstance(rules, dict) or not rules:
    raise SystemExit(0)
ids = [str(key) for key in rules if str(key).strip()]
if ids:
    sys.stdout.write(",".join(ids))
PY
}

# Always returns 0. On success, prints the decision record path. Without an
# endpoint, prints "no endpoint". A failed ask emits supervisor_ask and
# prints nothing.
oracfit_supervisor_ask_order() {
  local workdir="${1:-}"
  local run_id="${2:-}"
  local attempt="${3:-}"
  local state_file="${4:-}"
  local policy="${5:-}"
  local endpoint="${ORACFIT_SUPERVISOR_ENDPOINT:-}"
  local timeout="${ORACFIT_SUPERVISOR_TIMEOUT:-20}"
  local inbox=""
  local out=""
  local ids=""
  local ask_rc=0
  local ask_err=""
  local ask_reason=""
  local record=""

  if [ -z "$endpoint" ]; then
    printf '%s\n' "no endpoint"
    return 0
  fi

  if [ -z "$policy" ]; then
    policy="${ORACFIT_SUPERVISOR_POLICY:-}"
  fi
  if [ -z "$policy" ]; then
    policy="${_ORACFIT_SUPERVISOR_ASK_ROOT}/core/supervisor/policy.json"
  fi

  ids="$(_oracfit_supervisor_ask_ids "$policy" 2>/dev/null || true)"
  if [ -z "$ids" ]; then
    return 0
  fi

  inbox="${workdir}/.dispatch/logs/inbox"
  out="${inbox}/${run_id}.json"
  mkdir -p "$inbox" 2>/dev/null || true

  ask_err="$(mktemp "${TMPDIR:-/tmp}/oracfit-supervisor-ask.XXXXXX.err")" || ask_err=""
  record="$("$_ORACFIT_SUPERVISOR_ASK_BIN/oracfit-supervisor-ask.sh" \
    --endpoint "$endpoint" \
    --state "$state_file" \
    --out "$out" \
    --policy "$policy" \
    --timeout "$timeout" \
    --ids "$ids" \
    2>"${ask_err:-/dev/null}")" || ask_rc=$?

  if [ "$ask_rc" -eq 0 ] && [ -n "$record" ] && [ -f "$record" ]; then
    [ -n "$ask_err" ] && [ -f "$ask_err" ] && rm -f "$ask_err"
    printf '%s\n' "$record"
    return 0
  fi

  if [ -n "$ask_err" ] && [ -f "$ask_err" ]; then
    ask_reason="$(tr '\r\n\t' '   ' < "$ask_err" 2>/dev/null | cut -c1-200)"
    rm -f "$ask_err"
  fi
  [ -n "$ask_reason" ] || ask_reason="ask failed"
  if declare -F oracfit_emit_event >/dev/null 2>&1; then
    oracfit_emit_event supervisor_ask result=failed reason="$ask_reason" attempt="$attempt" || true
  fi
  return 0
}
