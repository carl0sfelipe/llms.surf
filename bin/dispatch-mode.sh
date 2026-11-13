#!/bin/bash
# dispatch-mode.sh — Oracfit mode entry (AD-5). classify → preflight → mode loop.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-oracfit-root.sh"
source "$SCRIPT_DIR/lib-oracfit-events.sh"
source "$SCRIPT_DIR/lib-oracfit-preflight.sh"
source "$SCRIPT_DIR/lib-oracfit-metrics.sh"
source "$SCRIPT_DIR/lib-oracfit-allowlist.sh"
source "$SCRIPT_DIR/lib-oracfit-gauntlet.sh"
source "$SCRIPT_DIR/lib-oracfit-gotcha.sh"
source "$SCRIPT_DIR/lib-oracfit-supervisor.sh"
source "$SCRIPT_DIR/lib-oracfit-supervisor-ask.sh"
source "$SCRIPT_DIR/lib-oracfit-rate-limit.sh"
source "$SCRIPT_DIR/lib-oracfit-prompt-template.sh"
source "$SCRIPT_DIR/lib-oracfit-json-schema.sh"

CREDIT="Oracfit — Carlos Felipe"
MAX_ATTEMPTS_DEFAULT=3

usage() {
  cat <<EOF
Usage: dispatch-mode.sh [options] <mode_id> <spec_file> <task_name>
       dispatch-mode.sh --class CLASS          # classify-only smoke (no model)

Options:
  --class CLASS     MECANICO_TRANSFORM|T0|COPY|ARCH|SCAFFOLD
                    (default MECANICO_TRANSFORM when mode is given)
  --workdir DIR     Run workdir (default: cwd). Sets ORACFIT_WORKDIR.
  --dry-run         Resolve root / print plan; no events
  --help            This help

Modes (YAML under \$ORACFIT_ROOT/core/modes/):
  normal            Flash-class via \$DISPATCH_RUNNER, ≤3 attempts + oracle

Env:
  ORACFIT_ROOT / DISPATCH_ROOT   core root (AD-3)
  DISPATCH_RUNNER                adapters/*/runner.sh (required for model modes)
  ORACFIT_WORKDIR                workdir for events/ledger/oracle

$CREDIT
EOF
}

class_arg=""
dry_run=false
workdir_arg=""
mode_id=""
spec_file=""
task_name=""
resume_run_id=""

while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      usage
      oracfit_resolve_root >/dev/null || exit 1
      exit 0
      ;;
    --dry-run) dry_run=true; shift ;;
    --class)
      shift
      class_arg="${1:?--class requires value}"
      shift
      ;;
    --workdir)
      shift
      workdir_arg="${1:?--workdir requires value}"
      shift
      ;;
    --resume-run-id)
      shift
      resume_run_id="${1:?--resume-run-id requires value}"
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -z "$mode_id" ]; then mode_id="$1"
      elif [ -z "$spec_file" ]; then spec_file="$1"
      elif [ -z "$task_name" ]; then task_name="$1"
      else
        echo "ERROR: unexpected arg: $1" >&2
        exit 2
      fi
      shift
      ;;
  esac
done

if [ -n "$workdir_arg" ]; then
  export ORACFIT_WORKDIR="$(cd "$workdir_arg" && pwd -P)"
else
  export ORACFIT_WORKDIR="${ORACFIT_WORKDIR:-$PWD}"
  ORACFIT_WORKDIR="$(cd "$ORACFIT_WORKDIR" && pwd -P)"
  export ORACFIT_WORKDIR
fi

# Incidente 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback
# (causa nº2): WORKDIR= (nome errado) era ignorada em silêncio e o run inteiro
# escrevia eventos/ledger/inbox no lugar errado. A env reconhecida é
# ORACFIT_WORKDIR (ou --workdir). Aviso alto, não fatal.
if [ -n "${WORKDIR:-}" ] && [ "$WORKDIR" != "$ORACFIT_WORKDIR" ]; then
  echo "⚠️  dispatch-mode: env WORKDIR='$WORKDIR' NÃO é lida por este script — o nome certo é ORACFIT_WORKDIR (ou --workdir). Usando: $ORACFIT_WORKDIR" >&2
fi

if $dry_run; then
  ROOT="$(oracfit_resolve_root)" || exit 1
  echo "Would run dispatch-mode root=$ROOT workdir=$ORACFIT_WORKDIR"
  [ -n "$class_arg" ] && echo "class=$class_arg"
  [ -n "$mode_id" ] && echo "mode=$mode_id spec=$spec_file task=$task_name"
  echo "runner=${DISPATCH_RUNNER:-<unset>}"
  exit 0
fi

ROOT="$(oracfit_resolve_root)" || exit 1

# S7 (regra 53, mecanismo 1): single-flight por workdir ANTES de qualquer
# preflight/persistência — segundo dispatch com run vivo no mesmo workdir é
# recusado (exit 6) em vez de sobrepor. Lock: .dispatch/.run-lock (mkdir
# atômico + pid, em bin/lib-oracfit-root.sh). Liberação em TODO caminho de saída.
oracfit_run_lock_acquire
lock_rc=$?
[ "$lock_rc" -eq 0 ] || exit "$lock_rc"
# Replaced after preflight passes by the EXIT/TERM/INT traps that also run the
# emergency epilogue. Until then, only the lock has to be released: a run that
# dies at preflight never started, so it must not write a ledger row or a
# run_finished event (tests/test-tuned-measure.sh T2).
trap 'oracfit_run_lock_release' EXIT

# Resume (v1, 2026-08-01): oracfit resume <run_id> "<msg>" chama a gente com
# --resume-run-id e SEM mode_id/spec_file/task_name — busca os 3 nos arquivos
# persistidos pelo dispatch original (ver bloco de persistência perto do
# mint de RUN_ID mais abaixo). Sem isso a informação morria junto com o
# processo — não dava pra retomar um dispatch já terminado (achado real,
# 2026-08-01, perguntado pelo usuário). Precisa rodar ANTES do check de
# classify-only logo abaixo, senão mode_id vazio cai nesse ramo por engano.
if [ -n "$resume_run_id" ]; then
  [ -z "$mode_id" ] && mode_id="$(cat "$(oracfit_inbox_dir)/${resume_run_id}.mode-id" 2>/dev/null || true)"
  [ -z "$spec_file" ] && spec_file="$(cat "$(oracfit_inbox_dir)/${resume_run_id}.spec-file" 2>/dev/null || true)"
  [ -z "$task_name" ] && task_name="$(cat "$(oracfit_inbox_dir)/${resume_run_id}.task-name" 2>/dev/null || true)"
  if [ -z "$mode_id" ] || [ -z "$spec_file" ] || [ -z "$task_name" ]; then
    echo "ERROR: resume: não achei mode/spec/task persistidos pra run_id $resume_run_id (dispatch original é anterior a esta feature, ou arquivos foram limpos)" >&2
    exit 3
  fi
fi

# --- classify-only path (Story 1.3 compat) ---
if [ -z "$mode_id" ]; then
  if [ -z "$class_arg" ]; then
    echo "ERROR: provide <mode_id> <spec> <task> or --class for classify-only" >&2
    exit 2
  fi
  RUN_ID="$(oracfit_mint_run_id)"
  export ORACFIT_RUN_ID="$RUN_ID"
  classify_output="$("$SCRIPT_DIR/classify-dispatch.sh" --class "$class_arg")" || true
  allowed=$(echo "$classify_output" | grep -o 'allowed=[a-z]*' | head -1 | cut -d= -f2)
  detected_class=$(echo "$classify_output" | grep -o 'class=[^ ]*' | head -1 | cut -d= -f2)
  oracfit_emit_event classify_result allowed="$allowed" class="$detected_class"
  if [ "$allowed" != "true" ]; then
    echo "Dispatch rejected: class=$detected_class" >&2
    exit 1
  fi
  oracfit_emit_event run_started mode=stub stage=init
  echo "run_id: $RUN_ID"
  echo "events: $(oracfit_events_path)"
  exit 0
fi

# --- full mode path ---
if [ -z "$spec_file" ] || [ -z "$task_name" ]; then
  echo "ERROR: usage: dispatch-mode.sh <mode_id> <spec_file> <task_name>" >&2
  exit 2
fi
if [ ! -f "$spec_file" ]; then
  # allow relative to ROOT
  if [ -f "$ROOT/$spec_file" ]; then
    spec_file="$ROOT/$spec_file"
  else
    echo "ERROR: spec not found: $spec_file" >&2
    exit 3
  fi
fi
spec_file="$(cd "$(dirname "$spec_file")" && pwd -P)/$(basename "$spec_file")"

if [ -z "$class_arg" ]; then
  class_arg="MECANICO_TRANSFORM"
fi

# Custom mode resolution order (AD-16, docs/modes-catalog.md §1): workdir overlay
# first, then the shared ORACFIT_ROOT install. Lets a project define its own
# core/modes/<id>.yaml (e.g. via `oracfit mode init`, which already scaffolds
# there) without forking or polluting the shared dispatch checkout — this is
# the "custom YAML é o ouro" path the catalog describes, but until now nothing
# actually looked in the workdir, so `oracfit mode init <id>` produced a file
# dispatch-mode.sh could never find.
mode_yaml="$ORACFIT_WORKDIR/core/modes/${mode_id}.yaml"
if [ ! -f "$mode_yaml" ]; then
  mode_yaml="$ROOT/core/modes/${mode_id}.yaml"
fi
if [ ! -f "$mode_yaml" ]; then
  echo "ERROR: unknown mode (no YAML): tried $ORACFIT_WORKDIR/core/modes/${mode_id}.yaml and $ROOT/core/modes/${mode_id}.yaml" >&2
  exit 3
fi

# validate mode schema (AD-16)
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$mode_yaml" || exit $?

if [ -z "${DISPATCH_RUNNER:-}" ]; then
  echo "ERROR: DISPATCH_RUNNER is unset. Example smoke:" >&2
  echo "  export DISPATCH_RUNNER=\"\$ORACFIT_ROOT/adapters/stub/runner.sh\"" >&2
  exit 3
fi

# Read the ref through the YAML loader (not grep): an inline comment after the
# value used to travel inside the ref and the tier resolver then found no model.
model_ref="$(python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" dump "$mode_yaml" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("")
    raise SystemExit(0)
stages = data.get("stages") or []
for stage in stages:
    ref = (stage or {}).get("model_ref")
    if ref:
        print(ref)
        break
else:
    print(data.get("model_ref") or "")
')"
# The artifacts promise: a stage that declares `artifacts:` promised to leave
# something there. Read through the loader (the same reader the rest of the
# runtime uses) and kept in a variable the attempt loop can check.
mode_stage_json="$(python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" dump "$mode_yaml" 2>/dev/null || true)"
artifacts="$(printf '%s' "$mode_stage_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("")
    raise SystemExit(0)
stages = data.get("stages") or []
for stage in stages:
    if isinstance(stage, dict) and stage.get("artifacts"):
        print(stage["artifacts"])
        break
')"
stage_role="$(printf '%s' "$mode_stage_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("")
    raise SystemExit(0)
stages = data.get("stages") or []
for stage in stages:
    if isinstance(stage, dict) and stage.get("role"):
        print(stage["role"])
        break
')"
stage_role="${stage_role:-run}"
# prompt_template of the stage this runtime dispatches (the first stage
# that carries a model_ref). Same reader as artifacts / rate_limit_s.
prompt_template="$(printf '%s' "$mode_stage_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("")
    raise SystemExit(0)
stages = data.get("stages") or []
for stage in stages:
    if not isinstance(stage, dict):
        continue
    if stage.get("model_ref"):
        value = stage.get("prompt_template")
        print(value if isinstance(value, str) else "")
        break
')"
prompt_template_path=""
prompt_template_missing=false
# json_schema of the stage this runtime dispatches (the first stage
# that carries a model_ref). Same reader as prompt_template.
json_schema="$(printf '%s' "$mode_stage_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("")
    raise SystemExit(0)
stages = data.get("stages") or []
for stage in stages:
    if not isinstance(stage, dict):
        continue
    if stage.get("model_ref"):
        value = stage.get("json_schema")
        print(value if isinstance(value, str) else "")
        break
')"
json_schema_path=""
json_schema_missing=false
# The throttle the mode declares: two calls of the same model, or two
# attempts of the same stage, are at least rate_limit_s seconds apart. Read
# from the stage that carries the model_ref - the stage this runtime
# dispatches. The index comes with it: it is the key of the stage in the
# ledger of the throttle.
rate_limit_s="$(printf '%s' "$mode_stage_json" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except ValueError:
    print("0 0")
    raise SystemExit(0)
stages = data.get("stages") or []
for index, stage in enumerate(stages):
    if not isinstance(stage, dict):
        continue
    ref = stage.get("model_ref")
    if ref:
        value = stage.get("rate_limit_s")
        print("%d %d" % (index, int(value) if isinstance(value, (int, float)) and not isinstance(value, bool) else 0))
        break
else:
    print("0 0")
')"
rate_limit_stage_index="${rate_limit_s%% *}"
rate_limit_s="${rate_limit_s##* }"
# E5-M3: o default antigo (deepseek-v4-flash-free) tinha hint morto e ficou
# sendo servido em silêncio — a classe exata do incidente E5. Default agora é
# a rota free do catálogo carimbado (resolve loud se o catálogo estiver ausente).
model_ref="${model_ref:-tier:cheap}"
# Incidente 2026-08-11-prompt-v3-travelview-espera-override-dis: override por
# env vence YAML e default. Permite fallback cheap→paid sem criar outro modo.
if [ -n "${DISPATCH_MODEL_REF:-}" ]; then

  model_ref="$DISPATCH_MODEL_REF"

  # Dogfood 2026-09-26 (rails-chatapp-gguf): modelo fora do model-registry.json
  # queimava max_attempts do gauntlet com oracle falhando antes de alguém
  # perceber o erro de integração. Falha rápida, com instrução acionável.
  # MODEL_REGISTRY: mesmo override do runner e do run-with-fallback (fixtures de teste).
  registry_file="${MODEL_REGISTRY:-${ROOT}/model-registry.json}"
  if [ -f "$registry_file" ] && [ -n "$model_ref" ]; then
    if ! python3 - "$model_ref" "$registry_file" <<'PYREG'
import json, sys
ref = sys.argv[1]
d = json.load(open(sys.argv[2]))
sys.exit(0 if any(m.get("id") == ref for m in d.get("models", [])) else 1)
PYREG
    then
      echo "FAIL: modelo '${model_ref}' ausente do ${registry_file}." >&2
      echo "  Ação: adicione a entrada {id, provider, tier, cli_hints: {opencode: "provider/model"}} e rode de novo. O gauntlet nem inicia." >&2
      exit 1
    fi
  fi

fi
# The keys the throttle is measured against: the stage this runtime dispatches
# and, when there is one, the model it calls. The model key is what keeps two
# calls to the same model apart even when they belong to different stages.
rate_limit_keys=("stage:${rate_limit_stage_index}")
if [ -n "$model_ref" ]; then
  rate_limit_keys+=("model:${model_ref}")
fi
max_attempts="$(grep -E '^\s*max_attempts:' "$mode_yaml" | head -1 | awk '{print $2}' || true)"
max_attempts="${max_attempts:-$MAX_ATTEMPTS_DEFAULT}"
# Gauntlet: until_approved raises the ceiling (exit = oracle pass, not fixed N).
max_attempts="$(oracfit_gauntlet_resolve_max_attempts "$mode_yaml" "$max_attempts")"

  # Dogfood 2026-09-26: toolchain quebrado no host (shims ELF do mise) queimou
  # o teto inteiro de dois runs locais. Gate OPT-IN: SURF_TOOLCHAIN_GATE=1.
  if [ "${SURF_TOOLCHAIN_GATE:-0}" = "1" ] && [ -f "$SCRIPT_DIR/check-toolchain.sh" ]; then
    bash "$SCRIPT_DIR/check-toolchain.sh" || {
      echo "FAIL: toolchain do host reprovado no gate (SURF_TOOLCHAIN_GATE=1). Corrija ou despache sem o gate." >&2
      exit 1
    }
  fi
gauntlet_on=false
oracfit_gauntlet_inject_enabled "$mode_yaml" && gauntlet_on=true

if [ -n "$resume_run_id" ]; then
  RUN_ID="$resume_run_id"
  export ORACFIT_RUN_ID="$RUN_ID"
else
  RUN_ID="$(oracfit_mint_run_id)"
  export ORACFIT_RUN_ID="$RUN_ID"
fi
# T20: run-with-fallback writes who served; mode ledger records it (E5).
export DISPATCH_EFETIVO_FILE="$ORACFIT_WORKDIR/.dispatch/pids/mode-${RUN_ID}.efetivo"
mkdir -p "$(dirname "$DISPATCH_EFETIVO_FILE")"
rm -f "$DISPATCH_EFETIVO_FILE"
t_run0=$(python3 -c 'import time; print(time.time())')

# Guaranteed epilogue, ported from oracfit_stages_emergency_epilogue (incident
# 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback): if this
# process dies before the normal close (set -e, SIGTERM/SIGINT, killed from
# outside), still emit run_finished + a ledger row (best effort) and the final
# run_id/status lines. The happy path sets epilogue_done=1 so this trap is a
# no-op. Defensive: every call has || true, so set -e cannot kill the trap.
epilogue_done=0
oracfit_mode_emergency_epilogue() {
  [ "${epilogue_done:-0}" = "1" ] && return 0
  epilogue_done=1
  local t_abn dur_abn
  dur_abn=0
  if [ -n "${t_run0:-}" ]; then
    t_abn="$(python3 -c 'import time; print(time.time())' 2>/dev/null || true)"
    if [ -n "$t_abn" ]; then
      dur_abn="$(python3 -c "print(round(float('$t_abn')-float('$t_run0'), 3))" 2>/dev/null || echo 0)"
    fi
  fi
  oracfit_emit_event run_finished status=fail reason=abnormal_exit \
    attempt="${attempt:-0}" duration_s="$dur_abn" 2>/dev/null || true
  ORACFIT_FREE_FIELDS=()
  oracfit_free_path_read "${DISPATCH_EFETIVO_FILE:-}" 2>/dev/null || true
  oracfit_emit_metric_and_ledger \
    mode_id="${mode_id:-}" \
    stage=run \
    oracle_exit="${oracle_exit:-1}" \
    attempt="${attempt:-0}" \
    model_id="${model_ref:-}" \
    flash_work_s="${flash_work_s:-0}" \
    frontier_wait_s="${frontier_wait_s:-0}" \
    estimated_cost="${estimated_cost:-0}" \
    task="${task_name:-}" \
    status=fail \
    "${ORACFIT_FREE_FIELDS[@]}" 2>/dev/null || true
  echo "run_id: ${RUN_ID:-}"
  echo "status: fail"
  return 0
}
# Traps that call this function are armed only after preflight passes.
# Installing them here would write a ledger row for a run that never started.

# The artifacts dir of this stage (only when the mode declares one). The
# runner writes there, the gate below reads it, and the model is told where
# it is — a declared artifacts dir is a promise the runtime keeps.
art_dir=""
if [ -n "$artifacts" ]; then
  art_dir="$ORACFIT_WORKDIR/.dispatch/artifacts/${RUN_ID}/${artifacts}"
  mkdir -p "$art_dir"
  export ORACFIT_STAGE_ROLE="$stage_role"
  export ORACFIT_STAGE_ARTIFACTS="$art_dir"
fi

# Persiste mode/spec/task por run_id — sem isso `oracfit resume` não teria
# como reconstruir o dispatch depois que o processo termina (o run_id sozinho
# não basta, só fica no events.jsonl como texto solto, não como arquivo
# buscável). Grava sempre (resume ou não) pra continuar funcionando se
# alguém der resume num resume.
mkdir -p "$(oracfit_inbox_dir)"
printf '%s' "$mode_id" > "$(oracfit_inbox_dir)/${RUN_ID}.mode-id"
printf '%s' "$spec_file" > "$(oracfit_inbox_dir)/${RUN_ID}.spec-file"
printf '%s' "$task_name" > "$(oracfit_inbox_dir)/${RUN_ID}.task-name"

# classify
classify_output="$("$SCRIPT_DIR/classify-dispatch.sh" --class "$class_arg")" || true
allowed=$(echo "$classify_output" | grep -o 'allowed=[a-z]*' | head -1 | cut -d= -f2)
detected_class=$(echo "$classify_output" | grep -o 'class=[^ ]*' | head -1 | cut -d= -f2)
oracfit_emit_event classify_result allowed="$allowed" class="$detected_class"
if [ "$allowed" != "true" ]; then
  echo "Dispatch rejected: class=$detected_class" >&2
  exit 1
fi

# preflight (AD-11) — before any model
set +e
oracfit_preflight "$spec_file" "$ORACFIT_WORKDIR"
pf_rc=$?
set -e
if [ "$pf_rc" -ne 0 ]; then
  exit "$pf_rc"
fi

# Preflight passed: the run has started. From here an abnormal death must
# close evidence (run_finished + ledger) the same way dispatch-stages.sh
# does after its own preflight (traps at lines 194-196, after preflight
# at line 126). The lock-only EXIT trap above stays armed until this point.
trap 'oracfit_mode_emergency_epilogue; oracfit_run_lock_release' EXIT
trap 'oracfit_mode_emergency_epilogue; oracfit_run_lock_release; exit 143' TERM
trap 'oracfit_mode_emergency_epilogue; oracfit_run_lock_release; exit 130' INT

oracfit_emit_event run_started mode="$mode_id" stage=run task="$task_name" model_id="$model_ref"
oracfit_emit_event stage_changed stage=run

attempt=0
oracle_exit=1
final_status=fail
supervisor_question_file=""
flash_work_s=0
# Gauntlet accum: oracle failures → next builder prompt (fresh session still).
gauntlet_dir="$(oracfit_inbox_dir)/${RUN_ID}.gauntlet"
gauntlet_accum="${gauntlet_dir}/feedback.md"
gauntlet_gotcha="${gauntlet_dir}/gotcha.md"
mkdir -p "$gauntlet_dir"
: >"$gauntlet_accum"
: >"$gauntlet_gotcha"
if [ -n "$prompt_template" ]; then
  if ! prompt_template_path="$(oracfit_prompt_template_resolve "$prompt_template")"; then
    prompt_template_path=""
    prompt_template_missing=true
    echo "PROMPT TEMPLATE NOT FOUND: $prompt_template" >&2
    printf '%s\n' "PROMPT TEMPLATE NOT FOUND: $prompt_template" \
      >"${gauntlet_dir}/oracle-attempt-1.log"
  fi
fi
if [ -n "$json_schema" ]; then
  if ! json_schema_path="$(oracfit_json_schema_resolve "$json_schema")"; then
    json_schema_path=""
    json_schema_missing=true
    echo "JSON SCHEMA NOT FOUND: $json_schema" >&2
    printf '%s\n' "JSON SCHEMA NOT FOUND: $json_schema" \
      >"${gauntlet_dir}/oracle-attempt-1.log"
  fi
fi
# Real executor cost, one JSON line per attempt (claude-code runner; other runners ignore it).
# Summed into the ledger below — docs/delegation-check.md §4.
export ORACFIT_COST_FILE="${gauntlet_dir}/executor-cost.jsonl"
: >"$ORACFIT_COST_FILE"

# Guard de zonas protegidas (v3.5 — relatório fábrica-agentic §3, fase "Core
# Hijacking": payload convence o modelo a usar os próprios privilégios de tool
# p/ reescrever os arquivos de CONTROLE do framework e persistir; ver
# docs/pesquisa/2026-08-12-triagem-fabrica-agentic-v3.5.md §A1). O dispatch não
# tem sandbox — o que dá pra ter honesto é DETECÇÃO: snapshot do git antes do
# attempt 1, comparação no epílogo. Lista: <workdir>/.oracfit-protected vence;
# sem ela, a default só vale quando o workdir É este checkout. Fail-open:
# sem git ou sem lista, o guard não roda e não atrapalha o run.
protected_globs_file=""
if [ -f "$ORACFIT_WORKDIR/.oracfit-protected" ]; then
  protected_globs_file="$ORACFIT_WORKDIR/.oracfit-protected"
elif [ "$ORACFIT_WORKDIR" = "$ROOT" ] && [ -f "$ROOT/core/protected-paths-default.txt" ]; then
  protected_globs_file="$ROOT/core/protected-paths-default.txt"
fi
pre_run_git_snapshot=""
if [ -n "$protected_globs_file" ] && git -C "$ORACFIT_WORKDIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pre_run_git_snapshot="${gauntlet_dir}/pre-run-git.txt"
  git -C "$ORACFIT_WORKDIR" status --porcelain >"$pre_run_git_snapshot" 2>/dev/null || pre_run_git_snapshot=""
fi

# HITL (v1): humano manda mensagem pelo painel -> escreve em
# .dispatch/logs/inbox/<run_id>.jsonl (fila, sempre) e opcionalmente toca
# .dispatch/logs/inbox/<run_id>.interrupt (pede interrupcao AGORA). O
# runner (adapters/*/runner.sh) ja tem watchdog rodando (reusado do
# detector de rate-limit) - so ganhou mais uma condicao pra checar. Exit
# 5 do runner = "interrompido a pedido do humano", nao e falha de modelo.
#
# Continuidade de sessao (P0, 2026-08-01): interromper SEM retomar a mesma
# sessao do opencode jogaria fora o cache de prompt acumulado — medido em
# 2026-08-01, cache_read foi 101,7M de 109M tokens totais do EPIC inteiro
# (ver lessons/). O runner escreve o session id real (capturado do stderr,
# --log-level INFO) em ORACFIT_SESSION_FILE; SO' apos um interrupt (nao em
# retry comum por oraculo falho — aquele continua sem --session de
# proposito, incidente A 2026-07-27, pra nao repetir o mesmo erro) o
# proximo attempt reusa esse id via --session, preservando cache hit.
# Se ESTE processo já é um `oracfit resume` (run_id reaproveitado de um
# dispatch anterior), o attempt 1 daqui também deve começar reusando a
# última sessão conhecida — senão resume de job já terminado perderia
# cache igual perderia um interrupt sem esse mecanismo.
resume_session_id=""
if [ -n "$resume_run_id" ]; then
  resume_session_id="$(cat "$(oracfit_session_file "$RUN_ID")" 2>/dev/null || true)"
fi
while [ "$prompt_template_missing" = false ] && [ "$json_schema_missing" = false ] && [ "$attempt" -lt "$max_attempts" ]; do
  attempt=$((attempt + 1))
  oracfit_emit_event attempt_started attempt="$attempt" mode="$mode_id"

  # The throttle the mode declares, now kept by the runtime: two calls of the
  # same model - or two attempts of the same stage - are at least
  # rate_limit_s seconds apart. The pause is measured from the END of the
  # previous dispatch, so a slow call does not count as a pause. The wait
  # yields to a human interrupt (the same file the runner watchdog watches).
  #
  # The gate runs BEFORE the inbox is read: an interrupt during the wait
  # must not eat the human message - the next attempt picks it up.
  rl_interrupt_file="$(oracfit_interrupt_file "$RUN_ID")"
  if ! oracfit_rate_limit_gate "$rate_limit_s" "mode $mode_id attempt $attempt" "$rl_interrupt_file" "${rate_limit_keys[@]}"; then
    # Interrupted during the wait: the attempt ends here, the next one picks
    # the human message up from the inbox. Same treatment as the runner
    # exit 5 below.
    oracfit_emit_event attempt_interrupted attempt="$attempt" reason=rate_limit_wait
    rm -f "$rl_interrupt_file" 2>/dev/null || true
    continue
  fi

  run_spec_file="$spec_file"
  # prompt_template first: after the base spec, before ground truth,
  # artifacts context and the human message.
  if [ -n "$prompt_template_path" ]; then
    pt_composed="$(mktemp "${TMPDIR:-/tmp}/oracfit-prompt-XXXXXX")"
    {
      cat "$run_spec_file"
      oracfit_prompt_template_emit "$prompt_template" "$prompt_template_path"
    } >"$pt_composed"
    run_spec_file="$pt_composed"
  fi
  # json_schema next: after the prompt template (when it exists), before
  # ground truth, gauntlet feedback and the human message.
  if [ -n "$json_schema_path" ]; then
    js_composed="$(mktemp "${TMPDIR:-/tmp}/oracfit-schema-XXXXXX")"
    {
      cat "$run_spec_file"
      oracfit_json_schema_emit "$json_schema" "$json_schema_path"
    } >"$js_composed"
    [ "$run_spec_file" != "$spec_file" ] && rm -f "$run_spec_file"
    run_spec_file="$js_composed"
  fi
  # P4: refresh ground-truth from ## Dados verificados every attempt/resume.
  gauntlet_gt="${gauntlet_dir}/ground-truth.md"
  oracfit_gauntlet_extract_ground_truth "$spec_file" >"$gauntlet_gt" 2>/dev/null || : >"$gauntlet_gt"
  # Gauntlet + ground-truth: compose BEFORE HITL inbox.
  if $gauntlet_on && { [ -s "$gauntlet_accum" ] || [ -s "$gauntlet_gt" ] || [ -s "$gauntlet_gotcha" ]; } || [ -s "$gauntlet_accum" ]; then
    # BSD/macOS mktemp: XXXXXX tem que terminar o template — sufixo .md fazia
    # mkstemp criar arquivo literal na 1a chamada e falhar "File exists" nas seguintes
    # (descoberto 2026-08-10 no relancamento do piloto content_factory).
    gauntlet_composed="$(mktemp "${TMPDIR:-/tmp}/oracfit-gauntlet-XXXXXX")"
    oracfit_gauntlet_compose_spec "$run_spec_file" "$gauntlet_accum" "$gauntlet_composed" "$gauntlet_gt" "$gauntlet_gotcha"
    [ "$run_spec_file" != "$spec_file" ] && rm -f "$run_spec_file"
    run_spec_file="$gauntlet_composed"
    oracfit_emit_event gauntlet_compose attempt="$attempt" has_feedback="$([ -s "$gauntlet_accum" ] && echo true || echo false)" has_ground_truth="$([ -s "$gauntlet_gt" ] && echo true || echo false)"
  fi

  # The artifacts promise, told to the model: the stage has to write there.
  if [ -n "$art_dir" ]; then
    art_composed="$(mktemp "${TMPDIR:-/tmp}/oracfit-artifacts-XXXXXX")"
    {
      cat "$run_spec_file"
      echo ""
      echo "## Stage context (Oracfit single-stage)"
      echo "- role: $stage_role"
      echo "- artifacts_dir: \`$art_dir\`"
      echo "- The stage MUST leave a non-empty file in that directory: a stage that declares \`artifacts:\` and writes nothing there fails."
    } >"$art_composed"
    [ "$run_spec_file" != "$spec_file" ] && rm -f "$run_spec_file"
    run_spec_file="$art_composed"
  fi

  inbox_file="$(oracfit_inbox_file "$RUN_ID")"
  if [ -s "$inbox_file" ]; then
    augmented="$(mktemp "${TMPDIR:-/tmp}/oracfit-spec-XXXXXX")"
    {
      cat "$run_spec_file"
      echo
      echo "## Mensagem do humano (recebida durante a execução, attempt $attempt)"
      echo
      python3 -c '
import json, sys
for line in open(sys.argv[1]):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    print("-", obj.get("text", ""))
' "$inbox_file"
    } >"$augmented"
    [ "$run_spec_file" != "$spec_file" ] && rm -f "$run_spec_file"
    run_spec_file="$augmented"
    oracfit_emit_event message_consumed attempt="$attempt" count="$(wc -l < "$inbox_file" | tr -d ' ')"
    : >"$inbox_file"
  fi

  # Achado 2026-08-01: painel nunca mostrava o PROMPT real mandado pro modelo
  # (so' classify/preflight/thinking/tool_call/oracle) — pedido explicito do
  # usuario. Emite o conteudo exato deste attempt (spec original ou
  # aumentado com mensagem humana) como evento proprio, truncado a 60KB pra
  # nao estourar events.jsonl com specs gigantes.
  if [ -n "${ORACFIT_RUN_ID:-}" ]; then
    RUN_SPEC_FILE="$run_spec_file" ORACFIT_ATTEMPT="$attempt" ORACFIT_EVENTS_PATH="$(oracfit_events_path)" python3 -c '
import json, os, sys
from datetime import datetime, timezone
spec_path = os.environ["RUN_SPEC_FILE"]
content = open(spec_path, "r", errors="replace").read()
truncated = len(content) > 60000
if truncated:
    content = content[:60000] + "\n\n...(truncado, spec original maior que 60KB)..."
obj = {
    "v": 1,
    "ts": datetime.now(timezone.utc).isoformat(),
    "run_id": os.environ["ORACFIT_RUN_ID"],
    "type": "prompt_sent",
    "attempt": os.environ["ORACFIT_ATTEMPT"],
    "content": content,
    "truncated": truncated,
}
path = os.environ["ORACFIT_EVENTS_PATH"]
os.makedirs(os.path.dirname(path), exist_ok=True)
with open(path, "a") as f:
    f.write(json.dumps(obj, ensure_ascii=False) + "\n")
' 2>/dev/null || true
  fi

  runner_args=("$model_ref" "$run_spec_file")
  if [ -n "$resume_session_id" ]; then
    runner_args+=(--session "$resume_session_id")
    oracfit_emit_event session_resumed attempt="$attempt" session_id="$resume_session_id"
  fi

  t0=$(python3 -c 'import time; print(time.time())')
  set +e
  export ORACFIT_EVENTS_FILE="$(oracfit_events_path)"
  export ORACFIT_INTERRUPT_FILE="$(oracfit_interrupt_file "$RUN_ID")"
  export ORACFIT_SESSION_FILE="$(oracfit_session_file "$RUN_ID")"
  # Incidente 2026-08-30-unlock-plan-passa-tier-ao-runner-sem-res (B2/E5-M4):
  # model_ref tier:* não é id — nenhum runner de verdade o aceita (exit 3).
  # Expande pela cadeia do catálogo free carimbado via run-with-fallback.
  case "$model_ref" in
    tier:*) STAGE_RUNNER="$SCRIPT_DIR/run-with-fallback.sh" ;;
    *)      STAGE_RUNNER="$DISPATCH_RUNNER" ;;
  esac
  "$STAGE_RUNNER" "${runner_args[@]}" | "$SCRIPT_DIR/oracfit-thinking-tee.py"
  runner_rc=${PIPESTATUS[0]}
  # The call is over: the next attempt of this mode (or the next call of the
  # same model) measures its pause from this moment.
  oracfit_rate_limit_record_call "${rate_limit_keys[@]}"
  unset ORACFIT_EVENTS_FILE
  set -e
  [ "$run_spec_file" != "$spec_file" ] && rm -f "$run_spec_file"
  t1=$(python3 -c 'import time; print(time.time())')
  stage_s=$(python3 -c "print(round(float('$t1')-float('$t0'), 3))")
  flash_work_s=$(python3 -c "print(round(float('$flash_work_s')+float('$stage_s'), 3))")

  captured_session=""
  [ -s "$ORACFIT_SESSION_FILE" ] && captured_session="$(cat "$ORACFIT_SESSION_FILE")"

  if [ "$runner_rc" -eq 5 ]; then
    oracfit_emit_event attempt_interrupted attempt="$attempt" duration_s="$stage_s" session_id="$captured_session"
    rm -f "$ORACFIT_INTERRUPT_FILE" 2>/dev/null || true
    unset ORACFIT_INTERRUPT_FILE ORACFIT_SESSION_FILE
    resume_session_id="$captured_session"
    continue
  fi
  unset ORACFIT_INTERRUPT_FILE ORACFIT_SESSION_FILE
  resume_session_id=""

  oracfit_emit_event attempt_finished attempt="$attempt" runner_exit="$runner_rc" duration_s="$stage_s"

  # Exit 3 = usage error (wrong model, auth, denied write): the next attempt would fail the same way.
  # Stop here instead of burning the gauntlet (incident 2026-10-02-claude-code-runner-sai-0-com-escrita-negada).
  if [ "$runner_rc" -eq 3 ]; then
    oracfit_emit_event runner_usage_error attempt="$attempt"
    echo "runner exited 3 (usage error) — attempts stopped; fix the configuration and dispatch again" >&2
    break
  fi

  oracle_log="${gauntlet_dir}/oracle-attempt-${attempt}.log"
  if [ -n "$art_dir" ] && [ -z "$(find "$art_dir" -type f ! -empty -print -quit 2>/dev/null)" ]; then
    # A stage that declares `artifacts:` promised to leave something there.
    # Nothing there = the promise broken. The reason lands in the oracle log,
    # so the next attempt gets it as feedback instead of guessing again.
    oracle_exit=1
    {
      echo "STAGE ARTIFACTS EMPTY: role=$stage_role attempt=$attempt dir=$art_dir"
      echo "The stage declared 'artifacts: $artifacts' and left no non-empty file there."
    } >"$oracle_log"
  else
    set +e
    oracfit_gauntlet_run_oracle_capture "$spec_file" "$ORACFIT_WORKDIR" "$oracle_log"
    oracle_exit=$?
    set -e
  fi
  oracfit_emit_event oracle_result exit="$oracle_exit" attempt="$attempt" command=from-spec

  if [ "$oracle_exit" -eq 0 ]; then
    final_status=pass
    break
  fi

  # Gauntlet: inject critic feedback for the next builder attempt (same session
  # is intentionally NOT reused — incidente A — but the SPEC learns).
  if $gauntlet_on && [ "$attempt" -lt "$max_attempts" ]; then
    biggest_gap="$(oracfit_gauntlet_append_feedback "$gauntlet_accum" "$attempt" "$oracle_exit" "$oracle_log")"
    oracfit_emit_event gauntlet_feedback attempt="$attempt" oracle_exit="$oracle_exit" biggest_gap="$(printf '%s' "$biggest_gap" | tr '\n' ' ' | cut -c1-200)"
    echo "gauntlet: attempt $attempt failed — gap: $biggest_gap" >&2
    # Deterministic gotcha match: best-effort. A failed evaluation must not
    # change the run's exit code or the oracle text.
    _gotcha_ids=""
    _gotcha_fired=0
    _gotcha_det=0
    _gotcha_events="$(oracfit_events_path)"
    _gotcha_ids="$(oracfit_gotcha_match_inject "$ORACFIT_WORKDIR" "$gauntlet_dir" "$_gotcha_events" "$oracle_exit" "$attempt" "$gauntlet_gotcha" || true)"
    _gotcha_fires="${gauntlet_dir}/fires-attempt-${attempt}.jsonl"
    if [ -f "$_gotcha_fires" ]; then
      _gotcha_counts="$(python3 -c '
