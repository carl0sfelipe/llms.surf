#!/bin/bash
# test-json-schema.sh — a schema a stage declares must be handed to the model.
#
# `json_schema: NAME` used to be a promise nobody kept: the loader accepted
# the field, four shipped stages named a file, and neither dispatcher read it.
# A stage that declared a schema received the same spec as a stage that did not.
#
# This suite is the mechanism that keeps the promise:
#   - both runtimes inject the file into the spec the runner receives
#     (the runtime hands the schema to the model)
#   - a declared schema that is missing fails the stage
#     (`JSON SCHEMA NOT FOUND`) before any model is called
#   - a stage that declares no schema is not affected
#   - the loader refuses an empty or non-string value
#   - the runtime does not validate the model's answer against the schema
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# A parent dispatch exports DISPATCH_MODEL_REF; the single-stage runtime
# would then demand that id in the registry instead of the fixture model.
unset DISPATCH_MODEL_REF
STAGES="$ROOT/bin/dispatch-stages.sh"
MODE="$ROOT/bin/dispatch-mode.sh"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
JS_LIB="$ROOT/bin/lib-oracfit-json-schema.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-json-schema.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# JSON schema fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
test -f .json-schema-marker

## Oráculo
- comando: test -f marker.txt
- exit esperado: 0

## Barra
- nome: json schema fixture

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
  mkdir -p "$1/core/modes" "$1/core/schemas" "$1/core/prompts"
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

attempt_log_has() {
  local dir="$1" needle="$2"
  local log=""
  log="$(find "$dir" -name 'oracle-attempt-1.log' | head -1)"
  [ -n "$log" ] && grep -qF "$needle" "$log"
}

# ── case 1: the runtime hands the schema to the model ───────────────────────
INJECT_DIR="$TMPDIR/inject"
make_mode "$INJECT_DIR" "inject-fixture" "    json_schema: js_fixture_hello"
printf '{"title":"UNIQUE_SCHEMA_BODY_TOKEN","type":"object"}\n' \
  >"$INJECT_DIR/core/schemas/js_fixture_hello.json"
rc=0
INJECT_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" inject-fixture "$INJECT_DIR/spec.md" inject-test \
    --workdir "$INJECT_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$INJECT_DIR/spec-handed.md" ] \
  && grep -qF "## Stage answer schema (json_schema: js_fixture_hello)" "$INJECT_DIR/spec-handed.md" \
  && grep -qF "UNIQUE_SCHEMA_BODY_TOKEN" "$INJECT_DIR/spec-handed.md"; then
  ok "the runtime hands the schema to the model"
else
  not "the runtime did not hand the schema to the model (rc=$rc): $INJECT_OUT"
fi

# ── case 2: declared and missing fails the stage ────────────────────────────
MISSING_DIR="$TMPDIR/missing"
make_mode "$MISSING_DIR" "missing-fixture" "    json_schema: js_fixture_missing"
rc=0
MISSING_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" missing-fixture "$MISSING_DIR/spec.md" missing-test \
    --workdir "$MISSING_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$MISSING_OUT" | grep -qF "JSON SCHEMA NOT FOUND: js_fixture_missing" \
  && attempt_log_has "$MISSING_DIR" "JSON SCHEMA NOT FOUND: js_fixture_missing" \
  && [ ! -f "$MISSING_DIR/spec-handed.md" ]; then
  ok "a declared and missing schema fails the stage"
else
  not "the missing schema was accepted (rc=$rc): $MISSING_OUT"
fi

# ── case 3: a stage that declares no schema is not affected ─────────────────
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
  && ! grep -qF "## Stage answer schema (json_schema:" "$PLAIN_DIR/spec-handed.md"; then
  ok "a stage that declares no schema is not affected"
else
  not "a stage without json_schema was affected (rc=$rc): $PLAIN_OUT"
fi

