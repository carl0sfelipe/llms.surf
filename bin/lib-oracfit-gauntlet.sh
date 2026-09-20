#!/bin/bash
# lib-oracfit-gauntlet.sh — Gauntlet feedback for Oracfit dispatch loops.
# Source me after lib-oracfit-root.sh / events / preflight.
#
# Pattern (https://github.com/robonuggets/gauntlet-loop):
#   oracle fail → name biggest gap → inject into next builder spec → loop until win
# Exit is oracle_exit=0 (or safety_ceiling / human stop). Fixed N is not the win condition.
#
# P0: deterministic critic (oracle stdout/stderr).
# P3: structured LLM critic (biggest_gap + must_fix JSON) when available.

# Parse gauntlet.* from mode YAML via mode-loader dump.
# No `gauntlet:` block → inject feedback ON, do NOT raise max_attempts.
# With `gauntlet:` block → until_approved + safety_ceiling apply (exit = win).
oracfit_gauntlet_cfg() {
  local mode_yaml="${1:?}"
  local key="${2:?}" # enabled|until_approved|safety_ceiling|inject_feedback
  python3 - "$mode_yaml" "$key" <<'PY'
import sys
from pathlib import Path
path, key = sys.argv[1], sys.argv[2]
text = Path(path).read_text(encoding="utf-8")
try:
    import yaml
    data = yaml.safe_load(text) or {}
except Exception:
    data = {}
g = data.get("gauntlet")
has_block = isinstance(g, dict)
g = g or {}
# P0 default: always learn from oracle fail; only raise ceiling when configured.
defaults = {
    "enabled": True,
    "inject_feedback": True,
    "until_approved": True if has_block else False,
    "safety_ceiling": 10 if has_block else 3,
}
val = g[key] if key in g else defaults[key]
if isinstance(val, bool):
    print("true" if val else "false")
else:
    print(val)
PY
}

oracfit_gauntlet_enabled() {
  local mode_yaml="${1:?}"
  [ "$(oracfit_gauntlet_cfg "$mode_yaml" enabled)" = "true" ]
}

oracfit_gauntlet_inject_enabled() {
  local mode_yaml="${1:?}"
  oracfit_gauntlet_enabled "$mode_yaml" || return 1
  [ "$(oracfit_gauntlet_cfg "$mode_yaml" inject_feedback)" = "true" ]
}

oracfit_gauntlet_resolve_max_attempts() {
  # Prefer safety_ceiling when until_approved; else keep caller max_attempts.
  local mode_yaml="${1:?}"
  local current_max="${2:?}"
  local until ceiling
  until="$(oracfit_gauntlet_cfg "$mode_yaml" until_approved)"
  ceiling="$(oracfit_gauntlet_cfg "$mode_yaml" safety_ceiling)"
  if [ "$until" = "true" ] && [ -n "$ceiling" ]; then
    if [ "$ceiling" -gt "$current_max" ] 2>/dev/null; then
      echo "$ceiling"
      return 0
    fi
  fi
  echo "$current_max"
}