import json, sys
fired = det = 0
try:
    for line in open(sys.argv[1], encoding="utf-8"):
        line = line.strip()
        if not line:
            continue
        fired += 1
        try:
            if json.loads(line).get("class") == "deterministic":
                det += 1
        except ValueError:
            pass
except OSError:
    pass
print(fired, det)
' "$_gotcha_fires" 2>/dev/null || echo "0 0")"
      _gotcha_fired="${_gotcha_counts%% *}"
      _gotcha_det="${_gotcha_counts##* }"
    fi
    oracfit_emit_event gotcha_match attempt="$attempt" oracle_exit="$oracle_exit" fired="${_gotcha_fired:-0}" deterministic="${_gotcha_det:-0}" ids="${_gotcha_ids}"
    unset _gotcha_ids _gotcha_fired _gotcha_det _gotcha_events _gotcha_fires _gotcha_counts
  fi

  # Attempt boundary: ask the supervisor (when no hand-placed decision
  # file and an endpoint is set), then apply the order for the next
  # attempt. A failed ask must not change this run's exit code. An
  # applied ESCALATE spends this attempt and pauses the run for the
  # owner.
  if [ "$attempt" -lt "$max_attempts" ]; then
    _sup_hand=""
    if [ -n "${ORACFIT_SUPERVISOR_DECISION:-}" ] && [ -f "${ORACFIT_SUPERVISOR_DECISION}" ]; then
      _sup_hand="$ORACFIT_SUPERVISOR_DECISION"
    elif [ -n "${ORACFIT_SUPERVISOR_ENDPOINT:-}" ]; then
      _sup_inbox="$(oracfit_inbox_dir)"
      _sup_state="${_sup_inbox}/${RUN_ID}.state.json"
      _sup_out="${_sup_inbox}/${RUN_ID}.json"
      mkdir -p "$_sup_inbox" 2>/dev/null || true
      if python3 - "$_sup_state" "$RUN_ID" "$mode_id" "$task_name" "$attempt" "$oracle_exit" "$gauntlet_accum" <<'PY'
