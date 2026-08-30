#!/bin/bash
# dispatch-escalate.sh — Mode 2: Flash → DeepSeek V4 Pro com detecção de travamento
#
# Uso: bin/dispatch-escalate.sh <spec_file> <task_name> [--mode 1|2|3] [--workdir DIR]
#
# O loop entre execute e verify:
#   1. Despacha pro modelo do tier atual
#   2. Roda o oráculo (extraído da spec)
#   3. Se passou → done
#   4. Se falhou → captura assinatura do erro
#   5. Se erros consecutivos são similares (modelo travado) → escala pro próximo tier
#   6. Se tentativas por tier esgotaram → escala
#   7. Se tier máximo falhou → blocked
#
# Modes:
#   1 = só Flash (sem escalonamento, max_attempts=3)
#   2 = Flash → DeepSeek V4 Pro (mesmo family, contexto acumulado)
#   3 = Flash → DeepSeek V4 Pro → Opus (orquestração completa)
#
# Exit: 0=sucesso, 1=falhou, 2=rate-limit, 3=erro de uso, 4=quota

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib-oracfit-gauntlet.sh
source "$REPO_ROOT/bin/lib-oracfit-gauntlet.sh"
# shellcheck source=lib-oracfit-preflight.sh
source "$REPO_ROOT/bin/lib-oracfit-preflight.sh"

SPEC_FILE="${1:?Uso: dispatch-escalate.sh <spec_file> <task_name> [--mode 1|2|3] [--workdir DIR]}"
TASK_NAME="${2:?Uso: dispatch-escalate.sh <spec_file> <task_name> [--mode 1|2|3] [--workdir DIR]}"
shift 2

MODE=2
WORKDIR=""
MAX_PER_TIER=3
SIMILARITY_THRESHOLD=3

# Regra 12 (mapa-regras): "dispatch-escalate.sh chamado direto continua sem
# teto" era dívida declarada. Todo call-site de modelo abaixo ganha teto-árvore
# via with-timeout.sh (mata o GRUPO — neto não segura o pipe). Exit 124 =
# estouro, contado como tentativa que falhou, nunca como sucesso silencioso.
ESCALATE_TIMEOUT="${DISPATCH_TIMEOUT:-1200}"
WT="$REPO_ROOT/bin/with-timeout.sh"

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:?--mode requer 1|2|3}"; shift 2 ;;
    --workdir) WORKDIR="${2:?--workdir requer DIR}"; shift 2 ;;
    --max-per-tier) MAX_PER_TIER="${2:?}"; shift 2 ;;
    *) echo "flag desconhecida: $1" >&2; exit 3 ;;
  esac
done

[ -f "$SPEC_FILE" ] || { echo "spec não encontrada: $SPEC_FILE" >&2; exit 3; }

# Immutable base for gauntlet compose (never append to escalate in a chain).
ORIGINAL_SPEC="$(cd "$(dirname "$SPEC_FILE")" && pwd)/$(basename "$SPEC_FILE")"
SPEC_FILE="$ORIGINAL_SPEC"

LOG_DIR="${LOG_DIR:-$REPO_ROOT/.dispatch/logs}"
mkdir -p "$LOG_DIR"
GAUNTLET_ACCUM="$LOG_DIR/${TASK_NAME}.gauntlet-feedback.md"
: >"$GAUNTLET_ACCUM"

ORACLE_CMD=$(grep -A1 '^\- comando:' "$SPEC_FILE" | head -1 | sed 's/^- comando: *//' | sed 's/^`//' | sed 's/`$//')
if [ -z "$ORACLE_CMD" ]; then
  echo "dispatch-escalate: spec sem oráculo (linha '- comando:'). Use check-spec.sh." >&2
  exit 3
fi

BARRA="$(oracfit_gauntlet_extract_barra "$ORIGINAL_SPEC" || true)"
if [ -n "$BARRA" ]; then
  echo "gauntlet barra: $(printf '%s' "$BARRA" | head -1 | cut -c1-120)"
else
  echo "gauntlet: sem ## Barra na spec — metric = só o oráculo"