# Freshness gate anti-veneno (fit 2026-08-09).
# O oráculo do content_factory confere `decision: APPROVED` no T4. Um T4 velho de run
# anterior (ou fixture) deixa o grep passar — run novo "aprovado" sem produzir nada.
# Exige AS DUAS condições, em mtime E identidade:
#   1. mtime(T4) >= $ORACFIT_RUN_STARTED_AT  (escrito DURANTE este run)
#   2. campo `run_id:` no T4 == $ORACFIT_RUN_ID  (é o T4 DESTE run)
# Sem ORACFIT_RUN_ID no env → bypass (content-factory standalone fora do oracfit).
# Args: t4_path. Usa env ORACFIT_RUN_ID e ORACFIT_RUN_STARTED_AT.
# Return 0 = fresco (pode confiar); !=0 = rejeitado (stale/poison/outro-run).
oracfit_gauntlet_freshness_gate() {
  local t4_path="${1:?}"
  # Bypass em modo standalone (CF rodando fora do oracfit, sem env de run).
  [ -z "${ORACFIT_RUN_ID:-}" ] && return 0
  ORACFIT_RUN_ID="${ORACFIT_RUN_ID}" \
  ORACFIT_RUN_STARTED_AT="${ORACFIT_RUN_STARTED_AT:-}" \
  T4_PATH="$t4_path" python3 - <<'PY'
import os, re, sys
from pathlib import Path
t4 = Path(os.environ["T4_PATH"])
run_id = os.environ["ORACFIT_RUN_ID"].strip()
started = os.environ.get("ORACFIT_RUN_STARTED_AT", "").strip()
if not t4.is_file():
    sys.exit(1)
# (1) mtime >= run_started_at — arquivo foi escrito durante ESTE run.
if started:
    try:
        started_f = float(started)
        mtime = t4.stat().st_mtime
        if mtime < started_f:
            sys.exit(1)
    except (ValueError, OSError):
        sys.exit(1)
# (2) run_id no T4 == ORACFIT_RUN_ID — é o T4 DESTE run, não de outro.
text = t4.read_text(encoding="utf-8", errors="replace")
m = re.search(r"(?im)^\s*run_id\s*:\s*['\"]?([A-Za-z0-9_.\-]+)", text)
if not m:
    sys.exit(1)
if m.group(1).strip() != run_id:
    sys.exit(1)
sys.exit(0)
PY
}

# Visual artifact freshness gate (ADR-0004).
# Args: target paths, relative to ORACFIT_WORKDIR unless absolute. Environment:
# ORACFIT_STAGE_STARTED_AT is the timestamp captured immediately before the
# current stage attempt. Every target must exist, be non-empty, and have mtime
# >= that attempt start. Paths are expanded by Python so spaces remain intact.
oracfit_visual_freshness_gate() {
  local started="${ORACFIT_STAGE_STARTED_AT:-}"
  if [ -z "$started" ]; then
    echo "visual freshness: ORACFIT_STAGE_STARTED_AT is unset" >&2
    return 1
  fi
  ORACFIT_VISUAL_WORKDIR="${ORACFIT_WORKDIR:-$PWD}" \
    ORACFIT_STAGE_STARTED_AT="$started" \
    python3 - "$@" <<'PY'
import os
import sys
from pathlib import Path

try:
    started = float(os.environ["ORACFIT_STAGE_STARTED_AT"])
except (KeyError, ValueError):
    print("visual freshness: invalid ORACFIT_STAGE_STARTED_AT", file=sys.stderr)
    sys.exit(1)

workdir = Path(os.environ["ORACFIT_VISUAL_WORKDIR"])
failed = False
for raw in sys.argv[1:]:
    expanded = os.path.expandvars(os.path.expanduser(raw))
    if "$" in expanded:
        print(f"visual freshness: unresolved target variable: {raw}", file=sys.stderr)
        failed = True
        continue
    path = Path(expanded)
    if not path.is_absolute():
        path = workdir / path
    try:
        stat = path.stat()
    except OSError:
        print(f"visual freshness: missing target: {path}", file=sys.stderr)
        failed = True
        continue
    if not path.is_file():
        print(f"visual freshness: target is not a file: {path}", file=sys.stderr)
        failed = True
        continue
    if stat.st_size <= 0:
        print(f"visual freshness: target is empty: {path}", file=sys.stderr)
        failed = True
        continue
    if stat.st_mtime < started:
        print(
            f"visual freshness: target is stale: {path} "
            f"(mtime={stat.st_mtime:.6f} < attempt_start={started:.6f})",
            file=sys.stderr,
        )
        failed = True

sys.exit(1 if failed else 0)
PY
}

