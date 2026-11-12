#!/bin/bash
# lib-oracfit-rate-limit.sh — the throttle a mode declares, kept by the runtime.
#
# `rate_limit_s: N` used to be a promise nobody kept: the loader demanded it
# on a `map` stage, the catalog documented it as "pause between attempts",
# and neither dispatcher had a single `sleep` in it. A mode could declare a
# throttle and hammer the provider anyway.
#
# What lives here:
#   oracfit_rate_limit_gate <seconds> <label> <interrupt_file> <key>...
#     waits until the declared pause has passed since the last dispatch of
#     those keys; returns 1 when a human interrupt ended the wait
#   oracfit_rate_limit_record_call <key>...
#     stamps every key with the current epoch (call it when the dispatch ends)
#   oracfit_rate_limit_last_call <key>
#     the epoch of the last dispatch of a key, or "" when it never ran
#
# The pause is measured from the END of the previous dispatch to the START
# of the next one. That is the strictest reading of both words: at least N
# seconds of pause between two attempts, and at least N seconds between two
# requests to the same provider.
#
# The pause is bounded (rule 12: no command without a ceiling), visible on
# stderr and in events.jsonl, and it never outlives a human interrupt.

# Ceiling for a single wait. The loader refuses a larger rate_limit_s, and
# this caps a hand-edited YAML that slipped past the loader. Keep the number
# in sync with RATE_LIMIT_MAX_S in bin/lib-oracfit-mode-loader.py — the
# mechanism test compares the two.
ORACFIT_RATE_LIMIT_MAX_S="${ORACFIT_RATE_LIMIT_MAX_S:-3600}"

# The ledger of the last dispatch per key, as "key epoch" lines. It lives in
# the process, not in a file: a control file of the orchestrator never goes
# to the dispatched workdir (rule 47).
ORACFIT_RATE_LIMIT_CALLS=""

# The epoch of the last dispatch of a key, or "" when it never ran.
oracfit_rate_limit_last_call() {
  local key="${1:-}" line best=""
  if [ -z "$key" ]; then
    printf '%s' "$best"
    return 0
  fi
  while IFS= read -r line; do
    case "$line" in
      "$key "*)
        best="${line#* }"
        ;;
    esac
  done <<EOF
$ORACFIT_RATE_LIMIT_CALLS
EOF
  printf '%s' "$best"
}

# Record the end of a dispatch for every given key.
oracfit_rate_limit_record_call() {
  local epoch line out="" key drop
  epoch="$(date +%s)"
  # Drop the lines of the keys being recorded, so a key is stamped once.
  while IFS= read -r line; do
    drop=false
    for key in "$@"; do
      if [ -z "$key" ]; then
        continue
      fi
      case "$line" in
        "$key "*) drop=true; break ;;
      esac
    done
    if [ "$drop" = true ]; then
      continue
    fi
    if [ -z "$line" ]; then
      continue
    fi
    out="${out}${line}"$'\n'
  done <<EOF
$ORACFIT_RATE_LIMIT_CALLS
EOF
  for key in "$@"; do
    if [ -z "$key" ]; then
      continue
    fi
    out="${out}${key} ${epoch}"$'\n'
  done
  ORACFIT_RATE_LIMIT_CALLS="$out"
}

# oracfit_rate_limit_gate <seconds> <label> <interrupt_file> <key>...
#
# Waits until the declared pause has passed since the last dispatch of the
# given keys. The keys are what the pause is measured against:
#   "model:<model_ref>"  -> two calls to the same model, anywhere in the run
#   "stage:<index>"      -> two attempts of the same stage
#
# The wait is the longest gap any key asks for. A stage that declares no
# throttle passes 0 seconds and the gate is a no-op (it still records when
# the call happened, so a later stage that does declare a throttle measures
# the pause against the real last call).
#
# Returns 1 when a human interrupt arrived while waiting (the caller decides
# what to do with it); 0 when the wait completed.
oracfit_rate_limit_gate() {
  local seconds="${1:-0}" label="${2:-run}" interrupt_file="${3:-}"
  shift 3 2>/dev/null || shift $# 2>/dev/null || true
  case "$seconds" in
    ''|*[!0-9]*) seconds=0 ;;
  esac
  if [ "$seconds" -gt "$ORACFIT_RATE_LIMIT_MAX_S" ]; then
    seconds="$ORACFIT_RATE_LIMIT_MAX_S"
  fi

  local now last elapsed gap remaining=0 key
  now="$(date +%s)"
  for key in "$@"; do
    if [ -z "$key" ]; then
      continue
    fi
    last="$(oracfit_rate_limit_last_call "$key")"
    if [ -z "$last" ]; then
      continue
    fi
    elapsed=$((now - last))
    if [ "$elapsed" -lt 0 ]; then
      elapsed=0
    fi
    gap=$((seconds - elapsed))
    if [ "$gap" -gt "$remaining" ]; then
      remaining="$gap"
    fi
  done

  if [ "$remaining" -gt 0 ]; then
    echo "RATE LIMIT: waiting ${remaining}s before $label" >&2
    if command -v oracfit_emit_event >/dev/null 2>&1 && [ -n "${ORACFIT_RUN_ID:-}" ]; then
      oracfit_emit_event rate_limit_wait seconds="$remaining" label="$label" || true
    fi
    local chunk
    while [ "$remaining" -gt 0 ]; do
      if [ -n "$interrupt_file" ] && [ -f "$interrupt_file" ]; then
        echo "RATE LIMIT: wait interrupted before $label" >&2
        if command -v oracfit_emit_event >/dev/null 2>&1 && [ -n "${ORACFIT_RUN_ID:-}" ]; then
          oracfit_emit_event rate_limit_interrupted label="$label" || true
        fi
        return 1
      fi
      chunk="$remaining"
      if [ "$chunk" -gt 1 ]; then
        chunk=1
      fi
      sleep "$chunk"
      remaining=$((remaining - chunk))
    done
  fi
  return 0
}