fi
# Incidente 2026-08-12-dispatch-escalate-chama-opencode-cru-sem: os defaults
# antigos (openrouter/deepseek/deepseek-v4-flash[,-pro]) NÃO existem no
# catálogo do opencode — model id inválido imprime o help do yargs e sai em
# ~0s, e o loop escalava tier achando "modelo travado". IDs abaixo verificados
# com `opencode models` (2026-08-12) e registrados no model-registry.json.
# E5-M3 (2026-08-31): opencode/deepseek-v4-flash-free morreu do catálogo do
# opencode (hint FANTASMA stampado; id removido do registry) — L1 agora é o
# free vivo, verificado em `opencode models` e no audit.
case "$MODE" in
  1) TIERS=("opencode/nemotron-3-ultra-free") ;;
  2) TIERS=("opencode/nemotron-3-ultra-free" "opencode/deepseek-v4-pro") ;;
  3) TIERS=("opencode/nemotron-3-ultra-free" "opencode/deepseek-v4-pro" "claude:opus") ;;
  *) echo "mode inválido: $MODE (use 1, 2 ou 3)" >&2; exit 3 ;;
esac
# Incidente 2026-08-11-dispatch-batch-v2-2-hardcoded-tiers-open: tiers eram fixos
# no case acima. DISPATCH_TIERS (lista separada por espaço de model refs) substitui
# TIERS quando definida e não-vazia, na ordem dada.
if [ -n "${DISPATCH_TIERS:-}" ]; then
  # shellcheck disable=SC2206
  TIERS=($DISPATCH_TIERS)
fi

dispatch_model() {
  local model="$1" spec="$2" task="$3" attempt="$4" tier_name="$5"
  local log="$LOG_DIR/${task}-${tier_name}-${attempt}.log"

  case "$model" in
    claude:*)
      local claude_model="${model#claude:}"
      echo "  → despachando claude ($claude_model), tentativa $attempt..."
      if [ -n "$WORKDIR" ]; then
        (cd "$WORKDIR" && bash "$WT" "$ESCALATE_TIMEOUT" claude -p --model "$claude_model" --dangerously-skip-permissions "$(cat "$spec")" > "$log" 2>&1)
      else
        bash "$WT" "$ESCALATE_TIMEOUT" claude -p --model "$claude_model" --dangerously-skip-permissions "$(cat "$spec")" > "$log" 2>&1
      fi
      ;;
    *)
      # Incidente 2026-08-12-dispatch-escalate-chama-opencode-cru-sem: o call
      # site cru sem `--` fazia spec com frontmatter YAML (`---`) virar flag
      # do yargs → help + exit em ~0s, disfarçado de modelo travado. Com
      # DISPATCH_RUNNER ativo (source adapters/<cli>/env.sh) o runner resolve
      # o model id pelo registry, põe o `--` e reporta rate limit ao
      # usage-hub. Sem runner, chamada crua ganha o `--` que faltava.
      if [ -n "${DISPATCH_RUNNER:-}" ]; then
        echo "  → despachando via runner ($model), tentativa $attempt..."
        ORACFIT_WORKDIR="${WORKDIR:-$PWD}" bash "$WT" "$ESCALATE_TIMEOUT" "$DISPATCH_RUNNER" "$model" "$spec" > "$log" 2>&1
      elif [ -n "$WORKDIR" ]; then
        echo "  → despachando opencode cru ($model), tentativa $attempt..."
        (cd "$WORKDIR" && bash "$WT" "$ESCALATE_TIMEOUT" opencode run --auto --model "$model" -- "$(cat "$spec")" > "$log" 2>&1)
      else
        echo "  → despachando opencode cru ($model), tentativa $attempt..."
        bash "$WT" "$ESCALATE_TIMEOUT" opencode run --auto --model "$model" -- "$(cat "$spec")" > "$log" 2>&1
      fi
      ;;
  esac
  local exit_code=$?
  echo "$log"
  return $exit_code
}

run_oracle() {
  if [ -n "$WORKDIR" ]; then
    (cd "$WORKDIR" && eval "$ORACLE_CMD" > /dev/null 2>&1)
  else
    eval "$ORACLE_CMD" > /dev/null 2>&1
  fi
  return $?
}