# Remove prior visual evidence before an attempt. This is deliberately separate
# from the gate: an absent target after a failed Playwright command must remain
# absent and fail closed, rather than allowing yesterday's PNG to survive.
oracfit_visual_freshness_clean() {
  [ "$#" -gt 0 ] || return 0
  ORACFIT_VISUAL_WORKDIR="${ORACFIT_WORKDIR:-$PWD}" \
    python3 - "$@" <<'PY'
import os
import sys
from pathlib import Path

workdir = Path(os.environ["ORACFIT_VISUAL_WORKDIR"])
failed = False
for raw in sys.argv[1:]:
    expanded = os.path.expandvars(os.path.expanduser(raw))
    if "$" in expanded:
        print(f"visual freshness: unresolved target variable: {raw}", file=sys.stderr)
        failed = True
        continue
    path = Path(expanded)
    if not path.is_absolute():
        path = workdir / path
    if not path.exists() and not path.is_symlink():
        continue
    if path.is_dir():
        print(f"visual freshness: refusing to remove directory target: {path}", file=sys.stderr)
        failed = True
        continue
    try:
        path.unlink()
    except OSError as exc:
        print(f"visual freshness: cannot remove stale target {path}: {exc}", file=sys.stderr)
        failed = True

sys.exit(1 if failed else 0)
PY
}

# Extract optional `freshness_target:` line from spec (anti-veneno, fit 2026-08-09).
# Caminho relativo do T4 que o oráculo confere; o gate de freshness o rejeita se
# não for deste run. Vazio se a spec não declarar freshness_target.
oracfit_gauntlet_freshness_target() {
  local spec="${1:?}"
  grep -iE '^[-*][[:space:]]*freshness_target:' "$spec" 2>/dev/null \
    | head -1 \
    | sed -E 's/^[-*][[:space:]]*freshness_target:[[:space:]]*//I' \
    | tr -d '"' \
    | sed -E 's/[[:space:]]+$//'
}

# Run ## Oráculo comando; capture combined stdout+stderr to logfile. Return oracle rc.
oracfit_gauntlet_run_oracle_capture() {
  local spec="${1:?}"
  local workdir="${2:?}"
  local logfile="${3:?}"
  local cmd
  cmd="$(grep -iE '^[-*][[:space:]]*comando:' "$spec" | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I')"
  if [ -z "$cmd" ]; then
    echo "ERROR: no oracle - comando: line in $spec" >&2
    printf 'ERROR: no oracle comando\n' >"$logfile"
    return 3
  fi
  set +e
  ( cd "$workdir" && eval "$cmd" ) >"$logfile" 2>&1
  local rc=$?
  # Não reabilite set -e antes do return: return non-zero com errexit mata
  # o script inteiro (fail-path do stage loop), não só devolve rc ao caller.
  return "$rc"
}

