#!/bin/bash
# dispatch-stages.sh — P5 minimal multi-stage runner (unlock → plan → run, etc.)
#
# Sequential stages from mode YAML. Each stage:
#   - emits stage_changed
#   - writes artifacts under .dispatch/artifacts/<run_id>/<artifacts|role>/
#   - runs DISPATCH_RUNNER once (stub-friendly)
#   - if oracle:true, runs ## Oráculo (or stage proof) with gauntlet inject
# on_fail:halt stops the chain (FR-4: unlock fail never starts run).
#
# Usage: dispatch-stages.sh <mode_id> <spec_file> <task_name> [--workdir DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib-oracfit-root.sh"
source "$SCRIPT_DIR/lib-oracfit-events.sh"
source "$SCRIPT_DIR/lib-oracfit-preflight.sh"
source "$SCRIPT_DIR/lib-oracfit-metrics.sh"
source "$SCRIPT_DIR/lib-oracfit-gauntlet.sh"

oracfit_stages_read_efetivo() {
  PROVIDER_EFETIVO=""
  REF_EFETIVO=""
  if [ -f "${DISPATCH_EFETIVO_FILE:-}" ]; then
    IFS=$'\t' read -r REF_EFETIVO PROVIDER_EFETIVO < "$DISPATCH_EFETIVO_FILE" || true
  fi
}

mode_id=""
spec_file=""
task_name=""
workdir_arg=""
resume_run_id=""

while [ $# -gt 0 ]; do
  case "$1" in
    --workdir) shift; workdir_arg="${1:?}"; shift ;;
    --resume-run-id) shift; resume_run_id="${1:?}"; shift ;;
    -*) echo "Unknown: $1" >&2; exit 2 ;;
    *)
      if [ -z "$mode_id" ]; then mode_id="$1"
      elif [ -z "$spec_file" ]; then spec_file="$1"
      elif [ -z "$task_name" ]; then task_name="$1"
      else echo "extra arg $1" >&2; exit 2
      fi
      shift
      ;;
  esac
done

if [ -n "$workdir_arg" ]; then
  export ORACFIT_WORKDIR="$(cd "$workdir_arg" && pwd -P)"
else
  export ORACFIT_WORKDIR="$(cd "${ORACFIT_WORKDIR:-$PWD}" && pwd -P)"
fi

# Resume (S8/P5): oracfit resume <run_id> roteia pra cá quando o modo é
# multi-stage (bin/oracfit conta os stages). Reconstrói mode/spec/task dos
# arquivos persistidos no inbox pelo run original; o RUN_ID é reaproveitado
# — sem isso a resposta do dono chegaria a um run novo que não fez a pergunta.
if [ -n "$resume_run_id" ]; then
  _inbox="$(oracfit_inbox_dir)"
  [ -z "$mode_id" ] && mode_id="$(cat "$_inbox/${resume_run_id}.mode-id" 2>/dev/null || true)"
  [ -z "$spec_file" ] && spec_file="$(cat "$_inbox/${resume_run_id}.spec-file" 2>/dev/null || true)"
  [ -z "$task_name" ] && task_name="$(cat "$_inbox/${resume_run_id}.task-name" 2>/dev/null || true)"
  if [ -z "$mode_id" ] || [ -z "$spec_file" ] || [ -z "$task_name" ]; then
    echo "ERROR: resume: não achei mode/spec/task persistidos pra run_id $resume_run_id em $_inbox" >&2
    exit 3
  fi
fi

if [ -z "$mode_id" ] || [ -z "$spec_file" ] || [ -z "$task_name" ]; then
  echo "Usage: dispatch-stages.sh <mode_id> <spec_file> <task_name> [--workdir DIR] | --resume-run-id <run_id>" >&2
  exit 2
fi

ROOT="$(oracfit_resolve_root)" || exit 1
export ORACFIT_ROOT="$ROOT"

# S7 (regra 53, mecanismo 1): single-flight por workdir ANTES de qualquer
# preflight/persistência (mesmo contrato do dispatch-mode.sh — lock em um
# entrypoint só não sobreviveria ao exec do cmd_run). Lock: .dispatch/.run-lock.
oracfit_run_lock_acquire
lock_rc=$?
[ "$lock_rc" -eq 0 ] || exit "$lock_rc"
mode_yaml="$ORACFIT_WORKDIR/core/modes/${mode_id}.yaml"
[ -f "$mode_yaml" ] || mode_yaml="$ROOT/core/modes/${mode_id}.yaml"
[ -f "$mode_yaml" ] || { echo "ERROR: mode yaml missing: $mode_id" >&2; exit 3; }
python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" validate "$mode_yaml" || exit $?
[ -n "${DISPATCH_RUNNER:-}" ] || { echo "ERROR: DISPATCH_RUNNER unset" >&2; exit 3; }

