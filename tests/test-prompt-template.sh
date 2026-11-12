#!/bin/bash
# test-prompt-template.sh — a prompt a stage declares must be handed to the model.
#
# `prompt_template: NAME` used to be a promise nobody kept: the loader accepted
# the field, four shipped stages named a file, and neither dispatcher read it.
# A stage that declared a prompt received the same spec as a stage that did not.
#
# This suite is the mechanism that keeps the promise:
#   - both runtimes inject the file into the spec the runner receives
#   - a declared template that is missing fails the stage
#     (`PROMPT TEMPLATE NOT FOUND`)
#   - a stage that declares no template is not affected
#   - the loader refuses an empty or non-string value
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# A parent dispatch exports DISPATCH_MODEL_REF; the single-stage runtime
# would then demand that id in the registry instead of the fixture model.
unset DISPATCH_MODEL_REF
STAGES="$ROOT/bin/dispatch-stages.sh"
MODE="$ROOT/bin/dispatch-mode.sh"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
PT_LIB="$ROOT/bin/lib-oracfit-prompt-template.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-prompt-template.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Prompt template fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
test -f .prompt-template-marker

## Oráculo
- comando: test -f marker.txt
- exit esperado: 0

## Barra
- nome: prompt template fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
role="${ORACFIT_STAGE_ROLE:-unknown}"
if [ -n "${2:-}" ]; then
  cp "$2" "$ORACFIT_WORKDIR/spec-handed.md"
  cp "$2" "$ORACFIT_WORKDIR/spec-$role.md"