# Heuristic biggest gap from oracle log (no LLM). One line.
oracfit_gauntlet_biggest_gap() {
  local logfile="${1:?}"
  local oracle_exit="${2:-1}"
  if [ ! -s "$logfile" ]; then
    echo "oracle exited ${oracle_exit} with empty output — re-check ## Oráculo comando and expected artifacts"
    return 0
  fi
  # 1º: linha final do vision gate — é a mais articulada (nome da fatia + gap
  # do juiz). Run DC8B7FBF: sem essa preferência a heurística genérica casava
  # "broken/failed" numa linha de progresso flaky ("slice ...: APPROVED — (flaky
  # reject ...)") e o feedback injetado era lixo.
  local gap
  gap="$(grep -E '^VISION GATE REJECTED:' "$logfile" | head -1 | cut -c1-240 || true)"
  # 1.5: Gradle — a primeira linha do stderr é boilerplate ("FAILURE: Build
  # failed with an exception.") e o conteúdo articulado vem DEPOIS: diagnóstico
  # do compilador Kotlin ("e: file: (l, c): ..."), causa raiz ("> Caused by:")
  # ou a task que falhou. Incidente
  # 2026-09-20-biggest-gap-le-a-primeira-linha-inutil-d: o feedback de gap era
  # o cabeçalho inútil em TODAS as tentativas do run — modelo real receberia
  # feedback vazio.
  if [ -z "$gap" ]; then
    gap="$(grep -E '^e: |^Execution failed for task|^> Caused by:' "$logfile" \
          | head -1 | sed 's/^[[:space:]]*//' | cut -c1-240 || true)"
  fi
  # 2º: linhas que parecem assertion/grep failure, SKIPPING boilerplate do
  # dispatch-stages ("STAGE ORACLE FAILED", "STAGE COMMAND FAILED", labels) e
  # linhas de progresso por fatia ("slice ..." — podem conter vocabulário de
  # falha dentro de um APPROVED flaky).
  # Incidente 2026-08-11-vision-gate-gap-nao-injetado: sem esse filtro a
  # heurística pega o boilerplate em vez do gap articulado pelo juiz LLM.
  # '^VISION GATE REJECTED\b' TAMBÉM fica no filtro de exclusão do fallback:
  # a forma canônica (com ':') já foi capturada pela preferência acima; a forma
  # label ("VISION GATE REJECTED — biggest_gap:") é boilerplate e o gap real
  # vem na linha SEGUINTE (regressão pega por tests/test-gauntlet-feedback.sh).
  # '^[[:space:]]*\{"' exclui linhas de stream JSON cru do opencode --format
  # json (ex: {"type":"tool_use",...} com "status":"error" no meio) — quando o
  # STAGE COMMAND falha, o oracle_log carrega o tail do stream e a heurística
  # injetava um blob JSON inútil como gap (run AA26BEB2, 2026-08-12).
  # Boilerplate do Gradle (mesmo incidente 2026-09-20 do 1.5 acima): o
  # cabeçalho "FAILURE: ..." casa FAIL e "BUILD FAILED" também — ambos são
  # moldura, não diagnóstico.
  if [ -z "$gap" ]; then
    gap="$(grep -iE 'FAIL|ERROR|not found|No such|ASSERT|expected|missing|REJECTED|ORACLE' "$logfile" \
          | grep -ivE '^STAGE (ORACLE|COMMAND) FAILED|^VISION GATE REJECTED\b|^slice |^FRESHNESS GATE|^The stage oracle and ordinary spec oracle were skipped|^[[:space:]]*\{"|^FAILURE: Build failed|^BUILD FAILED|^\* (What went wrong|Try|Get more help)|^> Run with' \
          | head -1 | sed 's/^[[:space:]]*//' | cut -c1-240 || true)"
  fi
  if [ -z "$gap" ]; then
    gap="$(grep -v '^[[:space:]]*$' "$logfile" \
          | grep -ivE '^STAGE (ORACLE|COMMAND) FAILED|^VISION GATE REJECTED\b|^slice |^FRESHNESS GATE|^The stage oracle and ordinary spec oracle were skipped|^[[:space:]]*\{"|^FAILURE: Build failed|^BUILD FAILED|^\* (What went wrong|Try|Get more help)|^> Run with|^> Compilation error' \
          | head -1 | sed 's/^[[:space:]]*//' | cut -c1-240 || true)"
  fi
  if [ -z "$gap" ]; then
    gap="oracle exited ${oracle_exit} — inspect captured log"
  fi
  printf '%s\n' "$gap"
}

# Extract optional ## Barra block (named quality bar for gauntlet). Empty if absent.
oracfit_gauntlet_extract_barra() {
  local spec="${1:?}"
  python3 - "$spec" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(r"(?im)^##\s*Barra\s*\n(.*?)(?=^##\s|\Z)", text, re.S)
if not m:
    sys.exit(0)
body = m.group(1).strip()
print(body[:2000])
PY
}

# Extract ## Dados verificados (or ## Dados) for content_factory ground-truth inject (P4).
oracfit_gauntlet_extract_ground_truth() {
  local spec="${1:?}"
  python3 - "$spec" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
m = re.search(
    r"(?im)^##\s*(?:Dados(?:\s+verificados)?|Verified\s+data)[^\n]*\n(.*?)(?=^##\s|\Z)",
    text,
    re.S,
)
if not m:
    sys.exit(0)
body = m.group(1).strip()
print(body[:8000])
PY
}

