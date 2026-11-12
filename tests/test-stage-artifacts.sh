#!/bin/bash
# test-stage-artifacts.sh — a stage that declares `artifacts:` must leave
# something there.
#
# The field was accepted by the loader, handed to the model in the spec and
# read by nobody: a stage could declare `artifacts: plan/`, write nothing and
# pass. The stages that follow (input: prev_stage) then read an empty
# hand-off and the run said "pass". A declared artifact is a promise — this
# suite is the mechanism that keeps it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGES="$ROOT/bin/dispatch-stages.sh"
MODE="$ROOT/bin/dispatch-mode.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-stage-artifacts.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Stage artifacts fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
test -f .stage-artifacts-marker

## Oráculo
- comando: test -f marker.txt
- exit esperado: 0

## Barra
- nome: stage artifacts fixture

NUNCA use declare const como workaround.
EOF
# english-ok-end

# The fake runner: it writes into the artifacts dir only when told to, and it
# records the spec it was handed.
FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
role="${ORACFIT_STAGE_ROLE:-unknown}"
if [ -n "${2:-}" ]; then
  cp "$2" "$ORACFIT_WORKDIR/spec-$role.md"
fi
printf 'work done\n' >"$ORACFIT_WORKDIR/marker.txt"
if [ "${FAKE_WRITE_ARTIFACT:-1}" = "1" ] && [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  printf 'artifact written by %s\n' "$role" >"$ORACFIT_STAGE_ARTIFACTS/note.txt"
fi
echo "ANSWER_FROM_$role"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

# ── case 1: a stage that writes nothing fails ────────────────────────────────
EMPTY_DIR="$TMPDIR/empty-case"
mkdir -p "$EMPTY_DIR/core/modes"
cp "$SPEC" "$EMPTY_DIR/spec.md"
cat >"$EMPTY_DIR/core/modes/empty-artifacts-fixture.yaml" <<'EOF'
id: empty-artifacts-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    artifacts: proof/
    max_attempts: 1
on_fail: halt
EOF
rc=0
EMPTY_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" FAKE_WRITE_ARTIFACT=0 \
    "$STAGES" empty-artifacts-fixture "$EMPTY_DIR/spec.md" empty-artifacts-test \
    --workdir "$EMPTY_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$EMPTY_OUT" | grep -qF "STAGE ARTIFACTS EMPTY"; then
  ok "a stage that declares artifacts and writes nothing fails the stage"
else
  not "the empty artifacts dir was accepted (rc=$rc): $EMPTY_OUT"
fi

# ── case 2: a stage that writes something passes ─────────────────────────────
WRITE_DIR="$TMPDIR/write-case"
mkdir -p "$WRITE_DIR/core/modes"
cp "$SPEC" "$WRITE_DIR/spec.md"
cp "$EMPTY_DIR/core/modes/empty-artifacts-fixture.yaml" \
   "$WRITE_DIR/core/modes/write-artifacts-fixture.yaml"
python3 - "$WRITE_DIR/core/modes/write-artifacts-fixture.yaml" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
p.write_text(p.read_text()
              .replace("id: empty-artifacts-fixture", "id: write-artifacts-fixture")
              .replace("artifacts: proof/", "artifacts: proof/"))
PY
rc=0
WRITE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" write-artifacts-fixture "$WRITE_DIR/spec.md" write-artifacts-test \
    --workdir "$WRITE_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "a stage that leaves a non-empty artifact passes"
else
  not "the written artifact did not satisfy the stage (rc=$rc): $WRITE_OUT"
fi

# ── case 3: a stage without artifacts is not gated ───────────────────────────
NOGATE_DIR="$TMPDIR/nogate-case"
mkdir -p "$NOGATE_DIR/core/modes"
cp "$SPEC" "$NOGATE_DIR/spec.md"
cat >"$NOGATE_DIR/core/modes/nogate-fixture.yaml" <<'EOF'
id: nogate-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    max_attempts: 1
on_fail: halt
EOF
rc=0
NOGATE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" FAKE_WRITE_ARTIFACT=0 \
    "$STAGES" nogate-fixture "$NOGATE_DIR/spec.md" nogate-test \
    --workdir "$NOGATE_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "a stage that declares no artifacts is not gated by an empty dir"
else
  not "a stage without artifacts was gated (rc=$rc): $NOGATE_OUT"
fi

# ── case 4: the model is told where the artifacts dir is ─────────────────────
if [ -f "$WRITE_DIR/spec-run.md" ] \
  && grep -qF "artifacts_dir:" "$WRITE_DIR/spec-run.md" \
  && grep -qF "MUST leave a non-empty file" "$WRITE_DIR/spec-run.md"; then
  ok "the composed spec tells the model where its artifacts dir is"
else
  not "the model was not told where to write its artifact: $WRITE_OUT"
fi

# ── case 5: the retry: the artifact arrives on the second attempt ───────────
RETRY_DIR="$TMPDIR/retry-case"
mkdir -p "$RETRY_DIR/core/modes"
cp "$SPEC" "$RETRY_DIR/spec.md"
RETRY_RUNNER="$RETRY_DIR/retry-runner.sh"
cat >"$RETRY_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
count_file="$ORACFIT_WORKDIR/attempt-count"
count=0
[ -f "$count_file" ] && count="$(cat "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
printf 'work done\n' >"$ORACFIT_WORKDIR/marker.txt"
if [ "$count" -ge 2 ] && [ -n "${ORACFIT_STAGE_ARTIFACTS:-}" ]; then
  mkdir -p "$ORACFIT_STAGE_ARTIFACTS"
  printf 'artifact on attempt %s\n' "$count" >"$ORACFIT_STAGE_ARTIFACTS/note.txt"
fi
exit 0
EOF
chmod +x "$RETRY_RUNNER"
cat >"$RETRY_DIR/core/modes/retry-artifacts-fixture.yaml" <<'EOF'
id: retry-artifacts-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    artifacts: proof/
    max_attempts: 3
on_fail: halt
EOF
rc=0
RETRY_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$RETRY_RUNNER" \
    "$STAGES" retry-artifacts-fixture "$RETRY_DIR/spec.md" retry-artifacts-test \
    --workdir "$RETRY_DIR" 2>&1
)" || rc=$?
attempts="$(cat "$RETRY_DIR/attempt-count" 2>/dev/null || printf '0')"
if [ "$rc" -eq 0 ] && [ "$attempts" -eq 2 ]; then
  ok "the stage retries until the artifact exists (2 attempts)"