fi
printf 'work done\n' >"$ORACFIT_WORKDIR/marker.txt"
if [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  printf 'artifact written by %s\n' "$role" >"$ORACFIT_STAGE_ARTIFACTS/note.txt"
fi
echo "ANSWER_FROM_$role"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

# make_mode <dir> <id> <extra_stage_yaml_lines>
make_mode() {
  mkdir -p "$1/core/modes" "$1/core/prompts"
  cp "$SPEC" "$1/spec.md"
  {
    echo "id: $2"
    echo 'version: "1"'
    echo "stages:"
    echo "  - role: run"
    echo "    model_ref: fixture-model"
    echo "$3"
    echo "    max_attempts: 1"
    echo "on_fail: halt"
  } >"$1/core/modes/$2.yaml"
}

# ── case 1: the multi-stage runtime injects the template into the spec ──────
INJECT_DIR="$TMPDIR/inject"
make_mode "$INJECT_DIR" "inject-fixture" "    prompt_template: pt_fixture_hello"
printf 'UNIQUE_PROMPT_BODY_TOKEN\nDo the hello work.\n' \
  >"$INJECT_DIR/core/prompts/pt_fixture_hello.md"
rc=0
INJECT_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" inject-fixture "$INJECT_DIR/spec.md" inject-test \
    --workdir "$INJECT_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$INJECT_DIR/spec-handed.md" ] \
  && grep -qF "## Stage prompt (prompt_template: pt_fixture_hello)" "$INJECT_DIR/spec-handed.md" \
  && grep -qF "UNIQUE_PROMPT_BODY_TOKEN" "$INJECT_DIR/spec-handed.md"; then
  ok "the multi-stage runtime injects the template into the spec"
else
  not "the multi-stage runtime did not inject the template (rc=$rc): $INJECT_OUT"
fi

# ── case 2: declared and missing fails the stage ────────────────────────────
MISSING_DIR="$TMPDIR/missing"
make_mode "$MISSING_DIR" "missing-fixture" "    prompt_template: pt_fixture_missing"
rc=0
MISSING_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" missing-fixture "$MISSING_DIR/spec.md" missing-test \
    --workdir "$MISSING_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$MISSING_OUT" | grep -qF "PROMPT TEMPLATE NOT FOUND: pt_fixture_missing" \
  && [ ! -f "$MISSING_DIR/spec-handed.md" ]; then
  ok "a declared template that is missing fails the stage"
else
  not "the missing template was accepted (rc=$rc): $MISSING_OUT"
fi

# ── case 3: a stage that declares no template is not affected ───────────────
PLAIN_DIR="$TMPDIR/plain"
make_mode "$PLAIN_DIR" "plain-fixture" "    rate_limit_s: 0"
rc=0
PLAIN_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" plain-fixture "$PLAIN_DIR/spec.md" plain-test \
    --workdir "$PLAIN_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$PLAIN_DIR/spec-handed.md" ] \
  && ! grep -qF "## Stage prompt (prompt_template:" "$PLAIN_DIR/spec-handed.md"; then
  ok "a stage that declares no prompt_template is not affected"
else
  not "a stage without prompt_template was affected (rc=$rc): $PLAIN_OUT"
fi

# ── case 4: the prompt sits before prev_stage in the composed spec ──────────
ORDER_DIR="$TMPDIR/order"
mkdir -p "$ORDER_DIR/core/modes" "$ORDER_DIR/core/prompts"
cp "$SPEC" "$ORDER_DIR/spec.md"
printf 'ORDER_PROMPT_BODY\n' >"$ORDER_DIR/core/prompts/pt_fixture_order.md"
cat >"$ORDER_DIR/core/modes/order-fixture.yaml" <<'EOF'
id: order-fixture
version: "1"
stages:
  - role: unlock
    model_ref: fixture-model
    artifacts: unlock/
    max_attempts: 1
  - role: plan
    model_ref: fixture-model
    input: prev_stage
    prompt_template: pt_fixture_order
    artifacts: plan/
    max_attempts: 1
on_fail: halt
EOF
rc=0
ORDER_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" order-fixture "$ORDER_DIR/spec.md" order-test \
    --workdir "$ORDER_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ORDER_DIR/spec-plan.md" ]; then
  prompt_line="$(grep -nF "## Stage prompt (prompt_template: pt_fixture_order)" "$ORDER_DIR/spec-plan.md" | head -1 | cut -d: -f1)"
  prev_line="$(grep -nF "## Previous stage output (input: prev_stage)" "$ORDER_DIR/spec-plan.md" | head -1 | cut -d: -f1)"
  gt_line="$(grep -nF "## GROUND TRUTH" "$ORDER_DIR/spec-plan.md" | head -1 | cut -d: -f1)"
  if [ -n "$prompt_line" ] && [ -n "$prev_line" ] \
    && [ "$prompt_line" -lt "$prev_line" ] \
    && { [ -z "$gt_line" ] || [ "$prompt_line" -lt "$gt_line" ]; } \
    && grep -qF "ORDER_PROMPT_BODY" "$ORDER_DIR/spec-plan.md"; then
    ok "the template sits after the base spec and before prev_stage / ground truth"
  else
    not "the template was not in front of prev_stage (prompt=$prompt_line prev=$prev_line gt=$gt_line)"
  fi
else
  not "the order fixture did not run (rc=$rc): $ORDER_OUT"
fi

# ── case 5: the single-stage runtime keeps the same promise ─────────────────
SINGLE_DIR="$TMPDIR/single"
make_mode "$SINGLE_DIR" "single-inject-fixture" "    prompt_template: pt_fixture_hello"
printf 'UNIQUE_PROMPT_BODY_TOKEN\nDo the hello work.\n' \
  >"$SINGLE_DIR/core/prompts/pt_fixture_hello.md"
rc=0
SINGLE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-inject-fixture "$SINGLE_DIR/spec.md" single-inject-test \
    --workdir "$SINGLE_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$SINGLE_DIR/spec-handed.md" ] \
  && grep -qF "## Stage prompt (prompt_template: pt_fixture_hello)" "$SINGLE_DIR/spec-handed.md" \
  && grep -qF "UNIQUE_PROMPT_BODY_TOKEN" "$SINGLE_DIR/spec-handed.md"; then
  ok "the single-stage runtime injects the template into the spec"
else
  not "the single-stage runtime did not inject the template (rc=$rc): $SINGLE_OUT"
fi

SINGLE_MISS_DIR="$TMPDIR/single-missing"
make_mode "$SINGLE_MISS_DIR" "single-missing-fixture" "    prompt_template: pt_fixture_missing"
rc=0
SINGLE_MISS_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-missing-fixture "$SINGLE_MISS_DIR/spec.md" single-missing-test \
    --workdir "$SINGLE_MISS_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$SINGLE_MISS_OUT" | grep -qF "PROMPT TEMPLATE NOT FOUND: pt_fixture_missing" \
  && [ ! -f "$SINGLE_MISS_DIR/spec-handed.md" ]; then
  ok "the single-stage runtime fails a missing template"
else
  not "the single-stage runtime accepted the missing template (rc=$rc): $SINGLE_MISS_OUT"
fi

