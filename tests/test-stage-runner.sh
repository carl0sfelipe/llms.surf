#!/bin/bash
# Focused tests for ADR-0004 stage schema/runner behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
STAGES="$ROOT/bin/dispatch-stages.sh"
STUB="$ROOT/adapters/stub/runner.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-stage-runner.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
cat >"$SPEC" <<'EOF'
# Stage runner fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
python3 -c "raise SystemExit(0)"

## Oráculo
- comando: test -f .never-produced-by-stage-fixture
- exit esperado: 0

## Barra
- nome: stage runner fixture

NUNCA use declare const como workaround.
EOF

MODE_DIR="$TMPDIR/core/modes"
mkdir -p "$MODE_DIR"

cat >"$MODE_DIR/schema-fixture.yaml" <<'EOF'
id: schema-fixture
version: "1"
stages:
  - role: render
    command: "true"
    preflight: "true"
    stage_oracle: "true"
    freshness_targets:
      - evidence/desktop.png
    max_attempts: 1
run_attempt_budget: 2
on_fail: halt
EOF
if python3 "$LOADER" validate "$MODE_DIR/schema-fixture.yaml" >/dev/null; then
  ok "new stage keys and global budget validate"
else
  not "valid new stage schema was rejected"
fi

cat >"$TMPDIR/bad-schema.yaml" <<'EOF'
id: bad-schema
version: "1"
stages:
  - role: run
    stage_oracle: true
run_attempt_budget: 0
EOF
rc=0
python3 "$LOADER" validate "$TMPDIR/bad-schema.yaml" >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 2 ]; then
  ok "invalid stage oracle/budget is rejected"
else
  not "invalid stage oracle/budget should exit 2 (rc=$rc)"
fi

echo "evidence" >"$TMPDIR/stale.png"
source "$ROOT/bin/lib-oracfit-gauntlet.sh"
export ORACFIT_WORKDIR="$TMPDIR"
export ORACFIT_STAGE_STARTED_AT="$(python3 -c 'import time; print(time.time() + 60)')"
if oracfit_visual_freshness_gate evidence/stale.png >/dev/null 2>&1; then
  not "stale visual target was accepted"
else
  ok "visual freshness rejects an artifact older than attempt start"
fi
: >"$TMPDIR/empty.png"
export ORACFIT_STAGE_STARTED_AT="$(python3 -c 'import time; print(time.time())')"
if oracfit_visual_freshness_gate empty.png >/dev/null 2>&1; then
  not "empty visual target was accepted"
else
  ok "visual freshness rejects an empty artifact"
fi
printf 'fresh evidence\n' >"$TMPDIR/fresh.png"
touch "$TMPDIR/fresh.png"
if oracfit_visual_freshness_gate fresh.png >/dev/null 2>&1; then
  ok "visual freshness accepts a non-empty current artifact"
else
  not "current non-empty visual target was rejected"
fi
unset ORACFIT_STAGE_STARTED_AT

PREFLIGHT_DIR="$TMPDIR/preflight case"
mkdir -p "$PREFLIGHT_DIR/core/modes"
cp "$SPEC" "$PREFLIGHT_DIR/spec.md"
cat >"$PREFLIGHT_DIR/core/modes/preflight-fixture.yaml" <<'EOF'
id: preflight-fixture
version: "1"
stages:
  - role: run
    preflight: "test -f \"$ORACFIT_WORKDIR/required-service\""
    command: "touch \"$ORACFIT_WORKDIR/attempt-ran\""
    max_attempts: 1
on_fail: halt
EOF
rc=0
preflight_out="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
    "$STAGES" preflight-fixture "$PREFLIGHT_DIR/spec.md" preflight-test \
    --workdir "$PREFLIGHT_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && printf '%s\n' "$preflight_out" | grep -qF "preflight failed" \
  && [ ! -e "$PREFLIGHT_DIR/attempt-ran" ]; then
  ok "stage preflight failure stops attempts with actionable error"
else
  not "stage preflight should stop before command (rc=$rc): $preflight_out"
fi