# Parse P3 critic JSON from free-form LLM output.
# Prints JSON line: {"biggest_gap":"...","must_fix":["..."],"pick":"oracle|ours|bar"}
oracfit_gauntlet_parse_critic_json() {
  local raw="${1:?}"
  local lib_dir
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ORACFIT_CRITIC_RAW="$raw" ORACFIT_CHECK_VERDICT="$lib_dir/check-verdict.py" python3 - <<'PY'
import json, os, re
text = os.environ.get("ORACFIT_CRITIC_RAW") or ""
obj = None
fence = re.search(r"```(?:json)?\s*\n(.*?)```", text, re.S | re.I)
candidate = fence.group(1).strip() if fence else text
try:
    loaded = json.loads(candidate)
    if isinstance(loaded, dict):
        obj = loaded
except Exception:
    m = re.search(r"\{[^{}]*biggest_gap[^{}]*\}", text, re.S | re.I)
    if m:
        try:
            obj = json.loads(m.group(0))
        except Exception:
            obj = None
if not isinstance(obj, dict):
    gap = ""
    for line in text.splitlines():
        if re.search(r"biggest\s+remaining\s+gap|biggest_gap", line, re.I):
            gap = re.sub(r"^[^:]*:\s*", "", line).strip()
            break
    fixes = [ln.strip("-• ").strip() for ln in text.splitlines() if re.match(r"^\s*[-•\d]", ln)]
    obj = {"biggest_gap": gap or (text.strip().split("\n")[0][:240] if text.strip() else ""), "must_fix": fixes[:5], "pick": "oracle"}
gap = str(obj.get("biggest_gap") or "").strip()
# Contrato canônico de veredito (v4, fase 5): gap EVASIVO ("none", "n/a",
# "nenhuma"...) vira gap VAZIO — assim o call site mantém o gap heurístico do
# oracle log em vez de injetar lixo no feedback. O vocabulário é IMPORTADO do
# bin/check-verdict.py (o validador do ring close): vocabulário duplicado
# deriva, que é a classe 3 do docs/v4-plan.md. Sem o arquivo, segue sem o
# filtro (comportamento pré-v4), nunca com uma cópia local da lista.
_cv = os.environ.get("ORACFIT_CHECK_VERDICT") or ""
if _cv and os.path.isfile(_cv):
    import importlib.util
    _spec = importlib.util.spec_from_file_location("checkverdict", _cv)
    _mod = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_mod)
    if gap.lower() in _mod.EVASIVE:
        gap = ""
fixes = obj.get("must_fix") or obj.get("fixes") or []
if isinstance(fixes, str):
    fixes = [fixes]
fixes = [str(x).strip() for x in fixes if str(x).strip()][:5]
pick = str(obj.get("pick") or "oracle").strip().lower()
if pick not in ("oracle", "ours", "bar"):
    pick = "oracle"
print(json.dumps({"biggest_gap": gap, "must_fix": fixes, "pick": pick}, ensure_ascii=False))
PY
}

# Append structured critic block to accum (P3). Echoes biggest_gap.
oracfit_gauntlet_append_critic_structured() {
  local accum="${1:?}"
  local attempt="${2:?}"
  local critic_json="${3:?}"  # one JSON object
  mkdir -p "$(dirname "$accum")"
  python3 - "$accum" "$attempt" "$critic_json" <<'PY'
import json, sys
from pathlib import Path
accum, attempt, raw = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
obj = json.loads(raw)
gap = obj.get("biggest_gap") or ""
fixes = obj.get("must_fix") or []
pick = obj.get("pick") or "oracle"
lines = [
    "",
    f"## GAUNTLET CRITIC (attempt {attempt}) — structured",
    "",
    f"pick: {pick}",
    f"Single biggest remaining gap: {gap}",
    "",
    "must_fix:",
]
for f in fixes:
    lines.append(f"- {f}")
lines += [
    "",
    "The critic is harsh. Praise is not useful. Apply must_fix before resubmitting.",
    "",
]
with accum.open("a", encoding="utf-8") as fh:
    fh.write("\n".join(lines))
print(gap)
PY
}

