#!/bin/bash
# tests/test-gauntlet-feedback.sh — Canal de feedback N→N+1 do gauntlet.
#
# Quando o oráculo reprova no attempt N, o gauntlet grava o gap num accum
# (feedback.md) e o attempt N+1 recebe um spec composto que inclui esse feedback.
# Este teste protege esse canal: confirma que o input DO MODELO muda entre N e N+1
# e que o conteúdo do feedback aparece no spec composto. Sem run live — só as
# funções da lib (append_feedback + compose_spec).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d /tmp/oracfit-feedback.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

# shellcheck source=../bin/lib-oracfit-gauntlet.sh
source "$REPO_ROOT/bin/lib-oracfit-gauntlet.sh"

PASS=0; FAIL=0
ok()  { echo "PASS: $1"; PASS=$((PASS+1)); }
bad() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }

BASE_SPEC="$TMPDIR/base-spec.md"
ACCUM="$TMPDIR/feedback.md"
ORACLE_LOG_1="$TMPDIR/oracle-1.log"
: >"$ACCUM"

cat >"$BASE_SPEC" <<'EOF'
## Objetivo
Producir T4 APPROVED para o nicho X.

## Oraculo
- comando: test -f T4.yaml && grep -q APPROVED T4.yaml && echo OK
- exit esperado: 0
EOF

# --- Simula o oráculo do attempt 1 REPROVANDO ---------------------------------
# O oráculo real captura stdout/stderr; aqui simulamos uma saída de reprovação.
cat >"$ORACLE_LOG_1" <<'EOF'
grep: T4.yaml: No such file or directory
ORACLE FAIL: missing artifact T4.yaml
expected APPROVED but file not produced
EOF
ORACLE_EXIT_1=1

# append_feedback grava o gap no accum (o que o dispatch-stages faz na linha 200).
GAP1="$(oracfit_gauntlet_append_feedback "$ACCUM" 1 "$ORACLE_EXIT_1" "$ORACLE_LOG_1")"

# (1) accum não está vazio depois da reprovação do attempt 1.
if [ -s "$ACCUM" ]; then
  ok "accum feedback.md não-vazio após reprovação do attempt 1"
else
  bad "accum ficou vazio — feedback não foi gravado"
fi

# (2) o gap extraído aparece no accum.
if grep -qF "$GAP1" "$ACCUM"; then
  ok "gap extraído ('$GAP1') presente no accum"
else
  bad "gap não encontrado no accum"
fi

# --- Composição: spec do attempt 1 (sem feedback) vs attempt 2 (com feedback) --
SPEC_1="$TMPDIR/spec-attempt-1.md"
SPEC_2="$TMPDIR/spec-attempt-2.md"
EMPTY_ACCUM="$TMPDIR/empty-accum.md"; : >"$EMPTY_ACCUM"

# Attempt 1: compõe com accum vazio (ainda não houve reprovação).
oracfit_gauntlet_compose_spec "$BASE_SPEC" "$EMPTY_ACCUM" "$SPEC_1"
# Attempt 2: compõe com accum cheio (feedback do attempt 1 injetado).
oracfit_gauntlet_compose_spec "$BASE_SPEC" "$ACCUM" "$SPEC_2"

HASH_1=$(shasum -a 256 "$SPEC_1" | awk '{print $1}')
HASH_2=$(shasum -a 256 "$SPEC_2" | awk '{print $1}')

# (3) o input DO MODELO muda entre attempt 1 e attempt 2.
if [ "$HASH_1" != "$HASH_2" ]; then
  ok "input composto muda entre N e N+1 (hash divergente)"
else
  bad "input N+1 é idêntico a N — feedback não está chegando ao modelo"
fi

# (4) o conteúdo do feedback (gap + instruction) aparece no spec do attempt 2.
if grep -qF "GAUNTLET FEEDBACK" "$SPEC_2" && grep -qF "$GAP1" "$SPEC_2"; then
  ok "conteúdo do feedback aparece no spec composto do attempt 2"
else
  bad "spec do attempt 2 não contém o bloco de feedback"
fi

# (5) o spec do attempt 1 NÃO tem feedback (sanity — nada vaza antes da reprovação).
if ! grep -qF "GAUNTLET FEEDBACK" "$SPEC_1"; then
  ok "spec do attempt 1 não tem feedback (canal só ativa após reprovação)"
else
  bad "feedback vazou para o attempt 1 (acumulador não deveria ter conteúdo ainda)"
fi

# --- Segunda rodada de feedback: accum acumula (não sobrescreve) ---------------
cat >"$TMPDIR/oracle-2.log" <<'EOF'
T4.yaml exists but decision: REJECTED
missing price evidence in the copy
EOF
GAP2="$(oracfit_gauntlet_append_feedback "$ACCUM" 2 1 "$TMPDIR/oracle-2.log")"
COUNT_FEEDBACK_BLOCKS=$(grep -c "GAUNTLET FEEDBACK" "$ACCUM")
# (6) acumulador acumula rodadas (2 blocos após 2 reprovações).
if [ "$COUNT_FEEDBACK_BLOCKS" -ge 2 ]; then
  ok "accum acumula múltiplas rodadas ($COUNT_FEEDBACK_BLOCKS blocos após 2 reprovações)"