ORDER_DIR="$TMPDIR/order-case"
mkdir -p "$ORDER_DIR/core/modes"
cp "$SPEC" "$ORDER_DIR/spec.md"
python3 - "$ORDER_DIR/spec.md" <<'PY'
from pathlib import Path
path = Path(__import__("sys").argv[1])
path.write_text(path.read_text().replace(".never-produced-by-stage-fixture", "ordinary-marker"))
PY
cat >"$ORDER_DIR/core/modes/order-fixture.yaml" <<'EOF'
id: order-fixture
version: "1"
stages:
  - role: export
    command: "touch \"$ORACFIT_WORKDIR/stage-marker\""
    stage_oracle: "test -f \"$ORACFIT_WORKDIR/stage-marker\" && touch \"$ORACFIT_WORKDIR/ordinary-marker\""
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
rc=0
ORDER_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
    "$STAGES" order-fixture "$ORDER_DIR/spec.md" ordering-test \
    --workdir "$ORDER_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] && [ -f "$ORDER_DIR/ordinary-marker" ]; then
  ok "stage oracle runs before the ordinary spec oracle"
else
  not "stage oracle ordering failed (rc=$rc): $ORDER_OUT"
fi

FAIL_DIR="$TMPDIR/runner-failure-case"
mkdir -p "$FAIL_DIR/core/modes"
cp "$SPEC" "$FAIL_DIR/spec.md"
FAIL_RUNNER="$FAIL_DIR/failing-runner.sh"
cat >"$FAIL_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
count_file="$ORACFIT_WORKDIR/failure-attempt-count"
count=0
[ -f "$count_file" ] && count="$(cat "$count_file")"
printf '%s\n' "$((count + 1))" >"$count_file"
echo "simulated runner failure"
exit 7
EOF
chmod +x "$FAIL_RUNNER"
cat >"$FAIL_DIR/core/modes/runner-failure-fixture.yaml" <<'EOF'
id: runner-failure-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    stage_oracle: "touch \"$ORACFIT_WORKDIR/oracle-ran\""
    oracle: true
    max_attempts: 2
on_fail: halt
EOF
rc=0
FAIL_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAIL_RUNNER" \
    "$STAGES" runner-failure-fixture "$FAIL_DIR/spec.md" runner-failure-test \
    --workdir "$FAIL_DIR" 2>&1
)" || rc=$?
failure_count="$(cat "$FAIL_DIR/failure-attempt-count" 2>/dev/null || printf '0')"
if [ "$rc" -ne 0 ] \
  && [ "$failure_count" -eq 2 ] \
  && [ ! -e "$FAIL_DIR/oracle-ran" ] \
  && printf '%s\n' "$FAIL_OUT" | grep -qF "STAGE COMMAND FAILED"; then
  ok "non-zero runner exit blocks custom/ordinary oracles and retries"
else
  not "runner failure false-green guard failed (rc=$rc count=$failure_count): $FAIL_OUT"
fi

BUDGET_DIR="$TMPDIR/budget-case"
mkdir -p "$BUDGET_DIR/core/modes"
cp "$SPEC" "$BUDGET_DIR/spec.md"
FAKE_RUNNER="$BUDGET_DIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
count_file="$ORACFIT_WORKDIR/run-attempt-count"
count=0
[ -f "$count_file" ] && count="$(cat "$count_file")"
printf '%s\n' "$((count + 1))" >"$count_file"
printf '%s\n' "${ORACFIT_SPEC_FILE:-}" >"$ORACFIT_WORKDIR/spec-env"
printf '%s\n' "${ORACFIT_STAGE_STARTED_AT:-}" >"$ORACFIT_WORKDIR/stage-start-env"
printf '%s\n' "${ORACFIT_NICHE:-}" >"$ORACFIT_WORKDIR/niche-env"
printf '%s\n' "${ORACFIT_NICHE_FOLDER:-}" >"$ORACFIT_WORKDIR/niche-folder-env"
exit 0
EOF
chmod +x "$FAKE_RUNNER"
cat >"$BUDGET_DIR/core/modes/budget-fixture.yaml" <<'EOF'
id: budget-fixture
version: "1"
stages:
  - role: run
    model_ref: fixture-model
    max_attempts: 1
  - role: vision_gate
    command: "true"
    stage_oracle: "exit 1"
    max_attempts: 1
    loop_target: run
run_attempt_budget: 2
gauntlet:
  enabled: true
  inject_feedback: false
  until_approved: true
  safety_ceiling: 5
