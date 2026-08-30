# lib-oracfit-events.sh — append-only event envelope (AD-12..15)
# Source me: source lib-oracfit-events.sh

oracfit_workdir() {
  local dir="${ORACFIT_WORKDIR:-$PWD}"
  if [ -d "$dir" ]; then
    local wd
    wd="$(cd -P "$dir" 2>/dev/null && pwd -P)" || wd="$dir"
    echo "$wd"
  else
    echo "$dir"
  fi
}

oracfit_events_path() {
  local wd
  wd="$(oracfit_workdir)" || return 1
  echo "$wd/.dispatch/logs/events.jsonl"
}

oracfit_emit_event() {
  local type="$1"
  shift 2>/dev/null || true
  if [ -z "${ORACFIT_RUN_ID:-}" ]; then
    echo "ERROR: oracfit_emit_event: ORACFIT_RUN_ID is not set" >&2
    return 1
  fi
  if [ -z "$type" ]; then
    echo "ERROR: oracfit_emit_event: type argument is required" >&2
    return 1
  fi
  local wd events_file
  wd="$(oracfit_workdir)" || return 1
  events_file="$wd/.dispatch/logs/events.jsonl"
  mkdir -p "$(dirname "$events_file")"
  python3 -c "
import json, sys
from datetime import datetime, timezone
skip = {'v', 'ts', 'run_id', 'type'}
obj = {'v': 1, 'ts': datetime.now(timezone.utc).isoformat(), 'run_id': sys.argv[1], 'type': sys.argv[2]}
for arg in sys.argv[3:]:
    if '=' in arg:
        k, v = arg.split('=', 1)
        if k not in skip:
            obj[k] = v
json.dump(obj, sys.stdout, ensure_ascii=False)
print()
" "$ORACFIT_RUN_ID" "$type" "$@" >> "$events_file"

  # S9 (go-live): o grito da praia — estados terminais avisam o dono no
  # celular (opt-in via ORACFIT_NTFY_TOPIC; ver bin/oracfit-notify.sh).
  # Hook ÚNICO no funil: qualquer caminho que emita run_finished/owner_question
  # avisa, sem tocar os scripts de dispatch. Best-effort de verdade: falha de
  # rede nunca muda o exit de quem emitiu (regra 12: curl com teto interno;
  # regra 13: advisory desacoplado de validação/commit). Corpo terso — só
  # run_id/task/status; conteúdo do workdir não sai da máquina.
  case "$type" in
    run_finished|owner_question)
      local _notify _kv _n_status="" _n_task=""
      _notify="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/oracfit-notify.sh"
      for _kv in "$@"; do
        case "$_kv" in
          status=*) _n_status="${_kv#status=}" ;;
          task=*) _n_task="${_kv#task=}" ;;
        esac
      done
      [ -x "$_notify" ] && "$_notify" "$ORACFIT_RUN_ID" "$_n_task" "$_n_status" >/dev/null 2>&1 || true
      ;;
  esac
}

oracfit_inbox_dir() {
  local wd
  wd="$(oracfit_workdir)" || return 1
  echo "$wd/.dispatch/logs/inbox"
}

oracfit_inbox_file() {
  echo "$(oracfit_inbox_dir)/${1:?run_id required}.jsonl"
}

oracfit_interrupt_file() {
  echo "$(oracfit_inbox_dir)/${1:?run_id required}.interrupt"
}

oracfit_session_file() {
  echo "$(oracfit_inbox_dir)/${1:?run_id required}.opencode-session"
}

oracfit_mint_run_id() {
  local id
  id="$(uuidgen 2>/dev/null)" || id="$(python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null)" || {
    echo "ERROR: oracfit_mint_run_id: cannot generate UUID (need uuidgen or python3)" >&2
    return 1
  }
  export ORACFIT_RUN_ID="$id"
  echo "$id"
}