import json
import os
import sys

out, run_id, mode_id, task_name, attempt, oracle_exit, accum = sys.argv[1:8]
text = ""
try:
    with open(accum, encoding="utf-8") as fh:
        text = fh.read()
except OSError:
    pass
parent = os.path.dirname(out)
if parent:
    os.makedirs(parent, exist_ok=True)
doc = {
    "run_id": run_id,
    "mode_id": mode_id,
    "task_name": task_name,
    "attempt": int(attempt),
    "oracle_exit": int(oracle_exit),
    "gauntlet_accum": text,
}
with open(out, "w", encoding="utf-8") as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=2)
    fh.write("\n")
PY
      then
        oracfit_supervisor_ask_order "$ORACFIT_WORKDIR" "$RUN_ID" "$attempt" "$_sup_state" >/dev/null || true
        if [ -f "$_sup_out" ]; then
          export ORACFIT_SUPERVISOR_DECISION="$_sup_out"
        fi
      else
        oracfit_emit_event supervisor_ask result=failed reason="could not write round state" attempt="$attempt" || true
      fi
    fi
    oracfit_supervisor_apply_order "$ORACFIT_WORKDIR" "$gauntlet_accum" "$RUN_ID" "$attempt" || true
    if [ -n "$_sup_hand" ]; then
      export ORACFIT_SUPERVISOR_DECISION="$_sup_hand"
    else
      unset ORACFIT_SUPERVISOR_DECISION
    fi
    unset _sup_hand _sup_inbox _sup_state _sup_out
    if [ "${ORACFIT_SUPERVISOR_LAST_ACTION:-}" = "ESCALATE" ] \
      && [ "${ORACFIT_SUPERVISOR_LAST_RESULT:-}" = "applied" ]; then
      final_status=owner_question
      oracle_exit=7
      supervisor_question_file="${ORACFIT_SUPERVISOR_LAST_FILE:-}"
      [ -n "$supervisor_question_file" ] \
        || supervisor_question_file="$(oracfit_inbox_dir)/${RUN_ID}.question.md"
      oracfit_emit_event owner_question \
        attempt="$attempt" file="$supervisor_question_file" || true
      break
    fi
  fi