else
  not "the stage did not retry for the missing artifact (rc=$rc attempts=$attempts): $RETRY_OUT"
fi

# ── case 6: the single-stage runtime keeps the same promise ──────────────────
SINGLE_DIR="$TMPDIR/single-case"
mkdir -p "$SINGLE_DIR/core/modes"
cp "$SPEC" "$SINGLE_DIR/spec.md"
cat >"$SINGLE_DIR/core/modes/single-artifacts-fixture.yaml" <<'EOF'
id: single-artifacts-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    artifacts: proof/
on_fail: halt
EOF
rc=0
SINGLE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" FAKE_WRITE_ARTIFACT=0 \
    "$MODE" single-artifacts-fixture "$SINGLE_DIR/spec.md" single-artifacts-test \
    --workdir "$SINGLE_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$SINGLE_OUT" | grep -qF "STAGE ARTIFACTS EMPTY"; then
  ok "the single-stage runtime keeps the same promise"
else
  not "the single-stage runtime accepted the empty artifacts dir (rc=$rc): $SINGLE_OUT"
fi

SINGLE_OK_DIR="$TMPDIR/single-ok-case"
mkdir -p "$SINGLE_OK_DIR/core/modes"
cp "$SPEC" "$SINGLE_OK_DIR/spec.md"
cp "$SINGLE_DIR/core/modes/single-artifacts-fixture.yaml" \
   "$SINGLE_OK_DIR/core/modes/single-artifacts-fixture.yaml"
rc=0
SINGLE_OK_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-artifacts-fixture "$SINGLE_OK_DIR/spec.md" single-artifacts-ok \
    --workdir "$SINGLE_OK_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ]; then
  ok "the single-stage runtime passes when the artifact exists"
else
  not "the single-stage runtime failed with a written artifact (rc=$rc): $SINGLE_OK_OUT"
fi

echo "test-stage-artifacts: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