# ── Gate visual por gatilho de diff (v4, fase 5: mesmo predicado do ring) ────
# Oráculo verde não prova tela: 3 telas foram shipped sem nenhum render
# (docs/v4-plan.md, classe 5). Se o trabalho no workdir tocou artefato visual,
# sucesso exige evidência:
#   - >=1 arquivo em GAUNTLET_SCREENS_DIR (paridade com o ring close);
#   - se o par canônico desktop-full.png + mobile-full.png existir, o juiz por
#     fatias (bin/vision-gate-slices.sh) decide — veredito já parseado a exit
#     code, gap na última linha "VISION GATE REJECTED:", que é exatamente a
#     linha que oracfit_gauntlet_biggest_gap prefere ao montar o feedback.
# GAUNTLET_VISUAL_GLOBS sobrescreve o predicado; VAZIO desliga deliberadamente
# (mesma semântica de visual_globs:[] no state.json do ring).
# Saída no stdout (vai para o log da tentativa); rc 0=passa, 1=reprova.
gauntlet_visual_gate() {
  local wd="${WORKDIR:-$PWD}" changed hits screens nshots
  changed=$( (cd "$wd" && git status --porcelain 2>/dev/null | awk '{print $NF}') || true)
  [ -n "$changed" ] || return 0
  if [ -n "${GAUNTLET_VISUAL_GLOBS+x}" ]; then
    hits=$(printf '%s\n' "$changed" | oracfit_visual_hits "$GAUNTLET_VISUAL_GLOBS")
  else
    hits=$(printf '%s\n' "$changed" | oracfit_visual_hits)
  fi
  [ -n "$hits" ] || return 0
  screens="${GAUNTLET_SCREENS_DIR:-}"
  if [ -z "$screens" ] || [ ! -d "$screens" ]; then
    echo "VISION GATE REJECTED: diff tocou artefato visual ($(printf '%s' "$hits" | head -3 | tr '\n' ' ')) sem nenhum screenshot — renderize a tela de verdade e salve em GAUNTLET_SCREENS_DIR"
    return 1
  fi
  nshots=$(find "$screens" -type f | wc -l | tr -d ' ')
  if [ "$nshots" -eq 0 ]; then
    echo "VISION GATE REJECTED: GAUNTLET_SCREENS_DIR ($screens) está vazio — renderize a tela de verdade antes de fechar"
    return 1
  fi
  if [ -f "$screens/desktop-full.png" ] && [ -f "$screens/mobile-full.png" ]; then
    bash "$REPO_ROOT/bin/vision-gate-slices.sh" "$screens"
    return $?
  fi
  echo "gate visual: ${nshots} screenshot(s) em $screens (sem par full-page — juiz por fatias não rodou)"
  return 0
}

# Debug barato (incidente override): ecoa os tiers no stderr no início do run,
# pra teste poder validá-los sem despachar modelo de verdade.
printf '[dispatch-escalate] tiers=%s\n' "${TIERS[*]}" >&2

# A assinatura SEMPRE inclui o exit code, não só a saída.
#
# Por quê: oráculo bem escrito é silencioso. `test "$(grep ... | wc -l)" = "0"
# && tsc --noEmit` não imprime nada quando falha — `test` é mudo e `tsc` só
# fala quando acha erro. A versão anterior capturava só stdout+stderr, então a
# assinatura vinha VAZIA, e `errors_similar` retorna 1 para vazio: o detector
# de travamento nunca disparava, o loop queimava MAX_PER_TIER × tiers inteiro,
# e o registro `blocked` saía com `last_error:""` — sem causa registrada.
#
# Medido em 2026-07-29: o dispatch `context-dump` gravou
# {"result":"blocked","tiers_used":2,"total_s":317,"last_error":""}. Quanto
# MELHOR o oráculo (silencioso, só exit code), PIOR o loop se comportava —
# exatamente ao contrário do que a doutrina do framework pede.
#
# É a mesma classe de bug do sensor cego que o dispatch 2.0 corrigiu no
# ledger (exit_status="ok" sempre), agora na camada de escalonamento.
capture_error_signature() {
  # Redireciona para arquivo em vez de pipe: `out=$(cmd | head)` faz $? e
  # PIPESTATUS se referirem à ATRIBUIÇÃO, não ao oráculo — a primeira versão
  # deste fix reportava oracle_exit=0 para oráculo que falhava.
  local tmp rc
  tmp=$(mktemp)
  if [ -n "$WORKDIR" ]; then
    ( cd "$WORKDIR" && eval "$ORACLE_CMD" ) >"$tmp" 2>&1
    rc=$?
  else
    eval "$ORACLE_CMD" >"$tmp" 2>&1
    rc=$?
  fi
  # exit code primeiro: é o único componente garantido. Oráculo silencioso
  # produz assinatura "oracle_exit=1", que é comparável e informativa.
  printf 'oracle_exit=%s\n' "$rc"
  head -20 "$tmp"
  rm -f "$tmp"
  return 0
}