# ── case 4: the schema sits after the prompt template ───────────────────────
ORDER_DIR="$TMPDIR/order"
mkdir -p "$ORDER_DIR/core/modes" "$ORDER_DIR/core/prompts" "$ORDER_DIR/core/schemas"
cp "$SPEC" "$ORDER_DIR/spec.md"
printf 'ORDER_PROMPT_BODY\n' >"$ORDER_DIR/core/prompts/pt_fixture_order.md"
printf '{"title":"ORDER_SCHEMA_BODY","type":"object"}\n' \
  >"$ORDER_DIR/core/schemas/js_fixture_order.json"
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
    json_schema: js_fixture_order
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
  schema_line="$(grep -nF "## Stage answer schema (json_schema: js_fixture_order)" "$ORDER_DIR/spec-plan.md" | head -1 | cut -d: -f1)"
  gt_line="$(grep -nF "## GROUND TRUTH" "$ORDER_DIR/spec-plan.md" | head -1 | cut -d: -f1)"
  if [ -n "$prompt_line" ] && [ -n "$schema_line" ] \
    && [ "$prompt_line" -lt "$schema_line" ] \
    && { [ -z "$gt_line" ] || [ "$schema_line" -lt "$gt_line" ]; } \
    && grep -qF "ORDER_SCHEMA_BODY" "$ORDER_DIR/spec-plan.md"; then
    ok "the schema sits after the prompt template"
  else
    not "the schema was not after the prompt (prompt=$prompt_line schema=$schema_line gt=$gt_line)"
  fi
else
  not "the order fixture did not run (rc=$rc): $ORDER_OUT"
fi

# ── case 5: the single-stage runtime keeps the same promise ─────────────────
SINGLE_DIR="$TMPDIR/single"
make_mode "$SINGLE_DIR" "single-inject-fixture" "    json_schema: js_fixture_hello"
printf '{"title":"UNIQUE_SCHEMA_BODY_TOKEN","type":"object"}\n' \
  >"$SINGLE_DIR/core/schemas/js_fixture_hello.json"
inject_rc=0
SINGLE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-inject-fixture "$SINGLE_DIR/spec.md" single-inject-test \
    --workdir "$SINGLE_DIR" 2>&1
)" || inject_rc=$?
SINGLE_MISS_DIR="$TMPDIR/single-missing"
make_mode "$SINGLE_MISS_DIR" "single-missing-fixture" "    json_schema: js_fixture_missing"
miss_rc=0
SINGLE_MISS_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-missing-fixture "$SINGLE_MISS_DIR/spec.md" single-missing-test \
    --workdir "$SINGLE_MISS_DIR" 2>&1
)" || miss_rc=$?
if [ "$inject_rc" -eq 0 ] \
  && [ -f "$SINGLE_DIR/spec-handed.md" ] \
  && grep -qF "## Stage answer schema (json_schema: js_fixture_hello)" "$SINGLE_DIR/spec-handed.md" \
  && grep -qF "UNIQUE_SCHEMA_BODY_TOKEN" "$SINGLE_DIR/spec-handed.md" \
  && [ "$miss_rc" -ne 0 ] \
  && printf '%s\n' "$SINGLE_MISS_OUT" | grep -qF "JSON SCHEMA NOT FOUND: js_fixture_missing" \
  && attempt_log_has "$SINGLE_MISS_DIR" "JSON SCHEMA NOT FOUND: js_fixture_missing" \
  && [ ! -f "$SINGLE_MISS_DIR/spec-handed.md" ]; then
  ok "the single-stage runtime keeps the same promise"
else
  not "the single-stage runtime broke the promise (inject_rc=$inject_rc miss_rc=$miss_rc): $SINGLE_OUT / $SINGLE_MISS_OUT"
fi

