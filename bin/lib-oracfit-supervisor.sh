# lib-oracfit-supervisor.sh — apply a supervisor order at the attempt boundary.
# Source me. Public: oracfit_supervisor_apply_order <workdir> <accum> <run_id> <attempt>
#
# The policy writes the order; this library is who executes it. CONTINUE is a
# no-op. INJECT_HINT writes the hint on the accumulator the next attempt
# composes into the spec. RESET snapshots the dirty tree, restores the
# changed tracked files from HEAD, and writes the scar plus the hint.
# ESCALATE is refused: nothing is executed by half, and the reason is visible.

if ! declare -F oracfit_wip_snapshot >/dev/null 2>&1; then
  # shellcheck source=bin/oracfit-wip-snapshot.sh
  . "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/oracfit-wip-snapshot.sh"
fi

_oracfit_supervisor_one_line() {
  printf '%s' "${1-}" | tr '\r\n\t' '   '
}

# Same globs file the restore already chooses (not a second list):
# <workdir>/.oracfit-protected wins; the default list only applies when the
# workdir is this checkout.
_oracfit_supervisor_protected_globs_file() {
  local wd="$1" root=""
  if [ -f "$wd/.oracfit-protected" ]; then
    printf '%s\n' "$wd/.oracfit-protected"
    return 0
  fi
  root="$(oracfit_resolve_root 2>/dev/null)" || root=""
  if [ -n "$root" ] && [ "$root" = "$wd" ] && [ -f "$root/core/protected-paths-default.txt" ]; then
    printf '%s\n' "$root/core/protected-paths-default.txt"
  fi
}

# Five lines on stdout: result, reason, ref, sha, restored count. Always returns 0.
_oracfit_supervisor_reset_emit() {
  printf '%s\n' "$1"
  printf '%s\n' "$(_oracfit_supervisor_one_line "$2")"
  printf '%s\n' "$3"
  printf '%s\n' "$4"
  printf '%s\n' "$5"
}

# RESET: evidence, target, restore from HEAD, scar. A refusal leaves the tree
# as it was (the snapshot, if it ran, is additive and is never deleted).
_oracfit_supervisor_reset() {
  local workdir="${1:-}" accum="${2:-}" run_id="${3:-}" attempt="${4:-}" path="${5:-}"
  local success_reason="${6:-reset}"
  local hint="" ref_name="" snap_sha="" snap_rc=0 restored_count=0
  local wd="" globs="" p rel in_head scar parent=""
  local restore_out="" restore_rc=0 snap_err="" restore_err=""
  local -a targets=()

  [ -n "$success_reason" ] || success_reason="reset"
  ref_name="$(oracfit_wip_ref_name "$run_id" "$attempt")"

  hint="$(python3 - "$path" <<'PY'
import json
import sys

path = sys.argv[1]
try:
    rec = json.load(open(path, encoding="utf-8"))
except (OSError, ValueError):
    raise SystemExit(0)
order = rec.get("order") if isinstance(rec.get("order"), dict) else {}
hint = order.get("hint") if isinstance(order.get("hint"), str) else ""
if not hint.strip():
    raise SystemExit(0)
sys.stdout.write(hint.rstrip())
PY
)"
  if [ -z "$hint" ]; then
    echo "supervisor: RESET order has no hint" >&2
    _oracfit_supervisor_reset_emit refused "RESET order has no hint" "$ref_name" "" 0
    return 0
  fi

  snap_err="$(mktemp "${TMPDIR:-/tmp}/oracfit-sup-snap.XXXXXX")" || {
    echo "supervisor: snapshot failed" >&2
    _oracfit_supervisor_reset_emit refused "snapshot failed" "$ref_name" "" 0
    return 0
  }
  snap_sha="$(oracfit_wip_snapshot "$workdir" "$run_id" "$attempt" 2>"$snap_err")"
  snap_rc=$?
  rm -f "$snap_err"
  if [ "$snap_rc" -ne 0 ] || [ -z "$snap_sha" ]; then
    if [ "$snap_rc" -eq 0 ]; then
      echo "supervisor: nothing to snapshot" >&2
      _oracfit_supervisor_reset_emit refused "nothing to snapshot" "$ref_name" "" 0
    else
      echo "supervisor: snapshot failed" >&2
      _oracfit_supervisor_reset_emit refused "snapshot failed" "$ref_name" "" 0
    fi
    return 0
  fi

  wd="$(CDPATH='' cd -P -- "$workdir" && pwd -P)" || wd="$workdir"
  globs="$(_oracfit_supervisor_protected_globs_file "$wd")"
  while IFS= read -r p || [ -n "$p" ]; do
    [ -n "$p" ] || continue
    if ! rel="$(_oracfit_wip_normalize_path "$p")"; then
      continue
    fi
    if _oracfit_wip_protected_glob "$rel" "$globs" >/dev/null; then
      continue
    fi
    in_head="$(git --git-dir="$wd/.git" --work-tree="$wd" --literal-pathspecs \
      ls-tree --name-only HEAD -- "$rel" 2>/dev/null)" || in_head=""
    [ -n "$in_head" ] || continue
    targets+=("$rel")
  done < <(
    {
      git --git-dir="$wd/.git" --work-tree="$wd" --no-optional-locks diff --name-only HEAD --
      git --git-dir="$wd/.git" --work-tree="$wd" --no-optional-locks diff --name-only --cached HEAD --
    } 2>/dev/null | LC_ALL=C sort -u
  )

  if [ "${#targets[@]}" -gt 0 ]; then
    restore_err="$(mktemp "${TMPDIR:-/tmp}/oracfit-sup-restore.XXXXXX")" || {
      echo "supervisor: restore refused, nothing restored" >&2
      _oracfit_supervisor_reset_emit refused "restore refused" "$ref_name" "$snap_sha" 0
      return 0
    }
    restore_out="$(oracfit_wip_restore "$workdir" HEAD "${targets[@]}" 2>"$restore_err")"
    restore_rc=$?
    rm -f "$restore_err"
    if [ "$restore_rc" -ne 0 ]; then
      echo "supervisor: restore refused, nothing restored" >&2
      _oracfit_supervisor_reset_emit refused "restore refused" "$ref_name" "$snap_sha" 0
      return 0
    fi
    restored_count=0
    if [ -n "$restore_out" ]; then
      restored_count="$(printf '%s\n' "$restore_out" | grep -c . || true)"
    fi
  fi

  scar="$(oracfit_wip_scar_line "$run_id" "$attempt" "$ref_name")"
  parent="$(dirname "$accum")"
  if [ -n "$parent" ] && ! mkdir -p "$parent"; then
    echo "supervisor: could not write scar" >&2
    _oracfit_supervisor_reset_emit refused "could not write scar" "$ref_name" "$snap_sha" "$restored_count"
    return 0
  fi
  if ! {
    printf '\n'
    printf '%s\n' "## SUPERVISOR ORDER (attempt ${attempt}) — apply this hint before resubmitting"
    printf '\n'
    printf '%s\n' "$scar"
    printf '\n'
    printf '%s\n' "$hint"
  } >>"$accum"; then
    echo "supervisor: could not write scar" >&2
    _oracfit_supervisor_reset_emit refused "could not write scar" "$ref_name" "$snap_sha" "$restored_count"
    return 0
  fi

  _oracfit_supervisor_reset_emit applied "$success_reason" "$ref_name" "$snap_sha" "$restored_count"
  return 0
}

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
  local ref_name=""
  local snap_sha=""
  local restored_count=0
  local reset_parsed=""

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