errors_similar() {
  local sig1="$1" sig2="$2"
  [ -z "$sig1" ] && return 1
  [ -z "$sig2" ] && return 1
  [ "$sig1" = "$sig2" ] && return 0
  local total lines_same
  total=$(echo "$sig1" | wc -l)
  lines_same=$(comm -12 <(echo "$sig1" | sort) <(echo "$sig2" | sort) | wc -l)
  [ "$total" -eq 0 ] && return 1
  [ $((lines_same * 100 / total)) -ge 70 ] && return 0
  return 1
}

tier_label() {
  case "$1" in
    *flash*) echo "flash" ;;
    *v4-pro*) echo "pro" ;;
    *sonnet*) echo "sonnet" ;;
    *opus*) echo "opus" ;;
    *) echo "tier" ;;
  esac
}

# Regra 41: todo término de escalate emite telemetria + incidente de uso.
# Não depende de humano pedir feedback. Opt-out: DISPATCH_USAGE_FEEDBACK=0
emit_usage() {
  local result="$1" exit_code="${2:-}"
  local extra="${3:-{}}"
  local args=(
    --source escalate
    --task "$TASK_NAME"
    --result "$result"
    --mode "$MODE"
    --spec "$SPEC_FILE"
    --oracle "$ORACLE_CMD"
    --extra-json "$extra"
  )
  [ -n "${WORKDIR:-}" ] && args+=(--workdir "$WORKDIR")
  [ -n "${exit_code:-}" ] && args+=(--exit-code "$exit_code")
  bash "$REPO_ROOT/bin/emit-usage-feedback.sh" "${args[@]}" 2>/dev/null || true
}

echo "══════════════════════════════════════════════════════════"
echo " dispatch-escalate | task=$TASK_NAME | mode=$MODE"
echo " tiers: ${TIERS[*]}"
echo " max_per_tier=$MAX_PER_TIER | similarity_threshold=$SIMILARITY_THRESHOLD"
echo "══════════════════════════════════════════════════════════"
echo ""

if run_oracle; then
  echo "✅ oráculo já passa ANTES do dispatch — nada a fazer."
  echo "{\"task_name\":\"$TASK_NAME\",\"mode\":$MODE,\"result\":\"already-passing\",\"tiers_used\":0}" >> "$LOG_DIR/escalate-ledger.jsonl"
  emit_usage already-passing 0 '{"tiers_used":0}'
  exit 0
fi

# Regras 37/39 (mapa-regras): escalate chamado direto era dívida declarada —
# sem check-spec, sem check-spec-facts, sem check-oracle. Gates ANTES de
# qualquer modelo, DEPOIS do early-exit acima: aqui o oráculo comprovadamente
# falha, então rc=1 do preflight é gate real (spec fraca ou fato inventado),
# nunca o caso "oracle already passes". Subshell: a lib religa errexit por
# dentro e este script roda sem -e.
PF_RC=0
( oracfit_preflight "$SPEC_FILE" "${WORKDIR:-$PWD}" ) || PF_RC=$?
if [ "$PF_RC" -ne 0 ]; then
  echo "❌ preflight reprovou (rc=$PF_RC) — nenhum modelo chamado, nenhum token gasto." >&2
  emit_usage preflight-failed "$PF_RC" "{\"preflight_rc\":$PF_RC}"
  exit 3
fi

TOTAL_START=$(date +%s)
PREV_SIG=""
CONSECUTIVE_SIMILAR=0
PREV_GAP=""
CONSECUTIVE_SAME_GAP=0