# Resolve critic_model_ref: env CRITIC_MODEL_REF vence; senão lê do mode YAML.
# Vazio (sem critic configurado) → chamador pula o critic (feedback heurístico só).
oracfit_gauntlet_critic_ref() {
  local mode_yaml="${1:-}"
  local env_ref="${CRITIC_MODEL_REF:-}"
  if [ -n "$env_ref" ]; then
    printf '%s\n' "$env_ref"
    return 0
  fi
  [ -z "$mode_yaml" ] && return 0
  oracfit_gauntlet_cfg "$mode_yaml" critic_model_ref 2>/dev/null || true
}

# Persona do critic, trocável por perfil (v3.5, triagem do relatório
# fábrica-agentic §5.1 — docs/pesquisa/2026-08-12-triagem-fabrica-agentic-v3.5.md).
# DISPATCH_CRITIC_PROFILE aceita caminho absoluto OU nome de arquivo (sem .md)
# em core/critic-profiles/. O perfil contém SÓ a persona/protocolo de avaliação;
# o contrato JSON (biggest_gap/must_fix/pick) fica fora dele, nos call sites,
# porque o parse depende desse shape. Perfil ausente/ilegível → persona default
# com aviso (fail-open: critic ruim é melhor que stage travado).
oracfit_gauntlet_critic_persona() {
  local prof="${DISPATCH_CRITIC_PROFILE:-}" f=""
  if [ -n "$prof" ]; then
    if [ -f "$prof" ]; then
      f="$prof"
    elif [ -n "${ORACFIT_ROOT:-}" ] && [ -f "${ORACFIT_ROOT}/core/critic-profiles/${prof%.md}.md" ]; then
      f="${ORACFIT_ROOT}/core/critic-profiles/${prof%.md}.md"
    else
      echo "gauntlet: DISPATCH_CRITIC_PROFILE='$prof' não encontrado (nem caminho, nem core/critic-profiles/) — usando persona default" >&2
    fi
  fi
  if [ -n "$f" ]; then
    cat "$f"
  else
    echo "Você é um crítico HARSH do gauntlet com contexto FRESCO (você NÃO construiu o trabalho)."
  fi
}

