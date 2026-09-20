# lib-oracfit-metrics.sh — single metric writer (AD-17, FR-8/FR-9)
# Source after lib-oracfit-events.sh. Requires ORACFIT_RUN_ID.

oracfit_ledger_path() {
  local wd
  wd="$(oracfit_workdir)"
  echo "$wd/.dispatch/ledger/mode.jsonl"
}

# oracfit_emit_metric_and_ledger key=val...
# Required semantic fields for FR-8: flash_work_s frontier_wait_s estimated_cost
# Also records mode_id stage oracle_exit attempt model_id into ledger row.
oracfit_emit_metric_and_ledger() {
  if [ -z "${ORACFIT_RUN_ID:-}" ]; then
    echo "ERROR: oracfit_emit_metric_and_ledger: ORACFIT_RUN_ID not set" >&2
    return 1
  fi
  local wd ledger
  wd="$(oracfit_workdir)"
  ledger="$(oracfit_ledger_path)"
  mkdir -p "$(dirname "$ledger")"

  # T18/T19 → ledger de modo: run-with-fallback deixa <efetivo>.kernel com
  # kernel_shadow_diff / policy_version_* quando LLMS_KERNEL=shadow|on. Sem o
  # sidecar (flag off) nenhuma chave entra — schema não enfraquece. Incidente
  # 2026-09-19 (E5, máquina do dono): 2 runs em shadow e o medidor lia
  # "no-shadow-traffic" porque o dado parava no sidecar.
  local sidecar kv
  sidecar="${DISPATCH_EFETIVO_FILE:-}"
  if [ -n "$sidecar" ] && [ -f "${sidecar%.efetivo}.kernel" ]; then
    while IFS= read -r kv || [ -n "$kv" ]; do
      case "$kv" in
        kernel_shadow_diff=?*|policy_version_crate=?*|policy_version_sha=?*) set -- "$@" "$kv" ;;
      esac
    done < "${sidecar%.efetivo}.kernel"
  fi

  # Event for panel (read-only consumers — AD-17)
  oracfit_emit_event metric "$@"

  # Append-only ledger row
  python3 -c "
import json, sys
from datetime import datetime, timezone
skip = {'v', 'ts', 'run_id', 'type'}
obj = {
  'v': 1,
  'ts': datetime.now(timezone.utc).isoformat(),
  'run_id': sys.argv[1],
  'mode_id': '',
  'stage': '',
  'oracle_exit': '',
  'attempt': '',
  'model_id': '',
  'flash_work_s': '',
  'frontier_wait_s': '',
  'estimated_cost': '',
}
for arg in sys.argv[2:]:
    if '=' in arg:
        k, v = arg.split('=', 1)
        if k not in skip:
            obj[k] = v
missing = [k for k in ('flash_work_s','frontier_wait_s','estimated_cost') if obj.get(k,'') == '']
if missing:
    print('ERROR: metric missing required fields: ' + ','.join(missing), file=sys.stderr)
    sys.exit(1)
json.dump(obj, sys.stdout, ensure_ascii=False)
print()
" "$ORACFIT_RUN_ID" "$@" >> "$ledger"
}
