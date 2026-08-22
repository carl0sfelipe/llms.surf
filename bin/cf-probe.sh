#!/usr/bin/env bash
# cf-probe.sh — sonda a codebase Oracfit/Content-Factory de uma vez só.
#
# Objetivo: substituir ~40 tool calls do CLI (grep/cat/find um a um) por 1 leitura.
# Emite:
#   <out>/cf-probe-<ts>.json  — mesmo schema do questionário, com "v" preenchido
#   <out>/cf-probe-<ts>.md    — digest curto: veredito P0 + o que sobrou pra humano
#   <out>/caps-<ts>/          — capturas brutas (só se --keep-raw)
#
# Uso p/ o CLI:  ler o .md primeiro. Só abrir o .json se precisar do detalhe.
#
# Licença: faça o que quiser.

set -uo pipefail   # sem -e: probe que falha é resultado válido (not_found)

# ---------------------------------------------------------------- config ----
ORACFIT="${ORACFIT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
<repo-cliente>="${ORBE_ROOT:-$HOME/<repo-cliente>.live-imports}"
CF="$<repo-cliente>/apps/content-factory"
OUT="."
MAX_BYTES=6000          # teto por captura (--full remove)
KEEP_RAW=0
PING_MODEL=""
TS="$(date +%Y%m%d-%H%M%S)"

usage() {
  cat <<'USAGE'
cf-probe.sh [opções]

  --oracfit PATH     raiz do oracfit        (env ORACFIT_ROOT)
  --<repo-cliente> PATH        raiz do <repo-cliente>.live-imports (env ORBE_ROOT)
  --out DIR          onde escrever          (default: .)
  --ping MODEL_ID    testa o modelo forte com 1 token real (usa $DEEPSEEK_API_KEY)
  --full             sem truncar capturas   (json fica grande)
  --keep-raw         guarda as capturas brutas em caps-<ts>/
  --help

Notas:
  - nenhuma escrita fora de --out. Só leitura da codebase.
  - segredos são redigidos (sk-*, Bearer, *_KEY=, *_TOKEN=, *_SECRET=).
  - --ping é a única coisa que sai pra rede, e só se você pedir.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --oracfit)  ORACFIT="$2"; shift 2 ;;
    --<repo-cliente>)     <repo-cliente>="$2"; CF="$<repo-cliente>/apps/content-factory"; shift 2 ;;
    --out)      OUT="$2"; shift 2 ;;
    --ping)     PING_MODEL="$2"; shift 2 ;;
    --full)     MAX_BYTES=0; shift ;;
    --keep-raw) KEEP_RAW=1; shift ;;
    --help|-h)  usage; exit 0 ;;
    *) echo "opção desconhecida: $1" >&2; usage; exit 2 ;;
  esac
done

mkdir -p "$OUT" || { echo "não consegui criar $OUT" >&2; exit 1; }
CAPS="$(mktemp -d "${TMPDIR:-/tmp}/cfprobe.XXXXXX")"
META="$CAPS/_meta.tsv"
: > "$META"
OUT_JSON="$OUT/cf-probe-$TS.json"
OUT_MD="$OUT/cf-probe-$TS.md"