spec_file="$(cd "$(dirname "$spec_file")" && pwd)/$(basename "$spec_file")"
[ -f "$spec_file" ] || { echo "ERROR: spec missing" >&2; exit 3; }
export ORACFIT_SPEC_FILE="$spec_file"
export ORACFIT_NICHE="$task_name"
export ORACFIT_NICHE_FOLDER="$(
  ORACFIT_NICHE="$ORACFIT_NICHE" python3 -c '
import os
import re
niche = os.environ["ORACFIT_NICHE"]
folder = re.sub(r"[^\w\s-]", "", niche.lower())
folder = re.sub(r"[-\s]+", "-", folder)
print(folder[:50].strip("-"))
'
)"
[ -n "$ORACFIT_NICHE_FOLDER" ] || {
  echo "ERROR: niche produces an empty sanitized folder: $ORACFIT_NICHE" >&2
  exit 3
}

stages_json=$(python3 "$SCRIPT_DIR/lib-oracfit-mode-loader.py" dump "$mode_yaml")
stage_count=$(printf '%s' "$stages_json" | python3 -c 'import json,sys; print(len(json.load(sys.stdin).get("stages") or []))')
export ORACFIT_PREFLIGHT_STAGE_COUNT="$stage_count"

# Mesmo invariante do dispatch-mode.sh: o diretório de logs do workdir existe
# ANTES de qualquer preflight. Specs de smoke afirmam `.dispatch` como único
# fato garantido de workdir estranho — se o mkdir vier depois do preflight, o
# check-spec-facts reprova fato verdadeiro e o run nem começa (mecanismo em
# bin/lib-oracfit-preflight.sh; incidente
# incidents/2026-07-29-spec-com-dado-inventado-passou-no-gate.md).
mkdir -p "$(oracfit_inbox_dir)"

# Preflight once on base spec
set +e
oracfit_preflight "$spec_file" "$ORACFIT_WORKDIR"
pf=$?
set -e
[ "$pf" -eq 0 ] || exit "$pf"

RUN_ID="$(oracfit_mint_run_id)"
if [ -n "$resume_run_id" ]; then
  RUN_ID="$resume_run_id"
fi
export ORACFIT_RUN_ID="$RUN_ID"
# T20: run-with-fallback writes who served; mode ledger records it (E5).
export DISPATCH_EFETIVO_FILE="$ORACFIT_WORKDIR/.dispatch/pids/mode-${RUN_ID}.efetivo"
mkdir -p "$(dirname "$DISPATCH_EFETIVO_FILE")"
rm -f "$DISPATCH_EFETIVO_FILE"
# Thinking no painel: o tee do runner opencode (oracfit-thinking-tee.py) só emite
# eventos thinking/tool_call com ORACFIT_RUN_ID E ORACFIT_EVENTS_FILE setados.
# dispatch-mode.sh:363 exporta os dois; aqui faltava este — todo run multi-stage
# ficava mudo no feed (incidente 2026-08-12-loop-target-nao-transporta-feedback).
export ORACFIT_EVENTS_FILE="$(oracfit_events_path)"
# Freshness anti-veneno (fit 2026-08-09): T4 aceito pelo oráculo só se mtime >= este
# instante E run_id == $ORACFIT_RUN_ID. O writer do T4 carimba o campo lendo esta env.
export ORACFIT_RUN_STARTED_AT="$(python3 -c 'import time; print(int(time.time()))')"
mkdir -p "$(oracfit_inbox_dir)"
printf '%s' "$mode_id" >"$(oracfit_inbox_dir)/${RUN_ID}.mode-id"
printf '%s' "$spec_file" >"$(oracfit_inbox_dir)/${RUN_ID}.spec-file"
printf '%s' "$task_name" >"$(oracfit_inbox_dir)/${RUN_ID}.task-name"

# Epílogo garantido (família do incidente 2026-08-10-dispatch-mode-run-finished-
# sem-ledger-nem-usage-feedback): se o processo morrer antes do epílogo normal
# (set -e, SIGTERM/SIGINT externo, dispatch pendurado morto de fora), ainda
# emite run_finished + ledger (best effort) + as linhas finais run_id/status.
# O caminho feliz seta epilogue_done=1 e o trap vira no-op. Handler defensivo:
# tudo com || true, nada de set -e matando o trap no meio.
epilogue_done=0
oracfit_stages_emergency_epilogue() {
  [ "${epilogue_done:-0}" = "1" ] && return 0
  epilogue_done=1
  local t_abn dur_abn
  dur_abn=0
  if [ -n "${t0:-}" ]; then
    t_abn="$(python3 -c 'import time; print(time.time())' 2>/dev/null || true)"
    if [ -n "$t_abn" ]; then
      dur_abn="$(python3 -c "print(round(float('$t_abn')-float('$t0'), 3))" 2>/dev/null || echo 0)"
    fi
  fi
  oracfit_emit_event run_finished status=fail reason=abnormal_exit \
    stages="${stage_count:-0}" duration_s="$dur_abn" 2>/dev/null || true
  oracfit_stages_read_efetivo
  oracfit_emit_metric_and_ledger \
    mode_id="${mode_id:-}" \
    stage=multi \
    oracle_exit="${oracle_exit:-1}" \
    attempt="${total_attempt_count:-0}" \
    model_id=multi \
    flash_work_s="$dur_abn" \
    frontier_wait_s=0 \
    estimated_cost=0 \
    task="${task_name:-}" \
    status=fail \
    provider_efetivo="${PROVIDER_EFETIVO}" \
    provider_efetivo_ref="${REF_EFETIVO}" 2>/dev/null || true
  echo "run_id: ${RUN_ID:-}"
  echo "status: fail"
  return 0
}
trap 'oracfit_stages_emergency_epilogue; oracfit_run_lock_release' EXIT
trap 'oracfit_stages_emergency_epilogue; oracfit_run_lock_release; exit 143' TERM
trap 'oracfit_stages_emergency_epilogue; oracfit_run_lock_release; exit 130' INT

