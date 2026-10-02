#!/bin/bash
# oracfit verificar — o orquestrador implementa DIRETO, mas o run continua no painel e no ledger.
#
#   oracfit verificar <spec> <task> --antes    # oráculo tem de estar VERMELHO; abre o run
#   (o orquestrador implementa)
#   oracfit verificar <spec> <task>            # roda o oráculo, fecha o run (pass/fail) no ledger
#
# Por quê: delegar tarefa pequena a executor pago custa mais que fazer direto
# (docs/proposta-check-delegacao.md §1, 3 runs de 2026-10-02) — mas "direto" não pode sumir do
# painel (regra do dono, 2026-09-29). Mesmo oráculo, mesma prova, model_id "orquestrador",
# sem ida e volta a modelo nenhum. Exit: 0 pass · 1 fail · 2 oráculo já verde no --antes · 3 uso.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-oracfit-root.sh"
source "$SCRIPT_DIR/lib-oracfit-events.sh"
source "$SCRIPT_DIR/lib-oracfit-metrics.sh"
source "$SCRIPT_DIR/lib-oracfit-gauntlet.sh"

uso() { echo "uso: oracfit verificar <spec> <task> [--antes]" >&2; exit 3; }
spec="${1:-}"; task="${2:-}"; fase="${3:-}"
[ -n "$spec" ] && [ -n "$task" ] || uso
[ -f "$spec" ] || { echo "verificar: spec não encontrada: $spec" >&2; exit 3; }
case "$fase" in ""|--antes) ;; *) uso ;; esac

export ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
estado_dir="$ORACFIT_WORKDIR/.dispatch/verificar"
estado="$estado_dir/$task.json"
mkdir -p "$estado_dir"
log="$estado_dir/$task.oracle.log"

if [ "$fase" = "--antes" ]; then
  oracfit_gauntlet_run_oracle_capture "$spec" "$ORACFIT_WORKDIR" "$log"
  rc=$?
  [ "$rc" -eq 3 ] && exit 3
  if [ "$rc" -eq 0 ]; then
    echo "verificar: o oráculo JÁ está verde antes de implementar — ele não prova nada. Endureça o oráculo." >&2
    exit 2
  fi
  RUN_ID="$(oracfit_mint_run_id)"; export ORACFIT_RUN_ID="$RUN_ID"
  oracfit_emit_event run_started mode=direto stage=run task="$task" model_id=orquestrador
  oracfit_emit_event oracle_result exit="$rc" attempt=0 command=from-spec
  python3 -c 'import json,sys,time; json.dump({"run_id": sys.argv[1], "t0": time.time(), "spec": sys.argv[2]}, open(sys.argv[3], "w"))' \
    "$RUN_ID" "$spec" "$estado"
  echo "run_id: $RUN_ID"
  echo "oráculo vermelho (exit $rc) — implemente e rode: oracfit verificar $spec $task"
  exit 0
fi

[ -f "$estado" ] || { echo "verificar: nenhum run aberto para '$task' — comece com: oracfit verificar $spec $task --antes" >&2; exit 3; }
read -r RUN_ID t0 < <(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["run_id"], d["t0"])' "$estado")
export ORACFIT_RUN_ID="$RUN_ID"
oracfit_gauntlet_run_oracle_capture "$spec" "$ORACFIT_WORKDIR" "$log"
rc=$?
oracfit_emit_event oracle_result exit="$rc" attempt=1 command=from-spec
status=fail; [ "$rc" -eq 0 ] && status=pass
wall_s=$(python3 -c "import time; print(round(time.time()-float('$t0'), 3))")
oracfit_emit_metric_and_ledger mode_id=direto stage=run oracle_exit="$rc" attempt=1 model_id=orquestrador \
  flash_work_s="$wall_s" frontier_wait_s="$wall_s" estimated_cost=0 cost_source=orquestrador-nao-medido task="$task" status="$status" runner=orquestrador
oracfit_emit_event run_finished status="$status" attempt=1 oracle_exit="$rc"
rm -f "$estado"
echo "run_id: $RUN_ID"
echo "status: $status"
echo "oracle_exit: $rc"
[ "$status" = pass ] || { echo "--- oráculo:"; tail -20 "$log"; exit 1; }
