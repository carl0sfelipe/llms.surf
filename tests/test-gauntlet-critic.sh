#!/bin/bash
# tests/test-gauntlet-critic.sh — Call site do critic estruturado (passo 3, veredito judge A).
#
# O critic_model_ref é despachado via $DISPATCH_RUNNER quando o oráculo reprova.
# Este teste usa um MOCK RUNNER (script que retorna JSON de critic fixo) para não gastar
# modelo real. Assere:
#   (a) critic_model_ref != driver_ref → critic roda; == → skip (no gain)
#   (b) o critic é despachado via runner (mock registra a chamada)
#   (c) o feedback estruturado aparece no accum (append_critic_structured)
#   (d) sem critic_model_ref → nada muda (feedback heurístico só)
#   (e) armadilha do judge: mini-spec do critic NÃO tem ## Oraculo (sem recursão)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-critic.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

source "$REPO_ROOT/bin/lib-oracfit-gauntlet.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# Mode YAML de teste com critic_model_ref configurado.
MODE_YAML="$TMPDIR/mode-test.yaml"
cat >"$MODE_YAML" <<'EOF'
id: test_critic
stages:
  - role: run
    model_ref: deepseek/deepseek-v4-flash-direct
    oracle: true
gauntlet:
  enabled: true
  inject_feedback: true
  critic_model_ref: deepseek/deepseek-reasoner
EOF

# Mock runner: registra args num log de chamadas e emite um JSON de critic válido.
MOCK_RUNNER="$TMPDIR/mock-runner.sh"
CALL_LOG="$TMPDIR/runner-calls.log"
: >"$CALL_LOG"
cat >"$MOCK_RUNNER" <<EOF
#!/bin/bash
echo "CALL model=\$1 spec=\$2" >>"$CALL_LOG"
# Registra o conteúdo do mini-spec para o teste inspecionar (armadilha do judge).
cp "\$2" "$TMPDIR/last-critic-spec.md" 2>/dev/null || true
cat <<'JSON'
{"biggest_gap":"falta evidência de preço ancorada no copy","must_fix":["adicionar tabela de preço comparativo","citar fonte da cotação"],"pick":"oracle"}
JSON
EOF
chmod +x "$MOCK_RUNNER"

ACCUM="$TMPDIR/feedback.md"; : >"$ACCUM"
ORACLE_LOG="$TMPDIR/oracle.log"
printf 'ORACLE FAIL: decision REJECTED — missing price evidence\n' >"$ORACLE_LOG"

# --- (1) critic_model_ref resolvido do YAML ------------------------------------
REF="$(oracfit_gauntlet_critic_ref "$MODE_YAML")"
if [ "$REF" = "deepseek/deepseek-reasoner" ]; then
  ok "critic_model_ref lido do mode YAML: $REF"
else
  bad "critic_model_ref não resolvido do YAML (got '$REF')"
fi

# --- (2) env CRITIC_MODEL_REF vence sobre o YAML -------------------------------
REF_ENV="$(CRITIC_MODEL_REF="via-env/strong" oracfit_gauntlet_critic_ref "$MODE_YAML")"
if [ "$REF_ENV" = "via-env/strong" ]; then
  ok "env CRITIC_MODEL_REF vence sobre o YAML: $REF_ENV"
else
  bad "env não venceu (got '$REF_ENV')"
fi

# --- (3) CICLO PRINCIPAL: critic despachado via runner + feedback estruturado --
DISPATCH_RUNNER="$MOCK_RUNNER" \
  DRIVER_REF="deepseek/deepseek-v4-flash-direct" \
  CRITIC_GAP=$(oracfit_gauntlet_run_critic "$MODE_YAML" "deepseek/deepseek-v4-flash-direct" "$ORACLE_LOG" "$ACCUM" 1 "$TMPDIR/empty-barra.md" 2>/dev/null || true)

# (3a) o mock runner foi chamado?
if [ -s "$CALL_LOG" ]; then
  ok "critic despachado via \$DISPATCH_RUNNER (mock registrou a chamada)"
else
  bad "runner mock não foi chamado pelo critic"
fi

# (3b) o modelo despachado é o critic, não o driver?
CALLED_MODEL=$(grep -oE 'model=[^ ]+' "$CALL_LOG" | head -1 | cut -d= -f2)
if [ "$CALLED_MODEL" = "deepseek/deepseek-reasoner" ]; then
  ok "runner recebeu critic_model_ref ($CALLED_MODEL), não o driver"
else
  bad "runner recebeu modelo errado: '$CALLED_MODEL'"
fi