SINGLE_PLAIN_DIR="$TMPDIR/single-plain"
make_mode "$SINGLE_PLAIN_DIR" "single-plain-fixture" "    rate_limit_s: 0"
rc=0
SINGLE_PLAIN_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-plain-fixture "$SINGLE_PLAIN_DIR/spec.md" single-plain-test \
    --workdir "$SINGLE_PLAIN_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$SINGLE_PLAIN_DIR/spec-handed.md" ] \
  && ! grep -qF "## Stage prompt (prompt_template:" "$SINGLE_PLAIN_DIR/spec-handed.md"; then
  ok "the single-stage runtime leaves a stage without prompt_template alone"
else
  not "the single-stage runtime affected a stage without prompt_template (rc=$rc): $SINGLE_PLAIN_OUT"
fi

# ── case 6: the loader refuses an empty or non-string prompt_template ───────
loader_rejects() {
  local value="$1" dir="$2"
  mkdir -p "$dir/core/modes"
  {
    echo "id: bad-prompt-fixture"
    echo 'version: "1"'
    echo "stages:"
    echo "  - role: run"
    echo "    model_ref: fixture-model"
    echo "    prompt_template: $value"
    echo "    max_attempts: 1"
    echo "on_fail: halt"
  } >"$dir/core/modes/bad-prompt-fixture.yaml"
  local rc=0
  python3 "$LOADER" validate "$dir/core/modes/bad-prompt-fixture.yaml" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

if loader_rejects '""' "$TMPDIR/bad-empty"; then
  ok "the loader refuses an empty prompt_template"
else
  not "the loader accepted an empty prompt_template"
fi

if loader_rejects "1" "$TMPDIR/bad-number"; then
  ok "the loader refuses a prompt_template that is not a string"
else
  not "the loader accepted a prompt_template that is not a string"
fi

VALID_DIR="$TMPDIR/valid-loader"
mkdir -p "$VALID_DIR/core/modes"
cat >"$VALID_DIR/core/modes/ok-prompt-fixture.yaml" <<'EOF'
id: ok-prompt-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    prompt_template: a_name_the_loader_cannot_see
    max_attempts: 1
on_fail: halt
EOF
if python3 "$LOADER" validate "$VALID_DIR/core/modes/ok-prompt-fixture.yaml" >/dev/null 2>&1; then
  ok "the loader accepts a non-empty string without checking the file"
else
  not "the loader refused a valid prompt_template string"
fi

# ── case 7: resolve order — workdir, then root; .md and slash are relative ──
# shellcheck source=../bin/lib-oracfit-prompt-template.sh
source "$PT_LIB"
RESOLVE_WD="$TMPDIR/resolve-wd"
mkdir -p "$RESOLVE_WD/core/prompts" "$RESOLVE_WD/prompts"
printf 'FROM_WORKDIR\n' >"$RESOLVE_WD/core/prompts/vision_product_fields.md"
printf 'RELATIVE_MD\n' >"$RESOLVE_WD/custom.md"
printf 'RELATIVE_SLASH\n' >"$RESOLVE_WD/prompts/nested.md"

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_prompt_template_resolve vision_product_fields
)"
if [ "$found" = "$RESOLVE_WD/core/prompts/vision_product_fields.md" ]; then
  ok "a bare name prefers the workdir file over ORACFIT_ROOT"
else
  not "workdir overlay lost (found=${found:-empty})"
fi

mkdir -p "$TMPDIR/empty-wd"
found="$(
  ORACFIT_WORKDIR="$TMPDIR/empty-wd" ORACFIT_ROOT="$ROOT" \
    oracfit_prompt_template_resolve vision_product_fields
)"
if [ "$found" = "$ROOT/core/prompts/vision_product_fields.md" ]; then
  ok "a bare name falls back to ORACFIT_ROOT/core/prompts/"
else
  not "root fallback lost (found=${found:-empty})"
fi

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_prompt_template_resolve custom.md
)"
if [ "$found" = "$RESOLVE_WD/custom.md" ]; then
  ok "a .md value is a path relative to the workdir"
else
  not "the .md path was not workdir-relative (found=${found:-empty})"
fi

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_prompt_template_resolve prompts/nested.md
)"
if [ "$found" = "$RESOLVE_WD/prompts/nested.md" ]; then
  ok "a value with a slash is a path relative to the workdir"
else
  not "the slash path was not workdir-relative (found=${found:-empty})"
fi

if ORACFIT_WORKDIR="$TMPDIR/empty-wd" ORACFIT_ROOT="$ROOT" \
     oracfit_prompt_template_resolve pt_fixture_missing >/dev/null 2>&1; then
  not "resolve returned success for a name that does not exist"
else
  ok "resolve fails when the file does not exist"
fi

echo "test-prompt-template: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