on_fail: halt
EOF
rc=0
budget_out="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" budget-fixture "$BUDGET_DIR/spec.md" budget-test \
    --workdir "$BUDGET_DIR" 2>&1
)" || rc=$?
count="$(cat "$BUDGET_DIR/run-attempt-count" 2>/dev/null || printf '0')"
if [ "$rc" -ne 0 ] \
  && [ "$count" -eq 2 ] \
  && [ "$(cat "$BUDGET_DIR/spec-env")" = "$BUDGET_DIR/spec.md" ] \
  && [ -n "$(cat "$BUDGET_DIR/stage-start-env")" ] \
  && [ "$(cat "$BUDGET_DIR/niche-env")" = "budget-test" ] \
  && [ "$(cat "$BUDGET_DIR/niche-folder-env")" = "budget-test" ] \
  && printf '%s\n' "$budget_out" | grep -qF "global run-attempt budget exhausted"; then
  ok "budget counts run attempts across loop-backs and exports per-attempt context"
else
  not "global budget did not halt at two run attempts (rc=$rc count=$count): $budget_out"
fi

SANITIZED_DIR="$TMPDIR/sanitized-case"
mkdir -p "$SANITIZED_DIR/core/modes"
cp "$SPEC" "$SANITIZED_DIR/spec.md"
cp "$BUDGET_DIR/core/modes/budget-fixture.yaml" "$SANITIZED_DIR/core/modes/budget-fixture.yaml"
rc=0
SANITIZED_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" budget-fixture "$SANITIZED_DIR/spec.md" "Fancy Niche/2026!" \
    --workdir "$SANITIZED_DIR" 2>&1
)" || rc=$?
if [ "$rc" -ne 0 ] \
  && [ "$(cat "$SANITIZED_DIR/niche-env")" = "Fancy Niche/2026!" ] \
  && [ "$(cat "$SANITIZED_DIR/niche-folder-env")" = "fancy-niche2026" ]; then
  ok "sanitized niche folder matches content-factory behavior and preserves original niche"
else
  not "sanitized niche export mismatch (rc=$rc): $SANITIZED_OUT"
fi

CRITIC_DIR="$TMPDIR/critic-timeout-case"
mkdir -p "$CRITIC_DIR/core/modes"
cp "$SPEC" "$CRITIC_DIR/spec.md"
CRITIC_STUB="$CRITIC_DIR/critic-stub-runner.sh"
cat >"$CRITIC_STUB" <<'EOF'
#!/bin/bash
set -euo pipefail
if [ "$1" = "hung-critic-model" ]; then
  # Provider degradado: dispatch do critic nunca responde.
  sleep 1000
  exit 0
fi
count_file="$ORACFIT_WORKDIR/critic-case-attempts"
count=0
[ -f "$count_file" ] && count="$(cat "$count_file")"
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ "$count" -eq 1 ]; then
  echo "simulated builder failure on attempt 1"
  exit 9
fi
exit 0
EOF
chmod +x "$CRITIC_STUB"
cat >"$CRITIC_DIR/core/modes/critic-timeout-fixture.yaml" <<'EOF'
id: critic-timeout-fixture
version: "1"
stages:
  - role: run
    model_ref: builder-model
    stage_oracle: "true"
    max_attempts: 2
gauntlet:
  enabled: true
  inject_feedback: true
  critic_model_ref: hung-critic-model
on_fail: halt
EOF
rc=0
critic_t0="$(date +%s)"
CRITIC_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$CRITIC_STUB" ORACFIT_CRITIC_TIMEOUT=2 \
    "$STAGES" critic-timeout-fixture "$CRITIC_DIR/spec.md" critic-timeout-test \
    --workdir "$CRITIC_DIR" 2>&1
)" || rc=$?
critic_elapsed=$(( $(date +%s) - critic_t0 ))
critic_attempts="$(cat "$CRITIC_DIR/critic-case-attempts" 2>/dev/null || printf '0')"
if [ "$rc" -eq 0 ] \
  && [ "$critic_attempts" -eq 2 ] \
  && [ "$critic_elapsed" -lt 60 ] \
  && printf '%s\n' "$CRITIC_OUT" | grep -qiE "critic.*timeout"; then
  ok "hung critic dispatch is bounded by ORACFIT_CRITIC_TIMEOUT and fails open (attempt 2 ran in ${critic_elapsed}s)"
else
  not "critic timeout guard failed (rc=$rc attempts=$critic_attempts elapsed=${critic_elapsed}s): $CRITIC_OUT"