# --------------------------------------------------------------- helpers ----
redact() {
  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{8,}/[REDACTED]/g' \
    -e 's/(Bearer )[A-Za-z0-9._-]{8,}/\1[REDACTED]/g' \
    -e 's/([A-Za-z_]*(KEY|TOKEN|SECRET|PASSWORD|PASSWD)[A-Za-z_]*[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/g'
}

mtime_of() {  # portável BSD/GNU
  stat -f '%Sm %N' -t '%Y-%m-%dT%H:%M:%S' "$1" 2>/dev/null \
    || stat -c '%y %n' "$1" 2>/dev/null \
    || echo "?? $1"
}

# probe KEY PRIO "pergunta" 'comando'
probe() {
  local key="$1" prio="$2" q="$3" cmd="$4" out status
  out="$(eval "$cmd" 2>/dev/null)"
  out="$(printf '%s' "$out" | redact)"
  if [[ -z "${out//[[:space:]]/}" ]]; then
    status="not_found"
  else
    status="auto"
    if [[ "$MAX_BYTES" -gt 0 && "${#out}" -gt "$MAX_BYTES" ]]; then
      out="$(printf '%s' "$out" | head -c "$MAX_BYTES")
[...TRUNCADO em $MAX_BYTES bytes — rode com --full ou abra o arquivo direto...]"
      status="auto_truncated"
    fi
  fi
  printf '%s' "$out" > "$CAPS/$key.txt"
  printf '%s\t%s\t%s\t%s\n' "$key" "$prio" "$status" "$q" >> "$META"
  printf '.' >&2
}

# fact KEY PRIO "pergunta" "valor literal"  — resultado já derivado
fact() {
  local key="$1" prio="$2" q="$3" v="$4"
  printf '%s' "$v" > "$CAPS/$key.txt"
  printf '%s\t%s\t%s\t%s\n' "$key" "$prio" "auto" "$q" >> "$META"
  printf '.' >&2
}

# human KEY PRIO "pergunta"  — decisão que só você toma
human() {
  local key="$1" prio="$2" q="$3"
  : > "$CAPS/$key.txt"
  printf '%s\t%s\t%s\t%s\n' "$key" "$prio" "needs_human" "$q" >> "$META"
}

has() { [[ -e "$1" ]] && echo yes || echo no; }

echo "cf-probe: oracfit=$ORACFIT <repo-cliente>=$<repo-cliente>" >&2
[[ -d "$ORACFIT" ]] || echo "AVISO: $ORACFIT não existe" >&2
[[ -d "$CF" ]]      || echo "AVISO: $CF não existe" >&2
printf 'sondando' >&2

# ===================================================== 1. repo_state ========
probe repo_state.oracfit_version P2 "VERSION do oracfit" \
  'cat "$ORACFIT/VERSION"'
probe repo_state.oracfit_git_status P1 "working tree sujo do oracfit" \
  'cd "$ORACFIT" && git status --porcelain'
probe repo_state.oracfit_head P2 "HEAD + branch do oracfit" \
  'cd "$ORACFIT" && git log -1 --oneline && git branch --show-current'
probe repo_state.orbe_git_status P1 "working tree sujo em apps/content-factory" \
  'cd "$<repo-cliente>" && git status --porcelain -- apps/content-factory'
probe repo_state.gauntlet_files_uncommitted P1 "arquivos de gauntlet sem commit" \
  'cd "$ORACFIT" && git status --porcelain | grep -i gauntlet'
probe repo_state.tree_oracfit_core P1 "arvore core/ do oracfit" \
  'find "$ORACFIT/core" -maxdepth 2 -type f \( -name "*.py" -o -name "*.yaml" \) | sort'
probe repo_state.tree_cf P1 "arvore do content-factory" \
  'find "$CF" -maxdepth 3 -type f \( -name "*.py" -o -name "*.yaml" \) | grep -v -E "\.venv|node_modules|__pycache__" | sort'
probe repo_state.python_env P2 "pyproject do CF (head)" \
  'head -40 "$CF/pyproject.toml"'
probe repo_state.crewai_version P1 "versoes crewai/litellm/langchain" \
  'cd "$CF" && { uv pip list 2>/dev/null || pip list 2>/dev/null; } | grep -Ei "crewai|litellm|langchain|openai|instructor"'

# ============================================ 2. oracfit_mode_contract ======
MODE_YAML="$ORACFIT/core/modes/content_factory.yaml"
probe oracfit_mode_contract.mode_yaml_full P0 "content_factory.yaml integral" \
  'cat "$MODE_YAML"'
probe oracfit_mode_contract.modes_available P1 "modes existentes" \
  'ls -1 "$ORACFIT/core/modes/"'
probe oracfit_mode_contract.mode_yaml_reference P1 "mode maduro pra comparar (unlock_plan)" \
  'cat "$ORACFIT/core/modes/unlock_plan.yaml"'
probe oracfit_mode_contract.mode_schema_keys P0 "chaves que o loader aceita/valida" \
  'grep -rn "critic_model_ref\|safety_ceiling\|model_ref\|ALLOWED\|_SCHEMA\|required_keys" "$ORACFIT/core" --include="*.py" | head -60'
probe oracfit_mode_contract.mode_loader_file P0 "arquivo que carrega/valida modes" \
  'grep -rln "def .*load_mode\|class .*Mode\b\|def .*validate_mode" "$ORACFIT/core" --include="*.py"'
probe oracfit_mode_contract.mode_validate_output P1 "saida de oracfit mode validate" \
  'cd "$ORACFIT" && command -v oracfit >/dev/null && oracfit mode validate content_factory 2>&1 | head -30'
probe oracfit_mode_contract.description_field_used P1 "description entra no prompt ou e so doc?" \
  'grep -rn "\[.description.\]\|\.description\b" "$ORACFIT/core" --include="*.py" | head -20'
probe oracfit_mode_contract.custom_gates_supported P0 "schema suporta gates custom por stage?" \
  'grep -rn "gate" "$ORACFIT/core" --include="*.py" --include="*.yaml" | head -40'

# ========================================= 3. model_registry_and_routing ====
probe model_registry.registry_candidates P0 "onde mora o registry de modelos" \
  'grep -rln "flash-direct\|model_registry\|MODEL_REGISTRY" "$ORACFIT" --include="*.yaml" --include="*.py" --include="*.toml" | grep -v -E "\.git/|node_modules" | head'
probe model_registry.registry_entries P0 "ids registrados (id -> upstream)" \
  'grep -rn "deepseek" "$ORACFIT" --include="*.yaml" --include="*.toml" | grep -v -E "\.git/|specs/" | head -50'
probe model_registry.strong_model_candidates P0 "ids fortes disponiveis" \
  'grep -rniE "v4-pro|reasoner|-r1|thinking|opus|sonnet" "$ORACFIT" --include="*.yaml" --include="*.py" | grep -v -E "\.git/|specs/" | head -30'
probe model_registry.direct_suffix_meaning P1 "o que -direct bypassa" \
  'grep -rn -- "-direct\|direct" "$ORACFIT/core" --include="*.py" | head -20'
fact model_registry.provider_key_present P0 "DEEPSEEK_API_KEY no ambiente?" \
  "$([[ -n "${DEEPSEEK_API_KEY:-}" ]] && echo "presente (len=${#DEEPSEEK_API_KEY})" || echo "AUSENTE no shell atual — o dispatch pode carregar via env.sh")"

if [[ -n "$PING_MODEL" ]]; then
  if [[ -z "${DEEPSEEK_API_KEY:-}" ]]; then
    fact model_registry.strong_model_verified_live P0 "modelo forte responde de verdade?" \
      "NAO TESTADO: DEEPSEEK_API_KEY ausente"
  else
    PING_CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 30 \
      https://api.deepseek.com/chat/completions \
      -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"$PING_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1}" 2>/dev/null)"
    if [[ "$PING_CODE" == "200" ]]; then
      fact model_registry.strong_model_verified_live P0 "modelo forte responde de verdade?" \
        "true — $PING_MODEL devolveu HTTP 200"
    else
      fact model_registry.strong_model_verified_live P0 "modelo forte responde de verdade?" \
        "false — $PING_MODEL devolveu HTTP $PING_CODE (escolher outro id ANTES de escrever no YAML)"
    fi
  fi
else
  fact model_registry.strong_model_verified_live P0 "modelo forte responde de verdade?" \
    "NAO TESTADO — rode: $0 --ping <MODEL_ID>"
fi

# ================================================== 4. gauntlet_engine ======
probe gauntlet_engine.files P0 "arquivos do gauntlet" \
  'grep -rln "gauntlet" "$ORACFIT" --include="*.py" | grep -v -E "\.git/|test" '
CRITIC_HITS="$(grep -rn 'critic_model_ref' "$ORACFIT" --include='*.py' 2>/dev/null | grep -v -E '\.git/|test')"
CRITIC_USE="$(printf '%s' "$CRITIC_HITS" | grep -vE 'ALLOWED|allowlist|_SCHEMA|schema|required|KEYS' )"
if [[ -n "${CRITIC_USE//[[:space:]]/}" ]]; then
  fact gauntlet_engine.critic_call_site_exists P0 "CRITICO: critic_model_ref e usado em runtime?" \
    "provavel TRUE — ha referencia fora de schema/allowlist:
$CRITIC_USE
>>> confirmar manualmente que a linha INSTANCIA um client, nao so le a chave."
else
  fact gauntlet_engine.critic_call_site_exists P0 "CRITICO: critic_model_ref e usado em runtime?" \
    "provavel FALSE — so aparece em schema/allowlist (ou nao aparece).
Hits brutos:
${CRITIC_HITS:-<nenhum>}
>>> se confirmado, G4 vira IMPLEMENTACAO, nao config."
fi
probe gauntlet_engine.critic_raw_hits P0 "todos os hits de critic_model_ref" \
  'grep -rn "critic_model_ref" "$ORACFIT" | grep -v "\.git/"'
probe gauntlet_engine.feedback_injection_mechanism P0 "CRITICO: como o feedback chega na iteracao N+1" \
  'grep -rniE "feedback|inject|retry|previous_attempt|prior_result" "$ORACFIT/core" --include="*.py" | head -40'
probe gauntlet_engine.loop_termination P0 "condicoes de parada do loop" \
  'grep -rn -B2 -A8 "safety_ceiling\|while .*attempt\|for attempt\|max_attempts" "$ORACFIT" --include="*.py" | grep -v "\.git/" | head -60'
probe gauntlet_engine.safety_ceiling_semantics P0 "ceiling conta o que?" \
  'grep -rn "safety_ceiling" "$ORACFIT" | grep -v "\.git/"'
probe gauntlet_engine.gauntlet_enabled_for_cf P0 "gauntlet esta ligado no mode CF?" \
  'grep -n -A6 "gauntlet" "$MODE_YAML"'
probe gauntlet_engine.ground_truth_inject P1 "o que o P4 ground-truth inject faz" \
  'grep -rn -A10 "ground_truth\|ground-truth" "$ORACFIT" --include="*.py" | grep -v "\.git/" | head -40'
probe gauntlet_engine.tests P2 "testes de gauntlet existentes" \
  'grep -rn "def test_" "$ORACFIT"/tests/*gauntlet* 2>/dev/null'

# =================================================== 5. oracle_engine =======
SPEC_BEELINK="$ORACFIT/specs/niche-<host-local>-ser-6800u-vale-a-pena.md"
probe oracle_engine.parser P0 "como o bloco ## Oraculo e executado" \
  'grep -rniE "oracle|oraculo" "$ORACFIT/core" --include="*.py" | head -40'
probe oracle_engine.parser_body P0 "corpo da funcao de oraculo" \
  'grep -rniE -A25 "def .*oracle|def .*oraculo" "$ORACFIT" --include="*.py" | grep -v "\.git/" | head -60'
probe oracle_engine.spec_beelink_blocks P0 "blocos Dados verificados / Oraculo / Barra" \
  'sed -n "/## Dados verificados/,\$p" "$SPEC_BEELINK"'
probe oracle_engine.spec_template P1 "template de spec de nicho" \
  'cat "$ORACFIT/specs/_template-content-factory-niche.md"'
probe oracle_engine.supports_shell P0 "oraculo roda shell arbitrario ou so check declarativo?" \
  'grep -rnE "subprocess|os\.system|shell=True|check_output" "$ORACFIT/core" --include="*.py" | head -20'
probe oracle_engine.checks_freshness P0 "oraculo checa mtime/run_id do artefato?" \
  'grep -rnE "mtime|getmtime|st_mtime|run_id" "$ORACFIT/core" --include="*.py" | head -30'

# ============================================ 6. content_factory_internals ==
probe cf_internals.agents_yaml P0 "agents.yaml integral" \
  'cat "$CF/config/agents.yaml"'
probe cf_internals.tasks_yaml P1 "tasks.yaml integral" \
  'cat "$CF/config/tasks.yaml"'
probe cf_internals.llm_factory P0 "lib/llm_factory.py" \
  'cat "$CF/lib/llm_factory.py"'
probe cf_internals.create_agent_llm P0 "_create_agent_llm completo" \
  'grep -n -A45 "_create_agent_llm" "$CF/src/bmad_crew.py"'
MC_HITS="$(grep -rn 'model_critical' "$CF" --include='*.py' 2>/dev/null | grep -v -E '\.venv|__pycache__')"
MC_YAML="$(grep -rn 'model_critical\|critical_decision' "$CF/config" 2>/dev/null)"
if [[ -n "${MC_HITS//[[:space:]]/}" ]]; then
  fact cf_internals.model_critical_respected P0 "CRITICO: happy path le model_critical?" \
    "referenciado em .py — inspecionar se e happy path ou fallback:
$MC_HITS
--- em config/ ---
${MC_YAML:-<nada>}
>>> heuristica: se a unica ocorrencia esta perto de 'except'/'fallback'/'emergency', a resposta e FALSE."
else
  fact cf_internals.model_critical_respected P0 "CRITICO: happy path le model_critical?" \
    "FALSE provavel — 'model_critical' nao aparece em nenhum .py do CF.
Em config/: ${MC_YAML:-<nada>}
>>> o fit judge!=act NAO existe hoje; G1 vira implementacao."
fi
probe cf_internals.model_critical_context P0 "contexto das linhas de model_critical" \
  'grep -rn -B6 -A10 "model_critical" "$CF" --include="*.py" | grep -v -E "\.venv|__pycache__"'
probe cf_internals.critical_decision_agents P0 "quem tem critical_decision: true" \
  'grep -n -B8 "critical_decision" "$CF/config/agents.yaml"'
probe cf_internals.env_override_exists P1 "envs que sobrescrevem modelo (base do kill switch)" \
  'grep -rn "os\.environ\|getenv" "$CF/lib" "$CF/src" 2>/dev/null | head -30'
probe cf_internals.structured_output P1 "output estruturado nas tasks?" \
  'grep -rn "output_pydantic\|output_json\|response_format\|output_file" "$CF/config" "$CF/src" 2>/dev/null | head -30'
probe cf_internals.main_py_entry P0 "args/env aceitos por main.py" \
  'grep -n -A35 "argparse\|def main" "$CF/main.py" | head -60'
probe cf_internals.crew_process P1 "sequential vs hierarchical + manager_llm" \
  'grep -n "Process\.\|manager_llm\|hierarchical" "$CF/src/bmad_crew.py"'

# ============================================== 7. dispatch_and_runtime =====
probe dispatch.env_sh_vars P1 "vars exportadas pelo env.sh (nomes)" \
  'grep -oE "export [A-Z_]+" "$ORACFIT/adapters/opencode/env.sh" | sort -u'
probe dispatch.run_help P0 "assinatura de oracfit run" \
  'command -v oracfit >/dev/null && oracfit run --help 2>&1 | head -40'
probe dispatch.panel_help P1 "assinatura de oracfit panel" \
  'command -v oracfit >/dev/null && oracfit panel --help 2>&1 | head -25'
probe dispatch.opencode_runner P0 "onde o runner monta o comando do CF" \
  'grep -rn "main\.py\|uv run" "$ORACFIT/adapters" "$ORACFIT/core" 2>/dev/null | grep -v "\.git/"'
probe dispatch.timeout_wrapper P1 "with-timeout no caminho de dispatch?" \
  'grep -rn "timeout" "$ORACFIT/adapters" 2>/dev/null | head -15'
probe dispatch.run_id_generation P0 "como run_id e gerado/exposto" \
  'grep -rn "run_id" "$ORACFIT/core" --include="*.py" | head -25'
probe dispatch.beelink_pid P0 "run <host-local> ainda viva?" \
  'ps -eo pid,lstart,command | grep -iE "oracfit|content-factory|bmad_crew|main\.py" | grep -v grep | grep -v cf-probe | awk -v me=$$ -v pai=$PPID "\$1 != me && \$1 != pai"'

EVENTS="$(find "$<repo-cliente>" "$ORACFIT" -name 'events.jsonl' -not -path '*/node_modules/*' 2>/dev/null | head -3)"
fact dispatch.events_jsonl_path P0 "path do events.jsonl" "${EVENTS:-<nao encontrado>}"
if [[ -n "$EVENTS" ]]; then
  E1="$(printf '%s' "$EVENTS" | head -1)"
  probe dispatch.events_sample P0 "2 eventos de exemplo" 'tail -2 "$E1"'
  probe dispatch.events_has_model_field P0 "eventos registram o modelo?" \
    'grep -o "\"model[^,]*" "$E1" | sort -u | head -20'
else
  fact dispatch.events_sample P0 "2 eventos de exemplo" "<events.jsonl nao encontrado>"
  fact dispatch.events_has_model_field P0 "eventos registram o modelo?" "<indeterminado>"
fi

# ========================================= 8. artifacts_and_idempotency =====
ART_FILES="$(find "$<repo-cliente>" -name 'T4-content-validation*' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -20)"
fact artifacts.t4_files P0 "arquivos T4 no disco" "${ART_FILES:-<nenhum>}"
if [[ -n "$ART_FILES" ]]; then
  ART_DIR="$(dirname "$(printf '%s' "$ART_FILES" | head -1)")"
  fact artifacts.dir P0 "diretorio de artefatos" "$ART_DIR"
  probe artifacts.dir_listing P0 "listagem com mtime" 'ls -la "$ART_DIR"'
  probe artifacts.t4_content P0 "conteudo do T4 (schema do verdict)" \
    'head -40 "$(printf "%s" "$ART_FILES" | head -1)"'
  # --- detecção de artefato velho APPROVED (risco de falso verde) ---
  STALE="$(grep -rl 'APPROVED' "$ART_DIR" 2>/dev/null)"
  if [[ -n "${STALE//[[:space:]]/}" ]]; then
    STALE_DETAIL=""
    while IFS= read -r f; do
      [[ -n "$f" ]] && STALE_DETAIL="$STALE_DETAIL
$(mtime_of "$f")"
    done <<< "$STALE"
    fact artifacts.stale_approved_present P0 "ha APPROVED de run anterior no disco?" \
      "SIM — RISCO DE FALSO VERDE. O oraculo 'existe arquivo com APPROVED' passa antes do pipeline rodar:$STALE_DETAIL"
  else
    fact artifacts.stale_approved_present P0 "ha APPROVED de run anterior no disco?" "nao"
  fi
  # --- run-scoped? ---
  if printf '%s' "$ART_FILES" | grep -qE '[0-9]{8}|[0-9]{6}|run[-_]|/runs?/'; then
    SCOPED="provavel TRUE — path contem timestamp/run id"
  else
    SCOPED="provavel FALSE — todo run sobrescreve o mesmo path. Confirmar em tasks.yaml output_file."
  fi
  fact artifacts.path_is_run_scoped P0 "artefato e run-scoped?" "$SCOPED"
else
  fact artifacts.dir P0 "diretorio de artefatos" "<nao encontrado>"
  fact artifacts.stale_approved_present P0 "ha APPROVED de run anterior?" "<indeterminado>"
  fact artifacts.path_is_run_scoped P0 "artefato e run-scoped?" "<indeterminado>"
fi
probe artifacts.output_file_config P0 "output_file declarado nas tasks" \
  'grep -n "output_file" "$CF/config/tasks.yaml"'
probe artifacts.verdict_vocabulary P1 "verdicts possiveis" \
  'grep -rn "APPROVED\|REJECT" "$CF/config" | head -20'
probe artifacts.cleanup_mechanism P1 "existe limpeza entre runs?" \
  'grep -rn "rmtree\|unlink\|shutil\|clean" "$ORACFIT/core" --include="*.py" | head -15'

# ======================================= 9. observability_and_evidence ======
LOGS="$(find "$<repo-cliente>" "$ORACFIT" -name '*.log' -mtime -3 -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -10)"
fact observability.log_paths P0 "logs recentes (3d)" "${LOGS:-<nenhum>}"
if [[ -n "$LOGS" ]]; then
  L1="$(printf '%s' "$LOGS" | head -1)"
  probe observability.model_lines_sample P0 "linhas de log que citam modelo" \
    'grep -iE "model[=\": ]" "$L1" | head -10'
  probe observability.distinct_models_in_log P0 "modelos distintos ja usados (evidencia de fit)" \
    'grep -ohiE "(deepseek|gpt|claude)[a-zA-Z0-9./_-]*" $LOGS 2>/dev/null | sort -u | head -20'
  probe observability.cost_logged P1 "tokens/custo aparecem no log?" \
    'grep -inE "usage|prompt_tokens|completion_tokens|cost" "$L1" | head -10'
else
  fact observability.model_lines_sample P0 "linhas de log com modelo" "<sem logs recentes>"
  fact observability.distinct_models_in_log P0 "modelos distintos ja usados" "<sem logs recentes>"
fi
probe observability.litellm_verbose P1 "como ligar verbose do litellm" \
  'grep -rn "set_verbose\|LITELLM_LOG\|litellm.verbose" "$CF" 2>/dev/null | grep -v -E "\.venv|__pycache__" | head'

# =============================================== 10. decisões humanas =======
human decisions.feedback_channel_choice        P0 "canal de feedback: (a) feedback.md (b) append na spec (c) param no dispatch"
human decisions.freshness_strategy_choice      P0 "anti-artefato-velho: (a) dir por run_id (b) mtime>run_start (c) run_id no yaml (d) clean pre-run"
human decisions.strong_model_choice            P0 "qual id vira o critic/judge forte (depois do --ping)"
human decisions.implement_if_no_call_site      P0 "se critic_model_ref nao tiver call site: implementar agora ou registrar divida?"
human decisions.soft_judges_stay_flash         P1 "T2/T3 ficam flash mesmo?"
human decisions.max_iterations_desired         P1 "teto de iteracoes do gauntlet"
human decisions.acceptable_cost_per_run        P1 "gasto aceitavel por run <host-local>"
human decisions.wall_clock_vs_cost             P1 "'sem teto' vale so pra relogio ou tambem pra custo?"
human decisions.tag_scope                      P1 "paths exatos que entram no commit v1.9.0"

printf ' ok\n' >&2

# =================================================== montagem do JSON =======
CFPROBE_TS="$TS" CFPROBE_ORACFIT="$ORACFIT" CFPROBE_ORBE="$<repo-cliente>" \
CFPROBE_HOST="$(uname -srm 2>/dev/null)" CFPROBE_PING="${PING_MODEL:-<none>}" \
python3 - "$META" "$CAPS" "$OUT_JSON" "$OUT_MD" <<'PY'
import json, os, sys, collections

meta_path, caps_dir, out_json, out_md = sys.argv[1:5]

QUESTION_ORDER = []
nodes = {}
with open(meta_path, encoding='utf-8', errors='replace') as fh:
    for line in fh:
        line = line.rstrip('\n')
        if not line:
            continue
        parts = line.split('\t')
        if len(parts) < 4:
            continue
        key, prio, status, question = parts[0], parts[1], parts[2], '\t'.join(parts[3:])
        cap = os.path.join(caps_dir, key + '.txt')
        try:
            with open(cap, encoding='utf-8', errors='replace') as cf:
                value = cf.read()
        except OSError:
            value = ''
        value = value.strip() or None
        nodes[key] = {'q': question, 'v': value, 'p': prio, 'status': status}
        QUESTION_ORDER.append(key)

doc = collections.OrderedDict()
doc['_meta'] = {
    'generated_at': os.environ.get('CFPROBE_TS'),
    'oracfit_root': os.environ.get('CFPROBE_ORACFIT'),
    'orbe_root': os.environ.get('CFPROBE_ORBE'),
    'host': os.environ.get('CFPROBE_HOST'),
    'ping_model': os.environ.get('CFPROBE_PING'),
    'status_legend': {
        'auto': 'preenchido pelo script',
        'auto_truncated': 'preenchido mas cortado — rode --full',
        'not_found': 'comando nao retornou nada (arquivo ausente ou padrao inexistente)',
        'needs_human': 'decisao sua, script nao resolve',
    },
    'para_a_ia_cli': 'Leia o .md irmao primeiro. So abra este .json se precisar do dump completo de um campo especifico.',
}

for key in QUESTION_ORDER:
    section, field = key.split('.', 1)
    doc.setdefault(section, collections.OrderedDict())[field] = nodes[key]

with open(out_json, 'w', encoding='utf-8') as fh:
    json.dump(doc, fh, ensure_ascii=False, indent=2)

# ---------------------------------------------------------------- digest ----
def get(k, default='<sem dado>'):
    n = nodes.get(k)
    return (n['v'] if n and n['v'] else default)

P0_VERDICT = [
    ('G0.1 critic_model_ref tem call site',   'gauntlet_engine.critic_call_site_exists'),
    ('G0.2 model_critical e respeitado',      'cf_internals.model_critical_respected'),
    ('G0.3 modelo forte responde',            'model_registry.strong_model_verified_live'),
    ('G2   artefato APPROVED velho no disco', 'artifacts.stale_approved_present'),
    ('G2   artefato e run-scoped',            'artifacts.path_is_run_scoped'),
    ('G3   mecanismo de feedback',            'gauntlet_engine.feedback_injection_mechanism'),
    ('G5   run <host-local> ainda viva',           'dispatch.beelink_pid'),
]

lines = []
lines.append('# cf-probe — digest %s\n' % os.environ.get('CFPROBE_TS'))
lines.append('JSON completo: `%s`\n' % os.path.basename(out_json))
lines.append('## Veredito P0 (ler isto antes de qualquer coisa)\n')
for label, key in P0_VERDICT:
    v = get(key)
    first = v.strip().splitlines()[0][:220] if v and v != '<sem dado>' else v
    lines.append('- **%s** → %s' % (label, first))
lines.append('')

missing = [k for k in QUESTION_ORDER if nodes[k]['status'] == 'not_found' and nodes[k]['p'] == 'P0']
if missing:
    lines.append('## P0 sem resposta (%d) — ajustar path/padrao e re-rodar\n' % len(missing))
    for k in missing:
        lines.append('- `%s` — %s' % (k, nodes[k]['q']))
    lines.append('')

human_keys = [k for k in QUESTION_ORDER if nodes[k]['status'] == 'needs_human']
if human_keys:
    lines.append('## Decisoes suas (%d) — script nao resolve\n' % len(human_keys))
    for k in human_keys:
        lines.append('- [ ] **%s** (%s) — %s' % (k.split('.',1)[1], nodes[k]['p'], nodes[k]['q']))
    lines.append('')

trunc = [k for k in QUESTION_ORDER if nodes[k]['status'] == 'auto_truncated']
if trunc:
    lines.append('## Truncados (%d) — `--full` se precisar do resto\n' % len(trunc))
    lines.append(', '.join('`%s`' % k for k in trunc))
    lines.append('')

counts = collections.Counter(nodes[k]['status'] for k in QUESTION_ORDER)
lines.append('## Contagem\n')
lines.append(' | '.join('%s: %d' % (s, c) for s, c in sorted(counts.items())))
lines.append('')
lines.append('## Chaves por secao\n')
by_sec = collections.OrderedDict()
for k in QUESTION_ORDER:
    by_sec.setdefault(k.split('.',1)[0], []).append(k.split('.',1)[1])
for sec, fields in by_sec.items():
    lines.append('- **%s**: %s' % (sec, ', '.join(fields)))

with open(out_md, 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(lines) + '\n')

print('campos: %d | P0 sem resposta: %d | decisoes humanas: %d' %
      (len(QUESTION_ORDER), len(missing), len(human_keys)))
PY

RC=$?

if [[ "$KEEP_RAW" -eq 1 ]]; then
  cp -R "$CAPS" "$OUT/caps-$TS"
  echo "capturas brutas: $OUT/caps-$TS" >&2
fi
rm -rf "$CAPS"

if [[ $RC -ne 0 ]]; then
  echo "falha ao montar o JSON (python3 disponivel?)" >&2
  exit 1
fi

cat >&2 <<EOF

  digest: $OUT_MD
  json:   $OUT_JSON

  próximo passo p/ o CLI (1 tool call):
    cat "$OUT_MD"
EOF