done

# Incidente 2026-08-10-dispatch-mode-run-finished-sem-ledger-nem-usage-feedback
# (causa nº1): sob `set -e`, substituição de comando falhando neste epílogo
# matava o script ANTES do ledger e do run_finished — attempt_finished ficava
# como último evento e a telemetria sumia. Daqui até o exit, tudo é
# melhor-esforço: erro é tolerado, nunca fatal.
set +e

# Incidente 2026-08-12-run-marcado-fail-com-oraculo-verde-no-di: o modelo pode
# corrigir o trabalho DEPOIS da avaliação do oráculo da última attempt (típico:
# ele mesmo roda o oráculo no fim e se autocorrige). Fechar como fail sem reler
# o disco grava falso-fail no ledger e dispara retrabalho/rollback de trabalho
# bom. ADR-0002: o ledger mede o DISCO, não a memória da última avaliação.
# A paused run (owner_question) must not be rechecked: the recheck can
# flip the outcome of a run that is waiting for the owner.
if [ "$final_status" = "fail" ] && [ "$attempt" -gt 0 ]; then
  if [ -n "$art_dir" ] && [ -z "$(find "$art_dir" -type f ! -empty -print -quit 2>/dev/null)" ]; then
    # The artifacts promise is still broken on disk: the recheck below must not
    # flip a run to pass because the spec oracle looks somewhere else.
    final_recheck=1
    echo "declared artifact still empty at close — the run stays fail (the mode's promise was not kept)" >&2
    oracfit_emit_event oracle_final_recheck exit="$final_recheck" attempt="$attempt" reason=artifacts_empty
  else
  final_recheck_log="${gauntlet_dir}/oracle-final-recheck.log"
  oracfit_gauntlet_run_oracle_capture "$spec_file" "$ORACFIT_WORKDIR" "$final_recheck_log"
  final_recheck=$?
  if [ "$final_recheck" -eq 0 ]; then
    echo "oráculo verde no disco no fechamento — a última attempt avaliou estado anterior ao último write do modelo (falso-fail evitado)" >&2
    oracle_exit=0
    final_status=pass
  fi
  oracfit_emit_event oracle_final_recheck exit="$final_recheck" attempt="$attempt"
  fi