on_fail="$(grep -E '^\s*on_fail:' "$mode_yaml" | head -1 | awk '{print $2}' || true)"
on_fail="${on_fail:-halt}"

oracfit_emit_event run_started mode="$mode_id" stage=multi task="$task_name" stages="$stage_count"
echo "dispatch-stages: mode=$mode_id stages=$stage_count run_id=$RUN_ID" >&2

final_status=pass
oracle_exit=0
t0=$(python3 -c 'import time; print(time.time())')

# v3: loop_target do gauntlet (budget global de loops entre stages) + budget.
# Quando um stage com loop_target falha, volta pro stage nomeado em loop_target
# (ex: vision_gate falha → volta pro export). Budget global evita loop infinito
# (Fable ponto extra: 4×4=16 runs pior caso sem teto).
gauntlet_loop_target="$(oracfit_gauntlet_cfg "$mode_yaml" loop_target 2>/dev/null || true)"
gauntlet_ceiling="$(oracfit_gauntlet_cfg "$mode_yaml" safety_ceiling 2>/dev/null || true)"
gauntlet_ceiling="${gauntlet_ceiling:-4}"
global_loop_count=0
seen_stage_roles=""
run_attempt_budget="$(printf '%s' "$stages_json" | python3 -c 'import json,sys; d=json.load(sys.stdin); v=d.get("run_attempt_budget", d.get("global_run_attempt_budget", "")); print(v if v is not None else "")')"
run_attempt_count=0
# métrica: total de tentativas do run (todos os stages) — "attempt" no ledger
# registrava stage_count e divergia do oracle (plano Fable passo 9)
total_attempt_count=0
budget_exhausted=false