# Call site do critic estruturado (fit 2026-08-09, passo 3 — veredito judge: A).
# Despacha um mini-spec de critic via $DISPATCH_RUNNER (mesmo mecanismo do builder),
# herdando timeout/watchdog/ledger/auth do runner. NÃO re-entra o gauntlet: o mini-spec
# é sem oracle/comando (armadilha do judge — senão feedback recursivo infinito).
# Args: mode_yaml driver_model_ref oracle_log accum attempt barra_file
# Echoes: o biggest_gap do critic (vazio se não rodou ou falhou parse). Escreve o bloco
# estruturado no accum via append_critic_structured.
oracfit_gauntlet_run_critic() {
  local mode_yaml="${1:-}"
  local driver_ref="${2:-}"
  local oracle_log="${3:-}"
  local accum="${4:-}"
  local attempt="${5:-}"
  local barra_file="${6:-}"
  local critic_ref runner critic_runner oracle_sig log_tail barra crit_spec raw cjson gap
  local with_timeout critic_timeout critic_rc

  # fail-open: args ausentes não derrubam o stage loop
  if [ -z "$driver_ref" ] || [ -z "$oracle_log" ] || [ -z "$accum" ] || [ -z "$attempt" ]; then
    echo "gauntlet: run_critic sem driver_ref/oracle_log/accum/attempt, skipping critic" >&2
    return 0
  fi

  critic_ref="$(oracfit_gauntlet_critic_ref "$mode_yaml")"
  # Sem critic configurado → nada a fazer (feedback heurístico já foi pelo append_feedback).
  [ -z "$critic_ref" ] && return 0
  # Critic não pode ser o mesmo modelo do driver — senão é o builder se criticando.
  if [ "$critic_ref" = "$driver_ref" ]; then
    echo "gauntlet: critic_model_ref == driver ($critic_ref), skipping critic (no gain)" >&2
    return 0
  fi
  runner="${DISPATCH_RUNNER:-}"
  if [ -z "$runner" ] || [ ! -x "$runner" ]; then
    echo "gauntlet: DISPATCH_RUNNER ausente/não executável, skipping critic" >&2
    return 0
  fi

  oracle_sig="$(head -c 2000 "$oracle_log" 2>/dev/null || true)"
  log_tail="$([ -s "$oracle_log" ] && tail -c 1500 "$oracle_log" || echo "$oracle_sig")"
  barra="$([ -n "$barra_file" ] && [ -s "$barra_file" ] && cat "$barra_file" || echo "(oracle only)")"

  # Mini-spec SEM ## Oraculo (sem oracle:true, sem comando:) — armadilha do judge.
  crit_spec="$(mktemp "${TMPDIR:-/tmp}/oracfit-critic-XXXXXX")"
  {
    echo "## Objetivo"
    echo ""
    oracfit_gauntlet_critic_persona
    echo "Analise a falha do oráculo abaixo e responda APENAS um objeto JSON."
    echo ""
    echo "## Falha do oráculo (o que o builder produziu e foi reprovado)"
    echo '```'
    printf '%s\n' "$oracle_sig"
    echo '```'
    echo ""
    echo "## Barra (referência do que 'bom' significa)"
    printf '%s\n' "$barra"
    echo ""
    echo "## Resposta exigida"
    echo ""
    echo "Reply ONLY one JSON object (no markdown fences, no praise):"
    echo '{"biggest_gap":"single biggest remaining gap","must_fix":["fix1","fix2"],"pick":"oracle"}'
    echo "pick must be oracle|ours|bar. must_fix max 5 short imperative lines."
  } >"$crit_spec"

  # Regra 12: dispatch do critic toca rede/modelo → teto obrigatório via
  # bin/with-timeout.sh. Sem teto, um provider degradado (resposta que nunca
  # chega) bloqueia o stage loop inteiro e o run morre sem attempt 2
  # (incidents/2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished.md).
  with_timeout=""
  if [ -n "${ORACFIT_ROOT:-}" ] && [ -x "${ORACFIT_ROOT}/bin/with-timeout.sh" ]; then
    with_timeout="${ORACFIT_ROOT}/bin/with-timeout.sh"
  else
    local _gauntlet_lib_dir
    _gauntlet_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [ -x "${_gauntlet_lib_dir}/with-timeout.sh" ]; then
      with_timeout="${_gauntlet_lib_dir}/with-timeout.sh"
    fi
  fi
  critic_timeout="${ORACFIT_CRITIC_TIMEOUT:-180}"

  # Incidente B2/E5-M4: critic_model_ref tier:* não é id — expande pela
  # cadeia do catálogo free carimbado em vez de entregar cru ao runner.
  case "$critic_ref" in
    tier:*)
      if [ -f "${_gauntlet_lib_dir}/run-with-fallback.sh" ]; then
        critic_runner="${_gauntlet_lib_dir}/run-with-fallback.sh"
      else
        echo "gauntlet: run-with-fallback.sh ausente — critic tier: sem resolução, skipping" >&2
        return 0
      fi
      ;;
    *) critic_runner="$runner" ;;
  esac

  # Despacha via runner (mesmo shape do builder), captura stdout.
  critic_rc=0
  if [ -n "$with_timeout" ]; then
    raw="$(bash "$with_timeout" "$critic_timeout" "$critic_runner" "$critic_ref" "$crit_spec" 2>/dev/null)" || critic_rc=$?
  else
    echo "gauntlet: with-timeout.sh não encontrado — critic sem teto (regra 12)" >&2
    raw="$("$critic_runner" "$critic_ref" "$crit_spec" 2>/dev/null)" || critic_rc=$?
  fi
  rm -f "$crit_spec"

  # Fail open: teto estourado → gap vazio, o feedback heurístico já anexado
  # permanece e o stage loop segue para o próximo attempt sem bloquear.
  if [ "$critic_rc" -eq 124 ]; then
    echo "gauntlet: critic ($critic_ref) timeout após ${critic_timeout}s (ORACFIT_CRITIC_TIMEOUT) — fail open, mantendo feedback heurístico" >&2
    return 0
  fi
  raw="$(printf '%s\n' "$raw" | grep -vE '^(>|$)' | head -c 4000 || true)"

  if [ -z "$raw" ]; then
    echo "gauntlet: critic ($critic_ref) retornou vazio, mantendo feedback heurístico" >&2
    return 0
  fi
  cjson="$(oracfit_gauntlet_parse_critic_json "$raw" 2>/dev/null || true)"
  if [ -z "$cjson" ]; then
    echo "gauntlet: critic não parseou JSON, mantendo feedback heurístico" >&2
    return 0
  fi
  gap="$(oracfit_gauntlet_append_critic_structured "$accum" "$attempt" "$cjson" 2>/dev/null || true)"
  oracfit_emit_event critic_dispatch model="$critic_ref" attempt="$attempt" gap="${gap:0:120}" 2>/dev/null || true
  printf '%s\n' "$gap"
}