if action == "ESCALATE":
    refuse(
        action,
        "action is not executable on this rung",
        action + " is not executable on this rung",
    )
    raise SystemExit(0)

order = rec.get("order") if isinstance(rec.get("order"), dict) else {}
hint = order.get("hint") if "hint" in order else None
if not isinstance(hint, str) or not hint.strip():
    refuse(action, action + " order has no hint", action + " order has no hint")
    raise SystemExit(0)

if action == "RESET":
    emit(action, "execute", record_reason or "reset")
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

  if [ "$action" = "RESET" ] && [ "$result" != "refused" ]; then
    reset_parsed="$(_oracfit_supervisor_reset "$workdir" "$accum" "$run_id" "$attempt" "$path" "$reason")"
    if [ -n "$reset_parsed" ]; then
      result="$(printf '%s\n' "$reset_parsed" | sed -n '1p')"
      reason="$(printf '%s\n' "$reset_parsed" | sed -n '2p')"
      ref_name="$(printf '%s\n' "$reset_parsed" | sed -n '3p')"
      snap_sha="$(printf '%s\n' "$reset_parsed" | sed -n '4p')"
      restored_count="$(printf '%s\n' "$reset_parsed" | sed -n '5p')"
    else
      result="refused"
      reason="snapshot failed"
    fi
    [ -n "$restored_count" ] || restored_count=0
  fi
  if [ "$result" = "execute" ]; then
    result="refused"
    reason="snapshot failed"
  fi

  if [ "$action" = "RESET" ]; then
    printf 'supervisor_order action=%s attempt=%s result=%s reason=%s ref=%s sha=%s restored=%s\n' \
      "$action" "$attempt" "$result" "$reason" "$ref_name" "$snap_sha" "$restored_count"
  else
    printf 'supervisor_order action=%s attempt=%s result=%s reason=%s\n' \
      "$action" "$attempt" "$result" "$reason"
  fi

  if command -v oracfit_emit_event >/dev/null 2>&1; then
    if [ "$action" = "RESET" ]; then
      ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$workdir}" \
        ORACFIT_RUN_ID="${ORACFIT_RUN_ID:-$run_id}" \
        oracfit_emit_event supervisor_order \
          attempt="$attempt" action="$action" result="$result" reason="$reason" \
          ref="$ref_name" sha="$snap_sha" restored="$restored_count" || true
    else
      ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$workdir}" \
        ORACFIT_RUN_ID="${ORACFIT_RUN_ID:-$run_id}" \
        oracfit_emit_event supervisor_order \
          attempt="$attempt" action="$action" result="$result" reason="$reason" || true
    fi
  fi

  [ "$restore_e" -eq 1 ] && set -e
  return 0
}