# (3c) o feedback estruturado (biggest_gap do JSON) está no accum?
if grep -qF "falta evidência de preço ancorada no copy" "$ACCUM" && grep -qF "GAUNTLET CRITIC" "$ACCUM"; then
  ok "feedback estruturado do critic injetado no accum (append_critic_structured)"
else
  bad "accum não contém o feedback estruturado do critic"
fi

# (3d) o biggest_gap ecoado bate com o do JSON?
if [ -n "$CRITIC_GAP" ] && echo "$CRITIC_GAP" | grep -qF "falta evidência de preço"; then
  ok "run_critic ecoou o biggest_gap do critic: $CRITIC_GAP"
else
  bad "run_critic não ecoou o gap (got '$CRITIC_GAP')"
fi

# --- (4) ARMADILHA DO JUDGE: mini-spec NÃO tem ## Oraculo (sem recursão) -------
if [ -f "$TMPDIR/last-critic-spec.md" ]; then
  if grep -qiE '^## Oracul' "$TMPDIR/last-critic-spec.md" || grep -qiE 'oracle:.*true|comando:' "$TMPDIR/last-critic-spec.md"; then
    bad "mini-spec do critic tem ## Oraculo/oracle/comando — armadilha do judge (recursão)"
  else
    ok "mini-spec do critic SEM oráculo (armadilha do judge evitada)"
  fi
else
  bad "mini-spec do critic não foi capturado pelo mock"
fi

# --- (5) critic_model_ref == driver → skip (no gain) ---------------------------
ACCUM2="$TMPDIR/feedback2.md"; : >"$ACCUM2"
SKIP_OUT=$(DISPATCH_RUNNER="$MOCK_RUNNER" oracfit_gauntlet_run_critic "$MODE_YAML" "deepseek/deepseek-reasoner" "$ORACLE_LOG" "$ACCUM2" 1 "$TMPDIR/empty-barra.md" 2>&1 >/dev/null || true)
CALLS_BEFORE=$(wc -l <"$CALL_LOG" | tr -d ' ')
if echo "$SKIP_OUT" | grep -q "skipping critic"; then
  ok "critic pulado quando critic_model_ref == driver (no gain)"
else
  bad "critic não pulou quando == driver (esperava skip)"
fi

# --- (6) sem critic_model_ref (mode sem o campo) → nada muda -------------------
MODE_NO_CRITIC="$TMPDIR/mode-no-critic.yaml"
cat >"$MODE_NO_CRITIC" <<'EOF'
id: test_no_critic
stages:
  - role: run
    model_ref: deepseek/deepseek-v4-flash-direct
    oracle: true
gauntlet:
  enabled: true
EOF
ACCUM3="$TMPDIR/feedback3.md"; : >"$ACCUM3"
NOCRIT_GAP=$(DISPATCH_RUNNER="$MOCK_RUNNER" oracfit_gauntlet_run_critic "$MODE_NO_CRITIC" "deepseek/deepseek-v4-flash-direct" "$ORACLE_LOG" "$ACCUM3" 1 "$TMPDIR/empty-barra.md" 2>/dev/null || true)
if [ -z "$NOCRIT_GAP" ] && [ ! -s "$ACCUM3" ]; then
  ok "sem critic_model_ref → run_critic não altera nada (feedback heurístico preservado)"
else
  bad "sem critic_model_ref, run_critic produziu output inesperado (gap='$NOCRIT_GAP')"
fi

# --- (7) driver_ref vazio → fail-open (rc 0, stdout vazio, accum intacto) ------
ACCUM4="$TMPDIR/feedback4.md"; : >"$ACCUM4"
SKIP_EMPTY_RC=0
SKIP_EMPTY_OUT=$(DISPATCH_RUNNER="$MOCK_RUNNER" oracfit_gauntlet_run_critic "$MODE_YAML" "" "$ORACLE_LOG" "$ACCUM4" 1 "$TMPDIR/empty-barra.md" 2>"$TMPDIR/skip-empty-driver.stderr" || SKIP_EMPTY_RC=$?)
SKIP_EMPTY_ERR=$(cat "$TMPDIR/skip-empty-driver.stderr" 2>/dev/null || true)
if [ "$SKIP_EMPTY_RC" -eq 0 ] && [ -z "$SKIP_EMPTY_OUT" ] && echo "$SKIP_EMPTY_ERR" | grep -q "skipping critic" && [ ! -s "$ACCUM4" ]; then
  ok "driver_ref vazio → fail-open (rc 0, stdout vazio, accum intacto)"
else
  bad "driver_ref vazio não fez fail-open (rc=$SKIP_EMPTY_RC out='$SKIP_EMPTY_OUT' err='$SKIP_EMPTY_ERR')"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