# True if new_gap is substantially the same as prev_gap (stuck critic).
oracfit_gauntlet_gap_stuck() {
  local prev="${1:-}"
  local new="${2:-}"
  python3 - "$prev" "$new" <<'PY'
import sys
a, b = sys.argv[1].strip().lower(), sys.argv[2].strip().lower()
if not a or not b:
    sys.exit(1)
if a == b:
    sys.exit(0)
# token overlap
sa, sb = set(a.split()), set(b.split())
if not sa or not sb:
    sys.exit(1)
overlap = len(sa & sb) / max(len(sa | sb), 1)
sys.exit(0 if overlap >= 0.7 else 1)
PY
}

# Append one gauntlet round to an accum feedback markdown file.
oracfit_gauntlet_append_feedback() {
  local accum="${1:?}"
  local attempt="${2:?}"
  local oracle_exit="${3:?}"
  local logfile="${4:?}"
  local biggest_gap
  biggest_gap="$(oracfit_gauntlet_biggest_gap "$logfile" "$oracle_exit")"
  mkdir -p "$(dirname "$accum")"
  {
    echo ""
    echo "## GAUNTLET FEEDBACK (attempt ${attempt}) — apply ALL before resubmitting"
    echo ""
    echo "Oracle exit: ${oracle_exit}"
    echo "Single biggest remaining gap: ${biggest_gap}"
    echo ""
    echo "The critic is harsh. Praise is not useful. Fix the gap above."
    echo "Do not stop until the oracle command passes (exit 0)."
    echo ""
    echo "Oracle output (truncated):"
    echo '```'
    head -c 4000 "$logfile" 2>/dev/null || true
    echo ""
    echo '```'
  } >>"$accum"
  # Print gap for callers/logs
  printf '%s\n' "$biggest_gap"
}

# Compose base spec + optional ground-truth + feedback accum → out_spec.
# Args: base_spec accum out_spec [ground_truth_file]
oracfit_gauntlet_compose_spec() {
  local base_spec="${1:?}"
  local accum="${2:?}"
  local out_spec="${3:?}"
  local gt_file="${4:-}"
  {
    cat "$base_spec"
    if [ -n "$gt_file" ] && [ -s "$gt_file" ]; then
      echo ""
      echo "<!-- oracfit-ground-truth: refresh on each attempt/resume; do not invent beyond this -->"
      echo "## GROUND TRUTH (Oracfit inject — authoritative for this run)"
      echo ""
      cat "$gt_file"
      echo ""
    fi
    if [ -s "$accum" ]; then
      echo ""
      echo "<!-- oracfit-gauntlet: injected feedback; do not remove -->"
      cat "$accum"
    fi
  } >"$out_spec"
}