fi

# Guard de zonas protegidas — comparação pós-run (snapshot feito antes do
# attempt 1). Alerta, NUNCA bloqueio: spec legítima pode mandar editar bin/
# (o painel vive lá) — quem decide é o judge/humano; aqui só se garante que
# escrita em zona de controle nunca passa DESPERCEBIDA. Estamos no trecho
# `set +e`: qualquer falha aqui é tolerada.
if [ -n "${pre_run_git_snapshot:-}" ] && [ -f "$pre_run_git_snapshot" ] && [ -s "$protected_globs_file" ]; then
  post_run_git="$(git -C "$ORACFIT_WORKDIR" status --porcelain 2>/dev/null || true)"
  if [ -s "$pre_run_git_snapshot" ]; then
    # só o que mudou DEPOIS do snapshot (linha idêntica pré-existente sai)
    new_changes="$(printf '%s\n' "$post_run_git" | grep -vxF -f "$pre_run_git_snapshot" || true)"
  else
    new_changes="$post_run_git"
  fi
  # Padrões de case com `(` de abertura: o bash 3.2 do macOS quebra o parse de
  # `case` DENTRO de $( ) quando o padrão não tem parêntese balanceado — erro
  # só em runtime ("syntax error near unexpected token newline"), bash -n passa.
  touched_protected="$(printf '%s\n' "$new_changes" | awk 'NF {print $NF}' | while IFS= read -r f; do
    while IFS= read -r g || [ -n "$g" ]; do
      case "$g" in (''|'#'*) continue ;; esac
      # shellcheck disable=SC2254 # glob proposital: fnmatch do case, `*` cruza `/`
      case "$f" in ($g) printf '%s\n' "$f"; break ;; esac
    done <"$protected_globs_file"
  done | sort -u)"
  if [ -n "$touched_protected" ]; then
    echo "⚠️  ZONA PROTEGIDA tocada durante o run — revise antes de aceitar:" >&2
    printf '%s\n' "$touched_protected" | sed 's/^/   ⚠️  /' >&2
    oracfit_emit_event protected_paths_alert files="$(printf '%s' "$touched_protected" | tr '\n' ',')" attempt="$attempt"
  fi
