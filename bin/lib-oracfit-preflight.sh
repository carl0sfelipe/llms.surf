# lib-oracfit-preflight.sh — AD-11 ordered gates before model (FR-6)
# Source after lib-oracfit-events.sh when ORACFIT_RUN_ID may be set.
#
# oracfit_preflight <spec_file> <workdir>
# Exit: 0=ok to call model, 1=gate failed, 2=broken oracle (oracle_exit=2), 3=usage

oracfit_preflight() {
  local spec="${1:?oracfit_preflight: spec required}"
  local workdir="${2:?oracfit_preflight: workdir required}"
  local bin_dir root rc
  bin_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  if [ ! -f "$spec" ]; then
    echo "ERROR: preflight: spec not found: $spec" >&2
    return 3
  fi
  if [ ! -d "$workdir" ]; then
    echo "ERROR: preflight: workdir not found: $workdir" >&2
    return 3
  fi

  # (1) check-spec
  if bash "$bin_dir/check-spec.sh" "$spec"; then
    oracfit_emit_event preflight_result step=check-spec pass=true reason=ok 2>/dev/null || true
  else
    oracfit_emit_event preflight_result step=check-spec pass=false reason=check-spec-failed 2>/dev/null || true
    echo "ERROR: preflight failed at check-spec" >&2
    return 1
  fi

  # (2) facts (rule 37)
  if python3 "$bin_dir/check-spec-facts.py" "$spec" "$workdir"; then
    oracfit_emit_event preflight_result step=check-spec-facts pass=true reason=ok 2>/dev/null || true
  else
    oracfit_emit_event preflight_result step=check-spec-facts pass=false reason=facts-failed 2>/dev/null || true
    echo "ERROR: preflight failed at check-spec-facts (rule 37)" >&2
    return 1
  fi

  # (3) check-oracle (rule 39)
  # Exit: 0=fails for right reason (OK to dispatch), 1=already passes, 2=broken
  set +e
  python3 "$bin_dir/check-oracle.py" "$spec" "$workdir" --quiet
  rc=$?
  set -e
  case "$rc" in
    0)
      oracfit_emit_event preflight_result step=check-oracle pass=true reason=fails-correctly oracle_lint=0 2>/dev/null || true
      return 0
      ;;
    1)
      if [ "${ORACFIT_PREFLIGHT_STAGE_COUNT:-1}" -gt 1 ] 2>/dev/null; then
        oracfit_emit_event preflight_result step=check-oracle pass=true reason=already-passes-multistage-resume oracle_lint=1 stages="${ORACFIT_PREFLIGHT_STAGE_COUNT}" 2>/dev/null || true
        echo "preflight: oracle already passes; multi-stage mode (${ORACFIT_PREFLIGHT_STAGE_COUNT} stages) → resume permitido" >&2
        return 0
      fi
      oracfit_emit_event preflight_result step=check-oracle pass=false reason=already-passes oracle_lint=1 2>/dev/null || true
      echo "ERROR: preflight: oracle already passes before model (nothing to measure)" >&2
      return 1
      ;;
    2)
      oracfit_emit_event preflight_result step=check-oracle pass=false reason=broken-oracle oracle_lint=2 oracle_exit=2 2>/dev/null || true
      echo "ERROR: preflight: broken oracle (oracle_exit=2) — runner MUST NOT start" >&2
      echo "HINT: exit 2 = oráculo QUEBRADO (comando/regex inválido), NÃO 'falta trabalho'." >&2
      echo "HINT: conserte o ## Oráculo da spec / rode bin/check-oracle.py antes de chamar modelo." >&2
      echo "HINT: Oracfit (ex-Dispatch) — isto não se resolve com 'oracfit start' (esse comando não existe)." >&2
      return 2
      ;;
    *)
      oracfit_emit_event preflight_result step=check-oracle pass=false reason=oracle-judge-error oracle_lint=$rc 2>/dev/null || true
      echo "ERROR: preflight: check-oracle could not judge (exit $rc)" >&2
      return 1
      ;;
  esac
}

# ── Gate visual: predicado ÚNICO de gatilho por diff (v4) ────────────────────
# Mesma lista que `oracfit ring init` grava em state.json (visual_globs):
# ring e gauntlet decidem "o diff tocou tela?" pelo MESMO predicado — gate que
# só existe num caminho é a doença das regras 12/37/39 (docs/v4-plan.md, classe 5).
ORACFIT_VISUAL_GLOBS_DEFAULT="*.html *.css public/* *.svelte *.vue *.jsx *.tsx"

# oracfit_visual_hits [globs]
# stdin: lista de arquivos (um por linha). stdout: os que casam com os globs
# (caminho completo OU basename, fnmatch). Argumento omitido → default acima;
# argumento VAZIO ("") → gate desligado deliberadamente (nada casa).
#
# Caminho de TESTE não é hit visual (incidente 2026-08-13: *.tsx casou
# TradeControls.hedge.test.tsx num diff test-only, zero delta de UI, e o anel
# ficou inclosável exigindo screenshot). A exclusão vale SÓ quando os globs
# efetivos são o default acima — inclusive vindos do state.json que o
# `ring init` semeia com essa mesma lista. Globs custom (GAUNTLET_VISUAL_GLOBS
# ou state.json editado) são respeitados ao pé da letra, sem exclusão.
# Decisão: __snapshots__ também é excluído — snapshot de teste é artefato de
# teste, não evidência de tela renderizada.
oracfit_visual_hits() {
  local globs="${1-$ORACFIT_VISUAL_GLOBS_DEFAULT}"
  # consome stdin mesmo desligado: SIGPIPE sob pipefail viraria rc fantasma
  [ -n "$globs" ] || { cat >/dev/null; return 0; }
  local skip_tests=0
  [ "$globs" = "$ORACFIT_VISUAL_GLOBS_DEFAULT" ] && skip_tests=1
  # python3 -c, NUNCA heredoc (`python3 - <<PY`): o heredoc vira o stdin do
  # python e a lista canalizada some — o gate reprovava NADA em silêncio
  # (pego por tests/test-gates-dispatch.sh T1/T5 antes de shippar)
  ORACFIT_VISUAL_GLOBS="$globs" ORACFIT_VISUAL_SKIP_TESTS="$skip_tests" python3 -c '
import fnmatch, os, re, sys
globs = os.environ.get("ORACFIT_VISUAL_GLOBS", "").split()
skip_tests = os.environ.get("ORACFIT_VISUAL_SKIP_TESTS") == "1"
test_dir = re.compile(r"(^|/)(test|tests|__tests__|__mocks__|__snapshots__|spec)/", re.I)
test_name = re.compile(r"(^test_|\.test\.|\.spec\.|_test\.)", re.I)
for line in sys.stdin:
    f = line.strip()
    if not f:
        continue
    base = f.rsplit("/", 1)[-1]
    if skip_tests and (test_dir.search(f) or test_name.search(base)):
        continue
    if any(fnmatch.fnmatch(f, g) or fnmatch.fnmatch(base, g) for g in globs):
        print(f)
'
}

# Extract `- comando:` from ## Oráculo and run in workdir. Echoes exit code only on stdout last line via global.
oracfit_run_oracle_cmd() {
  local spec="${1:?}"
  local workdir="${2:?}"
  local cmd
  cmd="$(grep -iE '^[-*][[:space:]]*comando:' "$spec" | head -1 | sed -E 's/^[-*][[:space:]]*comando:[[:space:]]*//I')"
  if [ -z "$cmd" ]; then
    echo "ERROR: no oracle - comando: line in $spec" >&2
    return 3
  fi
  ( cd "$workdir" && eval "$cmd" )
}