fi

KILL_DIR="$TMPDIR/kill-case"
mkdir -p "$KILL_DIR/core/modes"
cp "$SPEC" "$KILL_DIR/spec.md"
cat >"$KILL_DIR/core/modes/kill-fixture.yaml" <<'EOF'
id: kill-fixture
version: "1"
stages:
  - role: run
    command: "sleep 3"
    stage_oracle: "true"
    max_attempts: 1
on_fail: halt
EOF
kill_events="$KILL_DIR/.dispatch/logs/events.jsonl"
ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
  "$STAGES" kill-fixture "$KILL_DIR/spec.md" kill-test \
  --workdir "$KILL_DIR" >"$KILL_DIR/out.log" 2>&1 &
kill_pid=$!
# Espera o stage começar (stage_changed no events.jsonl) antes de matar,
# garantindo SIGTERM no meio do stage e não durante o preflight.
for _ in $(seq 1 50); do
  if [ -f "$kill_events" ] && grep -q '"type": "stage_changed"' "$kill_events" 2>/dev/null; then
    break
  fi
  sleep 0.2
done
sleep 1
kill -TERM "$kill_pid" 2>/dev/null || true
kill_rc=0
wait "$kill_pid" || kill_rc=$?
if [ "$kill_rc" -ne 0 ] \
  && grep '"type": "run_finished"' "$kill_events" 2>/dev/null | grep -q '"status": "fail"' \
  && grep -qF "status: fail" "$KILL_DIR/out.log"; then
  ok "SIGTERM mid-stage still emits run_finished status=fail and prints status: fail (rc=$kill_rc)"
else
  not "kill mid-stage missing run_finished/status (rc=$kill_rc): $(cat "$KILL_DIR/out.log" 2>/dev/null)"
fi

ATTEMPT_DIR="$TMPDIR/attempt-case"
mkdir -p "$ATTEMPT_DIR/core/modes"
cp "$SPEC" "$ATTEMPT_DIR/spec.md"
cat >"$ATTEMPT_DIR/core/modes/attempt-fixture.yaml" <<'EOF'
id: attempt-fixture
version: "1"
stages:
  - role: run
    command: >
      printf '%s\n' "${ORACFIT_STAGE_ATTEMPT:-}" >>"$ORACFIT_WORKDIR/attempt-log"
    stage_oracle: >
      test "$(tail -1 "$ORACFIT_WORKDIR/attempt-log")" = "2"
    max_attempts: 2
on_fail: halt
EOF
rc=0
ATTEMPT_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
    "$STAGES" attempt-fixture "$ATTEMPT_DIR/spec.md" attempt-test \
    --workdir "$ATTEMPT_DIR" 2>&1
)" || rc=$?
attempt_log="$(cat "$ATTEMPT_DIR/attempt-log" 2>/dev/null || true)"
if [ "$rc" -eq 0 ] \
  && printf '%s\n' "$attempt_log" | grep -qxF "1" \
  && printf '%s\n' "$attempt_log" | grep -qxF "2"; then
  ok "ORACFIT_STAGE_ATTEMPT is exported and increments between retries"
else
  not "stage attempt export/retry failed (rc=$rc log=$attempt_log): $ATTEMPT_OUT"
fi

ORACLE_EMPTY_DIR="$TMPDIR/oracle-empty-fail-case"
mkdir -p "$ORACLE_EMPTY_DIR/core/modes"
cat >"$ORACLE_EMPTY_DIR/spec.md" <<'EOF'
# Oracle empty-fail fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
python3 -c "raise SystemExit(0)"

## Oráculo
- comando: test -f /nao/existe && echo OK
- exit esperado: 0

## Barra
- nome: oracle empty-fail fixture

NUNCA use declare const como workaround.
EOF
cat >"$ORACLE_EMPTY_DIR/core/modes/oracle-empty-fail-fixture.yaml" <<'EOF'
id: oracle-empty-fail-fixture
version: "1"
stages:
  - role: run
    command: "true"
    stage_oracle: "true"
    oracle: true
    max_attempts: 2