fi

final_inbox="$(oracfit_inbox_file "$RUN_ID")"
if [ -s "$final_inbox" ]; then
  oracfit_emit_event message_undelivered count="$(wc -l < "$final_inbox" | tr -d ' ')"
fi

t_run1=$(python3 -c 'import time; print(time.time())')
frontier_wait_s=$(python3 -c "print(round(float('$t_run1')-float('$t_run0'), 3))")
[ -n "$frontier_wait_s" ] || frontier_wait_s=0
# Real cost when the runner reports it (claude-code); otherwise 0 as before (stub/free).
read -r estimated_cost executor_in_tok executor_out_tok < <(python3 - "${ORACFIT_COST_FILE:-}" <<'PY' 2>/dev/null || echo "0 0 0"
import json, sys
c = i = o = 0
try:
    for line in open(sys.argv[1]):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        c += float(d.get("cost_usd") or 0)
        i += int(d.get("in_tok") or 0) + int(d.get("cache_read_tok") or 0) + int(d.get("cache_write_tok") or 0)
        o += int(d.get("out_tok") or 0)
except OSError:
    pass
print(round(c, 6), i, o)
PY
)
[ -n "$estimated_cost" ] || estimated_cost=0

# Quem serviu, veredito da allowlist e sidecar do kernel — mesma leitura do ledger do dispatch.sh.
oracfit_free_path_read "${DISPATCH_EFETIVO_FILE:-}"
oracfit_emit_metric_and_ledger \
  mode_id="$mode_id" \
  stage=run \
  oracle_exit="$oracle_exit" \
  attempt="$attempt" \
  model_id="$model_ref" \
  flash_work_s="$flash_work_s" \
  frontier_wait_s="$frontier_wait_s" \
  estimated_cost="$estimated_cost" \
  executor_in_tok="${executor_in_tok:-0}" \
  executor_out_tok="${executor_out_tok:-0}" \
  task="$task_name" \
  status="$final_status" \
  "${ORACFIT_FREE_FIELDS[@]}"