for tier_idx in "${!TIERS[@]}"; do
  model="${TIERS[$tier_idx]}"
  label=$(tier_label "$model")
  echo "── Tier $((tier_idx+1)): $label ($model) ──"
  CONSECUTIVE_SAME_GAP=0
  PREV_GAP=""

  for attempt in $(seq 1 "$MAX_PER_TIER"); do
    ATTEMPT_START=$(date +%s)

    dispatch_model "$model" "$SPEC_FILE" "$TASK_NAME" "$attempt" "$label" > /dev/null
    RUNNER_EXIT=$?

    ATTEMPT_END=$(date +%s)
    DURATION=$((ATTEMPT_END - ATTEMPT_START))

    if [ $RUNNER_EXIT -eq 2 ]; then
      echo "  ⚠️  rate-limit (exit 2) — aguardando 30s..."
      sleep 30
      continue
    fi
    if [ $RUNNER_EXIT -eq 4 ]; then
      echo "  ❌ quota exausta (exit 4) — escalando..."
      break
    fi
    if [ $RUNNER_EXIT -eq 124 ]; then
      echo "  ⏱️  teto de ${ESCALATE_TIMEOUT}s atingido (regra 12) — tentativa conta como falha."
    fi

    if run_oracle; then
      # Oráculo verde não basta se o diff tocou tela (classe 5): o gate visual
      # decide o sucesso. Reprovação NÃO encerra o run — vira falha contável
      # com o gap na assinatura, e o loop de feedback abaixo o transporta
      # (oracfit_gauntlet_biggest_gap prefere a linha VISION GATE REJECTED).
      VISUAL_LOG="$LOG_DIR/${TASK_NAME}-${label}-${attempt}.visual.log"
      if gauntlet_visual_gate >"$VISUAL_LOG" 2>&1; then
        TOTAL_END=$(date +%s)
        TOTAL_DUR=$((TOTAL_END - TOTAL_START))
        echo "  ✅ oráculo PASSOU | ${DURATION}s | tentativa $attempt/$MAX_PER_TIER"
        echo ""
        echo "══════════════════════════════════════════════════════════"
        echo " SUCESSO | tier=$label | tentativa=$attempt | total=${TOTAL_DUR}s"
        echo "══════════════════════════════════════════════════════════"
        echo "{\"task_name\":\"$TASK_NAME\",\"mode\":$MODE,\"result\":\"success\",\"tier\":\"$label\",\"model\":\"$model\",\"attempt\":$attempt,\"duration_s\":$DURATION,\"total_s\":$TOTAL_DUR,\"runner_exit\":0,\"oracle_exit\":0}" >> "$LOG_DIR/escalate-ledger.jsonl"
        emit_usage success 0 "{\"tier\":\"$label\",\"model\":\"$model\",\"attempt\":$attempt,\"duration_s\":$DURATION,\"total_s\":$TOTAL_DUR}"
        exit 0
      fi
      CUR_SIG="oracle_exit=0
$(tail -20 "$VISUAL_LOG")"
      echo "  ❌ oráculo passou mas GATE VISUAL reprovou | ${DURATION}s | tentativa $attempt/$MAX_PER_TIER"
      grep -E '^VISION GATE REJECTED:' "$VISUAL_LOG" | head -1 | cut -c1-200 | sed 's/^/     /'
    else
      CUR_SIG=$(capture_error_signature)
      echo "  ❌ oráculo FALHOU | ${DURATION}s | tentativa $attempt/$MAX_PER_TIER"
    fi

    if errors_similar "$PREV_SIG" "$CUR_SIG"; then
      CONSECUTIVE_SIMILAR=$((CONSECUTIVE_SIMILAR + 1))
      echo "  ⚠️  erro similar ao anterior ($CONSECUTIVE_SIMILAR/$SIMILARITY_THRESHOLD consecutivos)"
    else
      CONSECUTIVE_SIMILAR=1
    fi
    PREV_SIG="$CUR_SIG"

    if [ $CONSECUTIVE_SIMILAR -ge $SIMILARITY_THRESHOLD ]; then
      echo "  🚨 modelo TRAVADO — $CONSECUTIVE_SIMILAR erros similares. Escalando."
      break
    fi

    if [ $attempt -lt $MAX_PER_TIER ]; then
      DISPATCH_LOG="$LOG_DIR/${TASK_NAME}-${label}-${attempt}.log"
      LOG_TAIL=$(tail -30 "$DISPATCH_LOG" 2>/dev/null)
      REFINEMENT=""
      CRITIC_JSON=""

      # P3: structured critic from attempt 1 (fresh context, JSON schema).
      echo "  🧠 gauntlet critic (biggest_gap schema) antes da tentativa $((attempt+1))..."
      # Persona trocável (DISPATCH_CRITIC_PROFILE, v3.5) — mesma função do
      # gauntlet do mode; o contrato JSON abaixo fica FORA do perfil.
      REFINE_PROMPT="$(oracfit_gauntlet_critic_persona)

SPEC SUMMARY:
$(head -30 "$ORIGINAL_SPEC")

BAR (if any):
${BARRA:-"(oracle only)"}

ORACLE FAILURE:
$CUR_SIG

BUILDER LOG TAIL:
$LOG_TAIL

