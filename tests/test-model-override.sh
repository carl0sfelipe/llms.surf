#!/bin/bash
# tests/test-model-override.sh — roteamento de modelo configurável
# (DISPATCH_TIERS + DISPATCH_MODEL_REF).
#
# Fecha dois incidentes (classe C):
# - incidents/2026-08-11-dispatch-batch-v2-2-hardcoded-tiers-open.md
# - incidents/2026-08-11-prompt-v3-travelview-espera-override-dis.md
#
# Padrão: tests/test-stage-runner.sh (stub runner em adapters/stub/runner.sh,
# mktemp, contadores pass/fail, exit 1 se falhar).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGES="$ROOT/bin/dispatch-stages.sh"
ESCALATE="$ROOT/bin/dispatch-escalate.sh"
BATCH="$ROOT/bin/dispatch-batch.sh"
STUB="$ROOT/adapters/stub/runner.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-model-override.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Spec base usada pelos testes de stages. O oráculo (test -f override-marker)
# é pré-passado (touch abaixo) pra que o preflight libere o run: em modo
# multi-stage (2 stages) o preflight aceita oráculo já-passando (resume path).
SPEC_TEMPLATE() {
  cat <<'EOF'
# Model override fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
python3 -c "raise SystemExit(0)"

## Oráculo
- comando: test -f override-marker
- exit esperado: 0

## Barra
- nome: model override fixture

NUNCA use declare const como workaround.
EOF
}

# ── 1. dispatch-stages.sh: stage com model_ref + DISPATCH_MODEL_REF ─────────
# O stub runner grava argv em $ORACFIT_STAGE_ARTIFACTS/stub-proof (linha
# "model_id=<argv[1]>"). Override → argv[1] deve ser o valor da env.
A_DIR="$TMPDIR/stages-override"
mkdir -p "$A_DIR/core/modes"
SPEC_TEMPLATE >"$A_DIR/spec.md"
touch "$A_DIR/override-marker"
cat >"$A_DIR/core/modes/override-fixture.yaml" <<'EOF'
id: override-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-default-model
    stage_oracle: "true"
    max_attempts: 1
  - role: export
    command: "touch \"$ORACFIT_WORKDIR/export-ran\""
    stage_oracle: "true"
    max_attempts: 1
on_fail: halt
EOF
rc=0
A_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" DISPATCH_MODEL_REF="env-override-model" \
    "$STAGES" override-fixture "$A_DIR/spec.md" override-test \
    --workdir "$A_DIR" 2>&1
)" || rc=$?
# stub-proof do stage "run" carimba model_id=$argv1 pós-override. O stub grava
# em $WD/.dispatch/stub-proof (sem ponto no nome) e copia pra
# artifacts/<run_id>/<role>/stub-proof — usar o do workdir, sempre presente.
stub_proof="$(ls "$A_DIR"/.dispatch/stub-proof 2>/dev/null | head -1 || true)"
model_id_line=""
[ -n "$stub_proof" ] && model_id_line="$(grep '^model_id=' "$stub_proof" 2>/dev/null | head -1 || true)"
# Stage com model_ref chama o RUNNER e ignora `command` — não há marker do
# stage 1; a prova do override é o stub-proof. O export mecânico prova que o
# pipeline seguiu até o fim.
if [ "$rc" -eq 0 ] \
  && [ -f "$A_DIR/export-ran" ] \
  && [ "$model_id_line" = "model_id=env-override-model" ]; then
  ok "dispatch-stages: stage com model_ref recebe o valor de DISPATCH_MODEL_REF (stub viu '$model_id_line')"
else
  not "dispatch-stages override falhou (rc=$rc proof=${stub_proof:-NONE} id='${model_id_line:-NONE}'): $A_OUT"
fi

# ── 2. dispatch-stages.sh: stage mecânico + DISPATCH_MODEL_REF NÃO vira modelo ─
# Stage sem model_ref roda o command direto; runner nunca é chamado; override
# não se aplica. Sinais: marker do command presente; stub-proof AUSENTE.
B_DIR="$TMPDIR/stages-mechanical"
mkdir -p "$B_DIR/core/modes"
SPEC_TEMPLATE >"$B_DIR/spec.md"
touch "$B_DIR/override-marker"
cat >"$B_DIR/core/modes/mechanical-fixture.yaml" <<'EOF'
id: mechanical-fixture
version: "1"
stages:
  - role: run
    command: "touch \"$ORACFIT_WORKDIR/mech-ran\""
    stage_oracle: "true"
    max_attempts: 1
  - role: export
    command: "true"
    stage_oracle: "true"
    max_attempts: 1
on_fail: halt
EOF
rc=0
B_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" DISPATCH_MODEL_REF="should-not-apply" \
    "$STAGES" mechanical-fixture "$B_DIR/spec.md" mech-test \
    --workdir "$B_DIR" 2>&1
)" || rc=$?
any_stub_proof="$(ls "$B_DIR"/.dispatch/stub-proof 2>/dev/null | head -1 || true)"
if [ "$rc" -eq 0 ] \
  && [ -f "$B_DIR/mech-ran" ] \
  && [ -z "$any_stub_proof" ]; then
  ok "dispatch-stages: stage mecânico continua mecânico mesmo com DISPATCH_MODEL_REF setada (runner não chamado)"
else
  not "dispatch-stages stage mecânico virou modelo indevidamente (rc=$rc stub=${any_stub_proof:-NONE}): $B_OUT"