# Normal close is complete for events: the EXIT/TERM/INT trap becomes a no-op
# so it cannot emit a second run_finished.
epilogue_done=1
oracfit_emit_event run_finished status="$final_status" attempt="$attempt" oracle_exit="$oracle_exit"

# Achado 2026-08-01 (docs-findings/audit-funcionalidades-meio-plugadas.md):
# emit-usage-feedback.sh promete rodar em "todo modo de dispatch"
# (core/feedback-protocol.md) mas nunca era chamado daqui — só pelos fluxos
# legados (dispatch-batch.sh, dispatch-escalate.sh, ledger-finalize.sh). O
# fluxo principal do modo (este arquivo) terminava sem gerar usage.jsonl nem
# incidente de uso. --source mode (novo valor, distingue deste caminho).
usage_result="failed"
[ "$final_status" = "pass" ] && usage_result="success"
[ "$final_status" = "owner_question" ] && usage_result="owner_question"
# NOTA: --mode em emit-usage-feedback.sh e injetado CRU no JSON (sem aspas,
# ver printf em bin/emit-usage-feedback.sh) — espera numero, nao string.
# mode_id do Oracfit e string ("normal", "flash_paid_0731"...): vai no
# extra-json (que E escapado direito), --mode fica de fora (default null).
bash "$ROOT/bin/emit-usage-feedback.sh" \
  --source mode \
  --task "$task_name" \
  --result "$usage_result" \
  --workdir "$ORACFIT_WORKDIR" \
  --spec "$spec_file" \
  --exit-code "$oracle_exit" \
  --extra-json "{\"run_id\":\"$RUN_ID\",\"attempts\":$attempt,\"model_id\":\"$model_ref\",\"mode_id\":\"$mode_id\"}" \
  2>/dev/null || true

echo "run_id: $RUN_ID"
echo "status: $final_status"
echo "attempts: $attempt"
echo "oracle_exit: $oracle_exit"
echo "flash_work_s: $flash_work_s"
echo "frontier_wait_s: $frontier_wait_s"
echo "events: $(oracfit_events_path)"
echo "ledger: $(oracfit_ledger_path)"
if [ "$final_status" = "owner_question" ]; then
  [ -n "$supervisor_question_file" ] \
    || supervisor_question_file="$(oracfit_inbox_dir)/${RUN_ID}.question.md"
  echo "question: $supervisor_question_file"
  echo "resume: oracfit resume $RUN_ID \"<your answer>\""
fi
echo "$CREDIT"

if [ "$final_status" = "pass" ]; then
  exit 0
fi
if [ "$final_status" = "owner_question" ]; then
  exit 7
fi
exit 1