# ── case 6: the loader refuses an empty or non-string json_schema ───────────
loader_rejects() {
  local value="$1" dir="$2"
  mkdir -p "$dir/core/modes"
  {
    echo "id: bad-schema-fixture"
    echo 'version: "1"'
    echo "stages:"
    echo "  - role: run"
    echo "    model_ref: fixture-model"
    echo "    json_schema: $value"
    echo "    max_attempts: 1"
    echo "on_fail: halt"
  } >"$dir/core/modes/bad-schema-fixture.yaml"
  local rc=0
  python3 "$LOADER" validate "$dir/core/modes/bad-schema-fixture.yaml" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

if loader_rejects '""' "$TMPDIR/bad-empty"; then
  ok "the loader refuses an empty or non-string json_schema"
else
  not "the loader accepted an empty json_schema"
fi

if loader_rejects "1" "$TMPDIR/bad-number"; then
  ok "the loader refuses a json_schema that is not a string"
else
  not "the loader accepted a json_schema that is not a string"
fi

VALID_DIR="$TMPDIR/valid-loader"
mkdir -p "$VALID_DIR/core/modes"
cat >"$VALID_DIR/core/modes/ok-schema-fixture.yaml" <<'EOF'
id: ok-schema-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    json_schema: a_name_the_loader_cannot_see
    max_attempts: 1
on_fail: halt
EOF
if python3 "$LOADER" validate "$VALID_DIR/core/modes/ok-schema-fixture.yaml" >/dev/null 2>&1; then
  ok "the loader accepts a non-empty string without checking the file"
else
  not "the loader refused a valid json_schema string"
fi

# ── case 7: resolve order — workdir, then root; .json and slash are relative ─
# shellcheck source=../bin/lib-oracfit-json-schema.sh
source "$JS_LIB"
RESOLVE_WD="$TMPDIR/resolve-wd"
mkdir -p "$RESOLVE_WD/core/schemas" "$RESOLVE_WD/schemas"
printf '{"from":"workdir"}\n' >"$RESOLVE_WD/core/schemas/product_from_photo.json"
printf '{"from":"relative_json"}\n' >"$RESOLVE_WD/custom.json"
printf '{"from":"relative_slash"}\n' >"$RESOLVE_WD/schemas/nested.json"

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_json_schema_resolve product_from_photo
)"
if [ "$found" = "$RESOLVE_WD/core/schemas/product_from_photo.json" ]; then
  ok "a bare name prefers the workdir file over ORACFIT_ROOT"
else
  not "workdir overlay lost (found=${found:-empty})"
fi

mkdir -p "$TMPDIR/empty-wd"
found="$(
  ORACFIT_WORKDIR="$TMPDIR/empty-wd" ORACFIT_ROOT="$ROOT" \
    oracfit_json_schema_resolve product_from_photo
)"
if [ "$found" = "$ROOT/core/schemas/product_from_photo.json" ]; then
  ok "the resolve order is workdir, then root"
else
  not "root fallback lost (found=${found:-empty})"
fi

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_json_schema_resolve custom.json
)"
if [ "$found" = "$RESOLVE_WD/custom.json" ]; then
  ok "a .json value is a path relative to the workdir"
else
  not "the .json path was not workdir-relative (found=${found:-empty})"
fi

found="$(
  ORACFIT_WORKDIR="$RESOLVE_WD" ORACFIT_ROOT="$ROOT" \
    oracfit_json_schema_resolve schemas/nested.json
)"
if [ "$found" = "$RESOLVE_WD/schemas/nested.json" ]; then
  ok "a value with a slash is a path relative to the workdir"
else
  not "the slash path was not workdir-relative (found=${found:-empty})"
fi

if ORACFIT_WORKDIR="$TMPDIR/empty-wd" ORACFIT_ROOT="$ROOT" \
     oracfit_json_schema_resolve js_fixture_missing >/dev/null 2>&1; then
  not "resolve returned success for a name that does not exist"
else
  ok "resolve fails when the file does not exist"
fi

# ── case 8: the four shipped schemas exist and match their prompts ──────────
SHIPPED_RC=0
SHIPPED_MSG="$(python3 - "$ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
schemas = root / "core" / "schemas"
names = (
    "product_from_photo",
    "store_product_catalog",
    "storefront_visual_findings",
    "storefront_visual_report",
)

def load(name):
    path = schemas / f"{name}.json"
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid JSON in {path}: {exc}") from exc

product = load("product_from_photo")
required = set(product.get("required") or [])
if "photo" not in required or "notes" not in required:
    raise SystemExit("product_from_photo must require photo and notes")

catalog = load("store_product_catalog")
if catalog.get("type") != "array":
    raise SystemExit("store_product_catalog must be an array")

findings = load("storefront_visual_findings")
required = set(findings.get("required") or [])
if "page_guess" not in required or "overall_severity" not in required:
    raise SystemExit("storefront_visual_findings must require page_guess and overall_severity")

report = load("storefront_visual_report")
required = set(report.get("required") or [])
if "critical_count" not in required or "top_issues" not in required:
    raise SystemExit("storefront_visual_report must require critical_count and top_issues")

for name in names:
    load(name)
print("ok")
PY
)" || SHIPPED_RC=$?
if [ "$SHIPPED_RC" -eq 0 ]; then
  ok "the four shipped schemas exist and match their prompts"
else
  not "the four shipped schemas do not match their prompts: $SHIPPED_MSG"
fi

echo "test-json-schema: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