fi

# ── 3. dispatch-batch.sh: parse 4 campos | 3 campos continuam aceitos ───────
# Unitário: extrai o bloco de parse do bin/dispatch-batch.sh (ancorado entre
# marcadores) e roda isolado num sub-bash com BATCH_FILE de fixture. Assim
# medimos a lógica de produção sem despachar modelo nem montar gate completo.
# Duplicate the production parser verbatim-by-source via sed extraction keeps
# drift-preto: se o bloco de parse mudar de marcadores, o teste quebra (bom).
PARSE_SRC="$TMPDIR/parse-block.sh"
sed -n '/# ── parse/,/^TOTAL=\${#SPECS\[@\]}/p' "$BATCH" \
  | sed '${/^TOTAL=\${#SPECS\[@\]}/d;}' >"$PARSE_SRC"
# Sanity: o bloco extraído precisa referenciar BATCH_FILE e os 4 arrays.
if ! grep -q 'BATCH_FILE' "$PARSE_SRC" || ! grep -q 'MODEL_REFS' "$PARSE_SRC"; then
  not "extração do bloco de parse falhou (marcadores mudaram?): $PARSE_SRC"
else
  FIXTURE_BATCH="$TMPDIR/batch.txt"
  cat >"$FIXTURE_BATCH" <<'EOF'
# comentário; linha vazia abaixo

item1-spec.md|item1-task|/tmp/dir1
item2-spec.md|item2-task|/tmp/dir2|item2-override-model
item3-spec.md|item3-task|/tmp/dir3|
EOF
  export BATCH_FILE="$FIXTURE_BATCH"
  unset SPECS TASKS DIRS MODEL_REFS
  parse_out="$(SPECS=() TASKS=() DIRS=() MODEL_REFS=() LINENO_=0 bash -c "
    set -uo pipefail
    $(cat "$PARSE_SRC")
    printf 'N=%s\\n' \${#SPECS[@]}
    for i in \${!SPECS[@]}; do
      printf 'item[%s]: spec=%s task=%s dir=%s mref=[%s]\\n' \
        \"\$i\" \"\${SPECS[\$i]}\" \"\${TASKS[\$i]}\" \"\${DIRS[\$i]}\" \"\${MODEL_REFS[\$i]}\"
    done
  " 2>&1)"
  expected_n=3
  expected_item2="item[1]: spec=item2-spec.md task=item2-task dir=/tmp/dir2 mref=[item2-override-model]"
  expected_item1="item[0]: spec=item1-spec.md task=item1-task dir=/tmp/dir1 mref=[]"
  expected_item3="item[2]: spec=item3-spec.md task=item3-task dir=/tmp/dir3 mref=[]"
  if printf '%s\n' "$parse_out" | grep -q "^N=$expected_n\$" \
    && printf '%s\n' "$parse_out" | grep -qF "$expected_item2" \
    && printf '%s\n' "$parse_out" | grep -qF "$expected_item1" \
    && printf '%s\n' "$parse_out" | grep -qF "$expected_item3"; then
    ok "dispatch-batch: 4º campo model_ref parseia; linha de 3 campos continua aceita"
  else
    not "dispatch-batch parser divergiu do esperado: $parse_out"
  fi
fi

# ── 4. dispatch-escalate.sh: DISPATCH_TIERS substitui o array TIERS ─────────
# Debug echo barato no início do run (stderr): 'tiers=<lista>'. A spec tem
# `- comando: true` → run_oracle passa imediatamente e o script exita 0 logo
# APÓS o echo, sem despachar modelo real. Capturamos só o stderr.
ESCALATE_SPEC="$TMPDIR/escalate-spec.md"
cat >"$ESCALATE_SPEC" <<'EOF'
# Escalate override fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
python3 -c "raise SystemExit(0)"

## Oráculo
- comando: true
- exit esperado: 0

## Barra
- nome: escalate override fixture

NUNCA use declare const como workaround.
EOF
LOG_DIR="$TMPDIR/escalate-logs"
mkdir -p "$LOG_DIR"
rc=0
ESC_ERR="$(LOG_DIR="$LOG_DIR" \
  DISPATCH_TIERS="alpha-free-model zhipuai/glm-5.2-coding-plan" \
  bash "$ESCALATE" "$ESCALATE_SPEC" override-escalate-test --mode 2 2>&1 >/dev/null)" || rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$ESC_ERR" | grep -qF '[dispatch-escalate] tiers=alpha-free-model zhipuai/glm-5.2-coding-plan'; then
  ok "dispatch-escalate: DISPATCH_TIERS substitui o array TIERS na ordem dada"
else
  not "dispatch-escalate override falhou (rc=$rc): $ESC_ERR"
fi

# Bônus: sem DISPATCH_TIERS, mode 2 mantém os tiers default (não inventa).
rc=0
ESC_ERR2="$(LOG_DIR="$LOG_DIR" \
  bash "$ESCALATE" "$ESCALATE_SPEC" override-escalate-default --mode 2 2>&1 >/dev/null)" || rc=$?
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$ESC_ERR2" | grep -qF '[dispatch-escalate] tiers=opencode/nemotron-3-ultra-free opencode/deepseek-v4-pro'; then
  ok "dispatch-escalate: sem DISPATCH_TIERS, mantém tiers default do mode (regressão OK)"
else
  not "dispatch-escalate default tiers quebrou (rc=$rc): $ESC_ERR2"
fi

echo
echo "=== RESULTS: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