Reply ONLY one JSON object (no markdown fences, no praise):
{\"biggest_gap\":\"single biggest remaining gap\",\"must_fix\":[\"fix1\",\"fix2\",\"fix3\",\"fix4\"],\"pick\":\"oracle\"}
pick must be oracle|ours|bar. must_fix max 5 short imperative lines."
      # Mesmo id morto do incidente do call site cru; e crítico sem teto já
      # pendurou stage inteiro (incidente 2026-08-11-critic-sem-teto-…).
      # E5-M3: o critic default morreu com o hint — agora é o free vivo.
      CRITIC_MODEL="${DISPATCH_CRITIC_MODEL:-opencode/nemotron-3-ultra-free}"
      REFINEMENT=$(bash "$REPO_ROOT/bin/with-timeout.sh" "${DISPATCH_CRITIC_TIMEOUT:-300}" \
        opencode run --auto --model "$CRITIC_MODEL" -- "$REFINE_PROMPT" 2>/dev/null | grep -v "^>" | grep -v "^$" | head -40 || true)
      if [ -n "$REFINEMENT" ]; then
        CRITIC_JSON="$(oracfit_gauntlet_parse_critic_json "$REFINEMENT" 2>/dev/null || true)"
        echo "  📋 critic: $(printf '%s' "$CRITIC_JSON" | head -c 160)"
      fi

      echo "  ↻ gauntlet: injetando feedback no próximo attempt..."
      oracle_log="$LOG_DIR/${TASK_NAME}-${label}-${attempt}.oracle.log"
      printf '%s\n' "$CUR_SIG" >"$oracle_log"
      ox="$(printf '%s\n' "$CUR_SIG" | sed -n 's/^oracle_exit=//p' | head -1)"
      ox="${ox:-1}"
      biggest_gap="$(oracfit_gauntlet_append_feedback "$GAUNTLET_ACCUM" "$attempt" "$ox" "$oracle_log")"
      if [ -n "$CRITIC_JSON" ]; then
        cg="$(oracfit_gauntlet_append_critic_structured "$GAUNTLET_ACCUM" "$attempt" "$CRITIC_JSON" || true)"
        [ -n "$cg" ] && biggest_gap="$cg"
      fi

      # Stuck on same gap → escalate tier (gauntlet: gap must change).
      if [ -n "$PREV_GAP" ] && oracfit_gauntlet_gap_stuck "$PREV_GAP" "$biggest_gap"; then
        CONSECUTIVE_SAME_GAP=$((CONSECUTIVE_SAME_GAP + 1))
        echo "  ⚠️  same biggest_gap ($CONSECUTIVE_SAME_GAP/2)"
      else
        CONSECUTIVE_SAME_GAP=1
      fi
      PREV_GAP="$biggest_gap"
      if [ "$CONSECUTIVE_SAME_GAP" -ge 2 ]; then
        echo "  🚨 critic stuck on same gap — escalating tier"
        break
      fi

      gt_file="$LOG_DIR/${TASK_NAME}.ground-truth.md"
      oracfit_gauntlet_extract_ground_truth "$ORIGINAL_SPEC" >"$gt_file" 2>/dev/null || true
      composed="${ORIGINAL_SPEC}.escalate"
      oracfit_gauntlet_compose_spec "$ORIGINAL_SPEC" "$GAUNTLET_ACCUM" "$composed" "$gt_file"
      SPEC_FILE="$composed"
      echo "  gap: $biggest_gap"
    fi
  done

  echo ""
done
TOTAL_END=$(date +%s)
TOTAL_DUR=$((TOTAL_END - TOTAL_START))
echo "══════════════════════════════════════════════════════════"
echo " BLOQUEADO | todos os tiers falharam | total=${TOTAL_DUR}s"
echo " último erro: $PREV_SIG"
echo "══════════════════════════════════════════════════════════"
echo "{\"task_name\":\"$TASK_NAME\",\"mode\":$MODE,\"result\":\"blocked\",\"tiers_used\":${#TIERS[@]},\"total_s\":$TOTAL_DUR,\"last_error\":\"$(echo "$PREV_SIG" | head -1 | tr '"' "'")\"}" >> "$LOG_DIR/escalate-ledger.jsonl"
emit_usage blocked 1 "{\"tiers_used\":${#TIERS[@]},\"total_s\":$TOTAL_DUR,\"last_error\":\"$(echo "$PREV_SIG" | head -1 | tr '"' "'")\"}"
exit 1