else
  bad "accum não acumulou rodadas (esperado ≥2 blocos, há $COUNT_FEEDBACK_BLOCKS)"
fi

# --- biggest_gap pula boilerplate do dispatch-stages ---------------------------
# Incidente 2026-08-12-biggest-gap-heuristic-pega-boilerplate: o logfile do
# oracle começa com "STAGE ORACLE FAILED: ..." (sempre presente) e o gap real
# do juiz vem depois. A heurística pegava a linha 1 e o builder refazia às cegas.
VISION_LOG="$TMPDIR/oracle-vision.log"
cat >"$VISION_LOG" <<'EOF'
STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1
VISION GATE REJECTED — biggest_gap:
The text contrast is poor; labels swallowed by map.
EOF
GAP_VISION="$(oracfit_gauntlet_biggest_gap "$VISION_LOG" 1)"

# (7) o gap real do juiz é extraído, não o boilerplate.
if [ "$GAP_VISION" = "The text contrast is poor; labels swallowed by map." ]; then
  ok "biggest_gap pula boilerplate e pega o gap articulado pelo juiz"
else
  bad "biggest_gap retornou '$GAP_VISION' em vez do gap real"
fi

# (8) logfile SÓ com boilerplate cai no fallback seguro (não retorna vazio).
ONLY_BOILER="$TMPDIR/oracle-boiler.log"
printf 'STAGE ORACLE FAILED: role=vision_gate attempt=1 exit=1\n' >"$ONLY_BOILER"
GAP_BOILER="$(oracfit_gauntlet_biggest_gap "$ONLY_BOILER" 1)"
if [ -n "$GAP_BOILER" ] && [[ "$GAP_BOILER" != "STAGE ORACLE FAILED"* ]]; then
  ok "logfile só-boilerplate cai no fallback ('$GAP_BOILER')"
else
  bad "fallback errado para logfile só-boilerplate: '$GAP_BOILER'"
fi

# (9) STAGE COMMAND FAILED com stream JSON cru do opencode no log: a heurística
# deve pular as linhas {"type":...} (mesmo contendo "error"/"failed" no meio)
# e pegar a linha de erro legível (run AA26BEB2, 2026-08-12).
JSON_LOG="$TMPDIR/oracle-jsonstream.log"
cat >"$JSON_LOG" <<'EOF'
STAGE COMMAND FAILED: role=run attempt=1 exit=1
{"type":"tool_use","timestamp":1786526318523,"sessionID":"ses_x","part":{"state":{"status":"error","input":{"filePath":"/x"}}}}
{"type":"step_start","timestamp":1786526429279,"sessionID":"ses_x"}
opencode: error: context length exceeded for model deepseek-v4-flash-free
EOF
GAP_JSON="$(oracfit_gauntlet_biggest_gap "$JSON_LOG" 1)"
if [ "$GAP_JSON" = "opencode: error: context length exceeded for model deepseek-v4-flash-free" ]; then
  ok "biggest_gap pula stream JSON cru e pega a linha de erro legível"
else
  bad "biggest_gap pegou '$GAP_JSON' em vez da linha de erro legível"
fi

# (10) Gradle: a primeira linha do stderr é boilerplate ("FAILURE: Build failed
# with an exception.") e o gap útil vem depois — a task que falhou. Incidente
# 2026-09-20-biggest-gap-le-a-primeira-linha-inutil-d: feedback de gap era o
# cabeçalho inútil em todas as tentativas do run R03.
GRADLE_LOG="$TMPDIR/oracle-gradle.log"
cat >"$GRADLE_LOG" <<'EOF'
FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':compileKotlin'.
> Compilation error; see the compiler error output for details.

* Try:
> Run with --stacktrace option to get the stack trace.

BUILD FAILED in 6s
EOF
GAP_GRADLE="$(oracfit_gauntlet_biggest_gap "$GRADLE_LOG" 1)"
if [ "$GAP_GRADLE" = "Execution failed for task ':compileKotlin'." ]; then
  ok "biggest_gap pula boilerplate do Gradle e pega a task que falhou"
else
  bad "biggest_gap pegou '$GAP_GRADLE' em vez da linha útil"
fi

# (11) Gradle/Kotlin: diagnóstico do compilador ("e: file: (l, c): ...") vem
# ANTES do bloco FAILURE — deve vencer como gap (é o mais acionável).
GRADLE_KT_LOG="$TMPDIR/oracle-gradle-kt.log"
cat >"$GRADLE_KT_LOG" <<'EOF'
e: file:///work/src/main/kotlin/PackVerifier.kt:42:13 unresolved reference: sha256
FAILURE: Build failed with an exception.

* What went wrong:
Execution failed for task ':compileKotlin'.
EOF
GAP_KT="$(oracfit_gauntlet_biggest_gap "$GRADLE_KT_LOG" 1)"
if [ "$GAP_KT" = "e: file:///work/src/main/kotlin/PackVerifier.kt:42:13 unresolved reference: sha256" ]; then
  ok "biggest_gap prefere o diagnóstico 'e:' do compilador Kotlin"
else
  bad "biggest_gap pegou '$GAP_KT' em vez do diagnóstico do compilador"
fi

echo
echo "=== Resumo: $PASS passaram, $FAIL falharam ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