i=0
while [ "$i" -lt "$stage_count" ]; do
  role=$(printf '%s' "$stages_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['stages'][$i].get('role',''))")
  model_ref=$(printf '%s' "$stages_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['stages'][$i].get('model_ref',''))")
  # Incidente 2026-08-11-prompt-v3-travelview-espera-override-dis: override por
  # env só onde há modelo (model_ref não-vazio). Stage mecânico NUNCA ganha
  # modelo pelo override — continua mecânico (ramo [ -z "$model_ref" ] abaixo).
  if [ -n "$model_ref" ] && [ -n "${DISPATCH_MODEL_REF:-}" ]; then
    model_ref="$DISPATCH_MODEL_REF"
  fi
  oracle=$(printf '%s' "$stages_json" | python3 -c "import json,sys; v=json.load(sys.stdin)['stages'][$i].get('oracle'); print('true' if v is True or v==True else ('false' if not v else str(v)))")
  artifacts=$(printf '%s' "$stages_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['stages'][$i].get('artifacts') or '')")
  max_attempts=$(printf '%s' "$stages_json" | python3 -c "import json,sys; s=json.load(sys.stdin)['stages'][$i]; print(s.get('max_attempts') or 3)")
  stage_oracle_command="$(printf '%s' "$stages_json" | python3 -c "import json,sys; s=json.load(sys.stdin)['stages'][$i]; v=s.get('oracle'); print(s.get('stage_oracle') or s.get('oracle_command') or (v if isinstance(v,str) and v != 'true' else ''))")"
  stage_preflight_command="$(printf '%s' "$stages_json" | python3 -c "import json,sys; s=json.load(sys.stdin)['stages'][$i]; print(s.get('preflight') or s.get('preflight_command') or '')")"
  # v3: loop_target do stage (fallback pro gauntlet-level). Ex: vision_gate falha
  # → volta pro stage com role=export. Vazio = não volta (comportamento original).
  stage_loop_target="$(printf '%s' "$stages_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['stages'][$i].get('loop_target') or '')")"
  [ -z "$stage_loop_target" ] && stage_loop_target="$gauntlet_loop_target"
  freshness_targets=()
  while IFS= read -r freshness_target; do
    [ -n "$freshness_target" ] && freshness_targets+=("$freshness_target")
  done < <(printf '%s' "$stages_json" | python3 -c "
import json,sys
s = json.load(sys.stdin)['stages'][$i]
targets = s.get('freshness_targets') or s.get('visual_freshness_targets') or []
for target in targets:
    print(target)
")
  art_dir="$ORACFIT_WORKDIR/.dispatch/artifacts/${RUN_ID}/${artifacts:-$role}"
  mkdir -p "$art_dir"
  # S8: pergunta de vida anterior do run_id não vale — o resume reaproveita o
  # diretório de artifacts; sem isto o run pausaria na hora, em loop (a
  # pergunta consumida já está registrada no inbox e não pausa de novo).
  rm -f "$art_dir/owner-question.md"
  # Stub-friendly: export stage context for runner / oracle helpers
  export ORACFIT_STAGE_ROLE="$role"
  export ORACFIT_STAGE_ARTIFACTS="$art_dir"
  # S8: o stage pode declarar owner_question (bool true ou string, ex.: once)
  owner_question_cfg="$(printf '%s' "$stages_json" | python3 -c "import json,sys; v=json.load(sys.stdin)['stages'][$i].get('owner_question'); print('' if not v else ('true' if v is True else str(v)))")"

  oracfit_emit_event stage_changed stage="$role" index="$i"
  echo "── stage $((i+1))/$stage_count role=$role model=$model_ref oracle=$oracle ──" >&2

  gauntlet_dir="$(oracfit_inbox_dir)/${RUN_ID}.${role}.gauntlet"
  mkdir -p "$gauntlet_dir"
  accum="${gauntlet_dir}/feedback.md"
  # Trunca só na PRIMEIRA entrada do stage neste run: na reentrada via loop_target
  # o accum carrega o feedback transferido do stage que falhou — zerar aqui mataria
  # o gap na chegada e o builder editaria cego (incidente 2026-08-12-loop-target-
  # nao-transporta-feedback-entre-stages). bash 3.2: sem array associativo.
  case " $seen_stage_roles " in
    *" $role "*) : ;;
    *) : >"$accum"; seen_stage_roles="$seen_stage_roles $role" ;;
  esac
  gt="${gauntlet_dir}/ground-truth.md"
  oracfit_gauntlet_extract_ground_truth "$spec_file" >"$gt" 2>/dev/null || : >"$gt"

  stage_preflight_failed=false
  if [ "$role" = "run" ] && [ -n "$run_attempt_budget" ] \
    && [ "$run_attempt_count" -ge "$run_attempt_budget" ]; then
    budget_exhausted=true
    stage_preflight_failed=true
    echo "ERROR: global run-attempt budget exhausted ($run_attempt_count/$run_attempt_budget); halting before stage $role" >&2
  fi
  if ! $stage_preflight_failed && [ -n "$stage_preflight_command" ]; then
    echo "stage $role: running preflight" >&2
    set +e
    ( cd "$ORACFIT_WORKDIR" && eval "$stage_preflight_command" ) \
      >"${gauntlet_dir}/preflight.log" 2>&1
    stage_preflight_rc=$?
    set -e
    if [ "$stage_preflight_rc" -ne 0 ]; then
      stage_preflight_failed=true
      echo "ERROR: stage $role preflight failed; no attempts started." >&2
      echo "HINT: fix the stage dependency/preflight and retry; see ${gauntlet_dir}/preflight.log" >&2
      cat "${gauntlet_dir}/preflight.log" >&2 || true
    fi
  fi

  attempt=0
  stage_ok=false
  while ! $stage_preflight_failed && [ "$attempt" -lt "$max_attempts" ]; do
    attempt=$((attempt + 1))
    total_attempt_count=$((total_attempt_count + 1))
    if [ "$role" = "run" ]; then
      if [ -n "$run_attempt_budget" ] \
        && [ "$run_attempt_count" -ge "$run_attempt_budget" ]; then
        budget_exhausted=true
        echo "ERROR: global run-attempt budget exhausted ($run_attempt_count/$run_attempt_budget); preserving artifacts" >&2
        break
      fi
      run_attempt_count=$((run_attempt_count + 1))
    fi
    run_spec="$spec_file"
    # S8: pergunta já feita neste run_id? (inbox registra a consumida — uma
    # pergunta por run; depois disso o oráculo governa)
    owner_asked=false
    [ -f "$(oracfit_inbox_dir)/${RUN_ID}.question.md" ] && owner_asked=true
    inbox_jsonl="$(oracfit_inbox_file "$RUN_ID")"
    if [ -s "$accum" ] || [ -s "$gt" ] || { [ -n "$owner_question_cfg" ] && ! $owner_asked; } || [ -s "$inbox_jsonl" ]; then
      composed="$(mktemp "${TMPDIR:-/tmp}/oracfit-stage-XXXXXX")"
      {
        cat "$spec_file"
        echo ""
        echo "## Stage context (Oracfit multi-stage)"
        echo "- role: $role"
        echo "- artifacts_dir: \`$art_dir\`"
        echo "- Write stage proof to that directory if you are the stub/builder."
        if [ -n "$owner_question_cfg" ] && ! $owner_asked; then
          cat <<'OQ'

## Pergunta do dono (contrato — só se bloqueado em fato que só o dono tem)
Se você está bloqueado por um fato que só o dono tem, NÃO invente e NÃO
queime a tentativa adivinhando: escreve owner-question.md no seu
artifacts_dir com EXATAMENTE este formato:

pergunta: <uma pergunta única, o fato que só o dono tem>
se <resposta A> -> <o que você faz se A>
se <resposta B> -> <o que você faz se B>

Mínimo DUAS linhas "se ... -> ..." (o garfo de consequências anexado —
pergunta sem garfo é ignorada). O run pausa para o dono responder e retoma
com a resposta injetada aqui. UMA pergunta por run: depois dela, o oráculo
governa como sempre.
OQ
        fi
        if [ -s "$gt" ]; then
          echo ""
          echo "<!-- oracfit-ground-truth -->"
          echo "## GROUND TRUTH"
          cat "$gt"
        fi
        if [ -s "$accum" ]; then
          echo ""
          cat "$accum"
        fi
        if [ -s "$inbox_jsonl" ]; then
          echo ""
          echo "## Mensagem do humano (recebida durante a execução, attempt $attempt)"
          echo ""
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
' "$inbox_jsonl"
        fi
      } >"$composed"
      run_spec="$composed"
      if [ -s "$inbox_jsonl" ]; then
        oracfit_emit_event message_consumed attempt="$attempt" count="$(wc -l < "$inbox_jsonl" | tr -d ' ')"
        : >"$inbox_jsonl"
      fi
    fi

    export ORACFIT_SESSION_FILE="$(oracfit_session_file "$RUN_ID")"
    set +e
    # v3: stage mecânico (sem model_ref) roda command do YAML do stage direto,
    # sem despachar pro $DISPATCH_RUNNER. Pra stages como export/render/vision_gate
    # que são scripts, não chamadas de LLM. O command vem do campo 'command:' do stage.
    stage_command="$(printf '%s' "$stages_json" | python3 -c "import json,sys; print(json.load(sys.stdin)['stages'][$i].get('command') or '')")"
    export ORACFIT_STAGE_ATTEMPT="$attempt"
    # Capture the start after the attempt prompt is composed and immediately
    # before the stage command. Visual gates compare mtime against this value.
    export ORACFIT_STAGE_STARTED_AT="$(python3 -c 'import time; print(f"{time.time():.6f}")')"
    freshness_cleanup_rc=0
    if [ "${#freshness_targets[@]}" -gt 0 ]; then
      oracfit_visual_freshness_clean "${freshness_targets[@]}" \
        >"${gauntlet_dir}/freshness-clean-${attempt}.log" 2>&1
      freshness_cleanup_rc=$?
    fi
    runner_rc=1
    if [ "$freshness_cleanup_rc" -eq 0 ]; then
      if [ -z "$model_ref" ]; then
        # Stage mecânico: roda o command do YAML. Se vazio, cai pro comando do spec.
        if [ -z "$stage_command" ]; then
          stage_command="$(grep -iE '^[-*][[:space:]]*comando:' "$run_spec" | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I')"
        fi
        if [ -n "$stage_command" ]; then
          echo "mechanical stage $role: running command" >&2
          ( cd "$ORACFIT_WORKDIR" && eval "$stage_command" ) >"${gauntlet_dir}/mech-${attempt}.log" 2>&1
          runner_rc=$?
        else
          echo "ERROR: mechanical stage $role sem command no YAML nem comando no spec" >&2
          runner_rc=1
        fi
      else
        # Tee de thinking (paridade com dispatch-mode.sh): traduz o stream
        # JSON do opencode pra prosa no runner log E emite eventos
        # thinking/tool_call no events.jsonl (precisa de ORACFIT_RUN_ID +
        # ORACFIT_EVENTS_FILE, exportados acima). Sem o tee, o painel não
        # mostra thinking em run multi-stage.
        # Incidente 2026-08-30-unlock-plan-passa-tier-ao-runner-sem-res
        # (B2/E5-M4): tier:* não é id — expande pela cadeia do catálogo
        # free carimbado em vez de entregar string cru ao runner (exit 3).
        case "$model_ref" in
          tier:*) STAGE_RUNNER="$SCRIPT_DIR/run-with-fallback.sh" ;;
          *)      STAGE_RUNNER="$DISPATCH_RUNNER" ;;
        esac
        "$STAGE_RUNNER" "$model_ref" "$run_spec" 2>&1 \
          | "$SCRIPT_DIR/oracfit-thinking-tee.py" >"${gauntlet_dir}/runner-${attempt}.log"
        runner_rc=${PIPESTATUS[0]}
      fi
    else
      echo "ERROR: could not remove stale visual evidence before stage $role attempt $attempt" >&2
      runner_rc=1
    fi
    set -e
    [ "$run_spec" != "$spec_file" ] && rm -f "$run_spec"
    unset ORACFIT_SESSION_FILE

    # Stub enhancement: also write per-stage proof
    if [ -f "$ORACFIT_WORKDIR/.dispatch/stub-proof" ]; then
      cp "$ORACFIT_WORKDIR/.dispatch/stub-proof" "$art_dir/stub-proof"
      echo "stage_role=$role" >>"$art_dir/stub-proof"
    fi

    # S8 — a pergunta do dono: checada DEPOIS do runner e ANTES do oráculo.
    # Pergunta válida (pergunta: + garfo >=2 linhas "se ... -> ...") pausa o
    # run INTEIRO com status owner_question (exit 7): nenhuma tentativa cara
    # adicional é queimada preenchendo o buraco com invenção. A pergunta vai
    # pro inbox; o dono responde com oracfit resume <run_id> "<resposta>" e o
    # run retoma com a resposta injetada na spec do próximo attempt.
    if [ -n "$owner_question_cfg" ] && ! $owner_asked && [ -f "$art_dir/owner-question.md" ]; then
      _oq_forks="$(grep -cE '^se .+ -> ' "$art_dir/owner-question.md" || true)"
      if grep -q '^pergunta: .' "$art_dir/owner-question.md" && [ "${_oq_forks:-0}" -ge 2 ]; then
        cp "$art_dir/owner-question.md" "$(oracfit_inbox_dir)/${RUN_ID}.question.md"
        oracfit_emit_event owner_question stage="$role" attempt="$attempt" file="${RUN_ID}.question.md"
        t_oq=$(python3 -c 'import time; print(time.time())')
        dur_oq=$(python3 -c "print(round(float('$t_oq')-float('$t0'), 3))")
        oracfit_emit_event run_finished status=owner_question stages="$stage_count" duration_s="$dur_oq"
        oracfit_stages_read_efetivo
        oracfit_emit_metric_and_ledger \
          mode_id="$mode_id" \
          stage=multi \
          oracle_exit=7 \
          attempt="$total_attempt_count" \
          model_id=multi \
          flash_work_s="$dur_oq" \
          frontier_wait_s=0 \
          estimated_cost=0 \
          task="$task_name" \
          status=owner_question \
          provider_efetivo="${PROVIDER_EFETIVO}" \
          provider_efetivo_ref="${REF_EFETIVO}" || true
        epilogue_done=1
        echo "run_id: $RUN_ID"
        echo "status: owner_question (pausado — pergunta do dono no inbox)"
        echo "pergunta: $(oracfit_inbox_dir)/${RUN_ID}.question.md"
        echo "responda: oracfit resume $RUN_ID \"<sua resposta>\""
        exit 7
      else
        echo "owner-question.md malformado (sem linha 'pergunta:' ou garfo < 2 linhas 'se ... -> ...') — ignorado; o oráculo governa" >&2
      fi
    fi

    oracle_log="${gauntlet_dir}/oracle-${attempt}.log"
    if [ "$runner_rc" -ne 0 ]; then
      # Sinal do false-green guard vai DIRETO pro console: o gap extraído pelo
      # gauntlet agora pula boilerplate (incidente 2026-08-12-biggest-gap) e
      # não repete mais esta linha.
      echo "STAGE COMMAND FAILED: role=$role attempt=$attempt exit=$runner_rc" >&2
      {
        echo "STAGE COMMAND FAILED: role=$role attempt=$attempt exit=$runner_rc"
        echo "The stage oracle and ordinary spec oracle were skipped."
        if [ -s "${gauntlet_dir}/mech-${attempt}.log" ]; then
          cat "${gauntlet_dir}/mech-${attempt}.log"
        fi
        if [ -s "${gauntlet_dir}/runner-${attempt}.log" ]; then
          cat "${gauntlet_dir}/runner-${attempt}.log"
        fi
        if [ -s "${gauntlet_dir}/freshness-clean-${attempt}.log" ]; then
          cat "${gauntlet_dir}/freshness-clean-${attempt}.log"
        fi
      } >"$oracle_log"
      oracle_exit="$runner_rc"
    else
    set +e
    # ADR-0004: visual freshness is a deterministic stage gate, before any
    # custom stage oracle and before the ordinary spec oracle.
    stage_oracle_exit=0
    if [ "${#freshness_targets[@]}" -gt 0 ]; then
      oracfit_visual_freshness_gate "${freshness_targets[@]}" \
        >"${oracle_log}.visual-freshness" 2>&1
      stage_oracle_exit=$?
    fi
    if [ "$stage_oracle_exit" -eq 0 ] && [ -n "$stage_oracle_command" ]; then
      ( cd "$ORACFIT_WORKDIR" && eval "$stage_oracle_command" ) \
        >"${oracle_log}.stage" 2>&1
      stage_oracle_exit=$?
    fi
    if [ "$stage_oracle_exit" -ne 0 ]; then
      {
        echo "STAGE ORACLE FAILED: role=$role attempt=$attempt exit=$stage_oracle_exit"
        if [ -s "${oracle_log}.visual-freshness" ]; then
          cat "${oracle_log}.visual-freshness"
        fi
        if [ -s "${oracle_log}.stage" ]; then
          cat "${oracle_log}.stage"
        fi
      } >"$oracle_log"
      oracle_exit="$stage_oracle_exit"
    elif [ "$oracle" != "true" ]; then
      # A stage with only a deterministic stage oracle has no ordinary spec
      # oracle. Its success is the stage oracle's exit 0, never the runner rc.
      oracle_exit=0
    else
    # Freshness gate anti-veneno (fit 2026-08-09): se a spec declara `freshness_target:`,
    # resolva o path relativo ao workdir e confirme que o T4 é fresco DESTE run ANTES
    # do `comando:` rodar — senão o grep APPROVED passa num arquivo velho de run
    # anterior (veneno). Gate reprova sem rodar o oráculo, e o feedback explica o motivo.
    oracle_precheck=0
    ft_rel="$(oracfit_gauntlet_freshness_target "$spec_file")"
    ft_path=""
    if [ -n "$ft_rel" ]; then
      ft_path="$ORACFIT_WORKDIR/$ft_rel"
      # Permite override explícito via env (specs sem a linha freshness_target).
      : "${ORACFIT_FRESHNESS_TARGET:="$ft_path"}"
    fi
    if [ -n "${ORACFIT_FRESHNESS_TARGET:-}" ] && [ -e "${ORACFIT_FRESHNESS_TARGET}" ]; then
      oracfit_gauntlet_freshness_gate "${ORACFIT_FRESHNESS_TARGET}" 2>"${oracle_log}.freshness"
      oracle_precheck=$?
      if [ "$oracle_precheck" -ne 0 ]; then
        {
          echo "FRESHNESS GATE REJECTED: ${ORACFIT_FRESHNESS_TARGET}"
          echo "T4 não é deste run (run_id divergente/ausente ou mtime < ORACFIT_RUN_STARTED_AT)."
          echo "Suspeita: arquivo de run anterior servindo de veneno. Refaça o T4."
        } >"$oracle_log"
        oracle_exit=1
      fi
    fi
    if [ "$oracle_precheck" -eq 0 ]; then
      oracfit_gauntlet_run_oracle_capture "$spec_file" "$ORACFIT_WORKDIR" "$oracle_log"
      oracle_exit=$?
    fi
    fi
    set -e
    fi
    oracfit_emit_event oracle_result exit="$oracle_exit" attempt="$attempt" stage="$role"

    if [ "$oracle_exit" -eq 0 ]; then
      stage_ok=true
      break
    fi
    if [ "$attempt" -lt "$max_attempts" ]; then
      gap="$(oracfit_gauntlet_append_feedback "$accum" "$attempt" "$oracle_exit" "$oracle_log")"
      echo "gauntlet stage=$role attempt=$attempt gap=$gap" >&2
      # Critic estruturado (fit 2026-08-09, passo 3): se o mode declara critic_model_ref,
      # despacha um mini-spec via $DISPATCH_RUNNER para um modelo forte analisar a reprovação
      # e produzir feedback estruturado (sobrescreve o gap heurístico se achar um melhor).
      # Sem critic_model_ref → fica só o feedback heurístico acima (comportamento anterior).
      barra_file="${gauntlet_dir}/barra.md"
      oracfit_gauntlet_extract_barra "$spec_file" >"$barra_file" 2>/dev/null || : >"$barra_file"
      # stderr do critic passa direto (uma linha de timeout/skip é observável);
      # || true mantém o fail open: critic nunca derruba o stage loop.
      critic_gap="$(oracfit_gauntlet_run_critic "$mode_yaml" "$model_ref" "$oracle_log" "$accum" "$attempt" "$barra_file" || true)"
      [ -n "$critic_gap" ] && gap="$critic_gap" && echo "gauntlet stage=$role attempt=$attempt critic_gap=$gap" >&2
    fi
  done
  if [ "$role" = "run" ] && [ -n "$run_attempt_budget" ] \
    && [ "$run_attempt_count" -ge "$run_attempt_budget" ] && ! $stage_ok; then
    budget_exhausted=true
    echo "ERROR: global run-attempt budget exhausted after stage $role; preserving artifacts" >&2
  fi
  # Freshness target é por-spec/stage; não vaza para o próximo stage.
  unset ORACFIT_FRESHNESS_TARGET
  unset ORACFIT_STAGE_STARTED_AT

  if ! $stage_ok; then
    if $budget_exhausted; then
      final_status=fail
      echo "ERROR: global run-attempt budget exhausted; halting with artifacts preserved" >&2
      break
    fi
    if $stage_preflight_failed; then
      final_status=fail
      echo "ERROR: stage $role preflight failed; halting before any loop-back" >&2
      break
    fi
    # v3: loop_target — se o stage falhou mas tem loop_target E há budget global,
    # volta pro stage nomeado (ex: vision_gate falha → volta pro export).
    # Fable ponto extra: sem budget global, 4×4=16 runs = tarde de flash desperdiçada.
    if [ -n "$stage_loop_target" ] && [ "$global_loop_count" -lt "$gauntlet_ceiling" ]; then
      global_loop_count=$((global_loop_count + 1))
      # Acha o índice do stage com role == loop_target.
      loop_i=$(printf '%s' "$stages_json" | python3 -c "
import json,sys
stages = json.load(sys.stdin).get('stages') or []
target = '$stage_loop_target'
for idx, s in enumerate(stages):
    if s.get('role') == target:
        print(idx); break
else:
    print(-1)
")
      if [ "$loop_i" -ge 0 ] && [ "$loop_i" -lt "$i" ]; then
        # O gap do stage que falhou PRECISA viajar até o stage alvo — sem isso o
        # builder recompõe com o spec original e o loop nunca converge (incidente
        # 2026-08-12-loop-target-nao-transporta-feedback-entre-stages: run 9D9CCFA4
        # queimou 5/5 loops cego). Se o accum da origem está vazio (falha no
        # attempt == max_attempts não passa pelo append do attempt-loop), gera o
        # bloco agora a partir do último oracle_log.
        target_accum="$(oracfit_inbox_dir)/${RUN_ID}.${stage_loop_target}.gauntlet/feedback.md"
        mkdir -p "$(dirname "$target_accum")"
        if [ -s "$accum" ]; then
          cat "$accum" >>"$target_accum"
          : >"$accum"
        elif [ -s "$oracle_log" ]; then
          oracfit_gauntlet_append_feedback "$target_accum" "$attempt" "$oracle_exit" "$oracle_log" >/dev/null 2>&1 || true
        fi
        echo "gauntlet: stage $role failed → looping back to $stage_loop_target (idx $loop_i, global loop $global_loop_count/$gauntlet_ceiling)" >&2
        oracfit_emit_event gauntlet_loop_back from="$role" to="$stage_loop_target" count="$global_loop_count" ceiling="$gauntlet_ceiling"
        i="$loop_i"
        continue
      fi
    fi
    final_status=fail
    echo "ERROR: stage $role failed after $max_attempts attempts" >&2
    if [ "$on_fail" = "halt" ]; then
      break
    fi
  fi
  i=$((i + 1))
done

t1=$(python3 -c 'import time; print(time.time())')
dur=$(python3 -c "print(round(float('$t1')-float('$t0'), 3))")
oracfit_emit_event run_finished status="$final_status" stages="$stage_count" duration_s="$dur"
oracfit_stages_read_efetivo
oracfit_emit_metric_and_ledger \
  mode_id="$mode_id" \
  stage=multi \
  oracle_exit="$oracle_exit" \
  attempt="$total_attempt_count" \
  model_id=multi \
  flash_work_s="$dur" \
  frontier_wait_s=0 \
  estimated_cost=0 \
  task="$task_name" \
  status="$final_status" \
  provider_efetivo="${PROVIDER_EFETIVO}" \
  provider_efetivo_ref="${REF_EFETIVO}" || true

# Tier-0 behavior scan (advisory — nunca altera exit code do dispatch).
_behavior_events="$(oracfit_events_path 2>/dev/null || true)"
if [ -n "${_behavior_events:-}" ] && [ -f "$_behavior_events" ]; then
  _behavior_gauntlet=""
  [ -d "$ORACFIT_WORKDIR/.dispatch/logs" ] && _behavior_gauntlet="$ORACFIT_WORKDIR/.dispatch/logs"
  _behavior_flags=""
  _behavior_flags="$(
    python3 "$ORACFIT_ROOT/bin/oracfit-behavior-scan.py" "$_behavior_events" \
      --run-id "$RUN_ID" \
      ${_behavior_gauntlet:+--gauntlet-dir "$_behavior_gauntlet"} 2>/dev/null || true
  )"
  if [ -n "$_behavior_flags" ]; then
    _behavior_nflags="$(printf '%s\n' "$_behavior_flags" | sed '/^$/d' | wc -l | tr -d ' ')"
    _behavior_nhigh="$(printf '%s\n' "$_behavior_flags" | python3 -c '
import json, sys
n = 0
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        if json.loads(line).get("severity") == "high":
            n += 1
    except json.JSONDecodeError:
        pass
print(n)
' 2>/dev/null || echo 0)"
    oracfit_emit_event behavior_scan flags="$_behavior_nflags" high="$_behavior_nhigh" 2>/dev/null || true
    echo "WARNING: behavior scan flagged $_behavior_nflags pattern(s) ($_behavior_nhigh high)" >&2
  fi
fi

# Epílogo normal completo — o trap de emergência (EXIT/TERM/INT) vira no-op.
epilogue_done=1
echo "run_id: $RUN_ID"
echo "status: $final_status"
[ "$final_status" = "pass" ] && exit 0
exit 1
