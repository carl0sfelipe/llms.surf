#!/bin/bash
# test-stage-input.sh — a stage that declares `input: prev_stage` must really
# read the work of the stages before it.
#
# The field was declared in the catalog and in the shipped modes (unlock_plan,
# vision_catalog) but nothing consumed it: the runtime composed the spec with
# the role and the artifacts dir only, so the expensive stage bought a result
# the next stage never saw. A declaration without a consumer is a promise with
# no body — this suite is the body.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
STAGES="$ROOT/bin/dispatch-stages.sh"
HELPER="$ROOT/bin/lib-oracfit-stage-input.py"
TMPDIR="$(mktemp -d /tmp/oracfit-stage-input.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Stage input fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
test -f .stage-input-marker

## Oráculo
- comando: true
- exit esperado: 0

## Barra
- nome: stage input fixture

NUNCA use declare const como workaround.
EOF
# english-ok-end

# The fake runner: it records the spec it was handed (per stage) and answers
# with a line the next stage can only see if the runtime really injected it.
FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
role="${ORACFIT_STAGE_ROLE:-unknown}"
if [ -n "${2:-}" ]; then
  cp "$2" "$ORACFIT_WORKDIR/spec-$role.md"
fi
if [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  printf 'note written by %s\n' "$role" >"$ORACFIT_STAGE_ARTIFACTS/note.txt"
fi
echo "ANSWER_FROM_$role"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

# ── case 1: the chain reaches the stages that ask for it ─────────────────────
CASE_DIR="$TMPDIR/chain-case"
mkdir -p "$CASE_DIR/core/modes"
cp "$SPEC" "$CASE_DIR/spec.md"
cat >"$CASE_DIR/core/modes/chain-fixture.yaml" <<'EOF'
id: chain-fixture
version: "1"
stages:
  - role: unlock
    model_ref: fixture-model
    artifacts: unlock/
  - role: plan
    model_ref: fixture-model
    input: prev_stage
    artifacts: plan/
  - role: run
    model_ref: fixture-model
    artifacts: run/
on_fail: halt
EOF
rc=0
CHAIN_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" chain-fixture "$CASE_DIR/spec.md" chain-test \
    --workdir "$CASE_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$CASE_DIR/spec-plan.md" ] \
  && grep -qF "ANSWER_FROM_unlock" "$CASE_DIR/spec-plan.md" \
  && grep -qF "note written by unlock" "$CASE_DIR/spec-plan.md" \
  && grep -qF "Previous stage output (input: prev_stage)" "$CASE_DIR/spec-plan.md"; then
  ok "the stage that declares input: prev_stage reads the previous stage's answer and files"
else
  not "input: prev_stage did not reach the next stage (rc=$rc): $CHAIN_OUT"
fi

if [ -f "$CASE_DIR/spec-run.md" ] \
  && ! grep -qF "ANSWER_FROM_unlock" "$CASE_DIR/spec-run.md"; then
  ok "a stage without input: prev_stage does not receive the previous output"
else
  not "the previous output leaked into a stage that did not ask for it: $CHAIN_OUT"
fi

# ── case 2: the chain accumulates (unlock -> plan -> run) ────────────────────
CHAIN_DIR="$TMPDIR/accum-case"
mkdir -p "$CHAIN_DIR/core/modes"
cp "$SPEC" "$CHAIN_DIR/spec.md"
cat >"$CHAIN_DIR/core/modes/accum-fixture.yaml" <<'EOF'
id: accum-fixture
version: "1"
stages:
  - role: unlock
    model_ref: fixture-model
  - role: plan
    model_ref: fixture-model
    input: prev_stage
  - role: run
    model_ref: fixture-model
    input: prev_stage
on_fail: halt
EOF
rc=0
ACCUM_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" accum-fixture "$CHAIN_DIR/spec.md" accum-test \
    --workdir "$CHAIN_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$CHAIN_DIR/spec-run.md" ] \
  && grep -qF "ANSWER_FROM_unlock" "$CHAIN_DIR/spec-run.md" \
  && grep -qF "ANSWER_FROM_plan" "$CHAIN_DIR/spec-run.md"; then
  ok "the last stage of the chain reads the whole chain, not only the last link"
else
  not "the chain did not accumulate (rc=$rc): $ACCUM_OUT"
fi

# ── case 3: a mechanical stage reads the chain through the environment ──────
MECH_DIR="$TMPDIR/mech-case"
mkdir -p "$MECH_DIR/core/modes"
cp "$SPEC" "$MECH_DIR/spec.md"
cat >"$MECH_DIR/core/modes/mech-input-fixture.yaml" <<'EOF'
id: mech-input-fixture
version: "1"
stages:
  - role: unlock
    model_ref: fixture-model
  - role: run
    command: "cp \"$ORACFIT_PREV_STAGE_INPUT_FILE\" \"$ORACFIT_WORKDIR/mech-input.md\"; printf '%s' \"$ORACFIT_PREV_STAGE_ROLE\" > \"$ORACFIT_WORKDIR/mech-prev-role.txt\""
    input: prev_stage
on_fail: halt
EOF
rc=0
MECH_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" mech-input-fixture "$MECH_DIR/spec.md" mech-test \
    --workdir "$MECH_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$MECH_DIR/mech-input.md" ] \
  && grep -qF "ANSWER_FROM_unlock" "$MECH_DIR/mech-input.md" \
  && [ "$(cat "$MECH_DIR/mech-prev-role.txt" 2>/dev/null || true)" = "unlock" ]; then
  ok "a mechanical stage reads the previous output through ORACFIT_PREV_STAGE_INPUT_FILE"
else
  not "the mechanical stage did not receive the previous output (rc=$rc): $MECH_OUT"
fi

# ── case 4: the loader refuses a promise the runtime cannot keep ────────────
cat >"$TMPDIR/first-stage-input.yaml" <<'EOF'
id: first-stage-input
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    input: prev_stage
EOF
rc=0
python3 "$LOADER" validate "$TMPDIR/first-stage-input.yaml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  ok "the loader refuses input: prev_stage on the first stage"
else
  not "the loader accepted a first stage that reads a stage that does not exist (rc=$rc)"
fi

# ── case 5: a stage that wrote nothing says so ──────────────────────────────
EMPTY_OUT="$(python3 "$HELPER" --role export --title "Output of stage 1 (role: export)")"
if printf '%s\n' "$EMPTY_OUT" | grep -qF "this stage wrote no output"; then
  ok "a stage with no output says so instead of leaving a silent empty block"
else
  not "the helper did not report the missing output: $EMPTY_OUT"
fi

echo "test-stage-input: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