on_fail: halt
EOF
rc=0
ORACLE_EMPTY_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
    "$STAGES" oracle-empty-fail-fixture "$ORACLE_EMPTY_DIR/spec.md" oracle-empty-fail-test \
    --workdir "$ORACLE_EMPTY_DIR" 2>&1
)" || rc=$?
run_id="$(printf '%s\n' "$ORACLE_EMPTY_OUT" | sed -n 's/^run_id: //p' | tail -1)"
gauntlet_dir="$ORACLE_EMPTY_DIR/.dispatch/logs/inbox/${run_id}.run.gauntlet"
if [ "$rc" -ne 0 ] \
  && [ -f "${gauntlet_dir}/mech-1.log" ] \
  && [ -f "${gauntlet_dir}/mech-2.log" ] \
  && [ ! -s "${gauntlet_dir}/oracle-1.log" ] \
  && [ -s "$ORACLE_EMPTY_DIR/.dispatch/logs/inbox/${run_id}.run.gauntlet/feedback.md" ] 2>/dev/null \
  && printf '%s\n' "$ORACLE_EMPTY_OUT" | grep -qF "gauntlet stage=run attempt=1 gap=" \
  && printf '%s\n' "$ORACLE_EMPTY_OUT" | grep -qF "ERROR: stage run failed after 2 attempts" \
  && ! printf '%s\n' "$ORACLE_EMPTY_OUT" | grep -qF "reason=abnormal_exit"; then
  ok "oracle fail with empty output retries and exits via normal epilogue"
else
  not "oracle empty-fail retry/epilogue failed (rc=$rc run_id=$run_id): $ORACLE_EMPTY_OUT"
fi

RESUME_DIR="$TMPDIR/multistage-resume-case"
mkdir -p "$RESUME_DIR/core/modes"
cat >"$RESUME_DIR/spec.md" <<'EOF'
# Multi-stage resume fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
python3 -c "raise SystemExit(0)"

## Oráculo
- comando: test -f resume-marker
- exit esperado: 0

## Barra
- nome: multistage resume fixture

NUNCA use declare const como workaround.
EOF
touch "$RESUME_DIR/resume-marker"
cat >"$RESUME_DIR/core/modes/multistage-resume-fixture.yaml" <<'EOF'
id: multistage-resume-fixture
version: "1"
stages:
  - role: run
    command: "touch \"$ORACFIT_WORKDIR/run-stage-ran\""
    stage_oracle: "true"
    oracle: true
    max_attempts: 1
  - role: export
    command: "touch \"$ORACFIT_WORKDIR/export-stage-ran\""
    max_attempts: 1
on_fail: halt
EOF
rc=0
RESUME_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$STUB" \
    "$STAGES" multistage-resume-fixture "$RESUME_DIR/spec.md" multistage-resume-test \
    --workdir "$RESUME_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 0 ] \
  && [ -f "$RESUME_DIR/run-stage-ran" ] \
  && [ -f "$RESUME_DIR/export-stage-ran" ] \
  && printf '%s\n' "$RESUME_OUT" | grep -qF "preflight: oracle already passes; multi-stage mode (2 stages)" \
  && printf '%s\n' "$RESUME_OUT" | grep -qF "status: pass"; then
  ok "multi-stage resume passes preflight when oracle already passes and runs all stages"
else
  not "multi-stage resume preflight/dispatch failed (rc=$rc): $RESUME_OUT"
fi

SINGLE_BLOCK_DIR="$TMPDIR/single-stage-oracle-passes"
mkdir -p "$SINGLE_BLOCK_DIR"
cp "$RESUME_DIR/spec.md" "$SINGLE_BLOCK_DIR/spec.md"
touch "$SINGLE_BLOCK_DIR/resume-marker"
source "$ROOT/bin/lib-oracfit-events.sh"
source "$ROOT/bin/lib-oracfit-preflight.sh"
rc=0
SINGLE_PF_OUT="$(
  ORACFIT_ROOT="$ROOT" ORACFIT_PREFLIGHT_STAGE_COUNT=1 \
    oracfit_preflight "$SINGLE_BLOCK_DIR/spec.md" "$SINGLE_BLOCK_DIR" 2>&1
)" || rc=$?
if [ "$rc" -eq 1 ] \
  && printf '%s\n' "$SINGLE_PF_OUT" | grep -qF "oracle already passes before model (nothing to measure)"; then
  ok "single-stage preflight still blocks when oracle already passes"
else
  not "single-stage preflight should reject passing oracle (rc=$rc): $SINGLE_PF_OUT"
fi

echo
echo "=== RESULTS: $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
