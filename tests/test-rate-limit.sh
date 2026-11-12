#!/bin/bash
# test-rate-limit.sh — a throttle a mode declares must be kept by the runtime.
#
# `rate_limit_s: N` used to be a promise nobody kept: the loader demanded it on
# a `map` stage, the catalog documented it as "pause between attempts", and
# neither dispatcher had a single `sleep` in it. A mode could declare a
# throttle and hammer the provider anyway.
#
# This suite is the mechanism that keeps the promise:
#   - both runtimes really wait between two attempts of the same stage
#   - a mode that declares no throttle is not slowed down
#   - the loader refuses a throttle the runtime could not honor
#   - the wait is bounded and a human interrupt ends it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGES="$ROOT/bin/dispatch-stages.sh"
MODE="$ROOT/bin/dispatch-mode.sh"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
RATE_LIB="$ROOT/bin/lib-oracfit-rate-limit.sh"
TMPDIR="$(mktemp -d /tmp/oracfit-rate-limit.XXXXXX)"
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

SPEC="$TMPDIR/spec.md"
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$SPEC" <<'EOF'
# Rate limit fixture

## Objetivo
Não invente números além dos dados verificados.

## Dados verificados
O fixture não precisa de fatos numéricos.

## Verificação
test -f .rate-limit-marker

## Oráculo
- comando: test -f marker.txt
- exit esperado: 0

## Barra
- nome: rate limit fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end

# The fake runner: it fails the first attempt and succeeds on the second, so
# the runtime has to dispatch twice — the pause between attempts is what this
# suite measures.
FAKE_RUNNER="$TMPDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -uo pipefail
count_file="$ORACFIT_WORKDIR/attempt-count"
count=0
if [ -f "$count_file" ]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ "$count" -lt 2 ]; then
  echo "first attempt fails on purpose" >&2
  exit 1
fi
printf 'work done\n' >"$ORACFIT_WORKDIR/marker.txt"
exit 0
EOF
chmod +x "$FAKE_RUNNER"

# make_mode <dir> <id> <rate_limit_line>
make_mode() {
  mkdir -p "$1/core/modes"
  cp "$SPEC" "$1/spec.md"
  {
    echo "id: $2"
    echo 'version: "1"'
    echo "stages:"
    echo "  - role: run"
    echo "    model_ref: fixture-model"
    echo "$3"
    echo "    max_attempts: 2"
    echo "on_fail: halt"
  } >"$1/core/modes/$2.yaml"
}

elapsed_of() { echo $(( $(date +%s) - $1 )); }

# ── case 1: the multi-stage runtime waits when the mode declares a throttle ──
THROTTLED_DIR="$TMPDIR/throttled"
make_mode "$THROTTLED_DIR" "throttled-fixture" "    rate_limit_s: 2"
t0=$(date +%s)
rc=0
THROTTLED_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" throttled-fixture "$THROTTLED_DIR/spec.md" throttled-test \
    --workdir "$THROTTLED_DIR" 2>&1
)" || rc=$?
throttled_s="$(elapsed_of "$t0")"
attempts="$(cat "$THROTTLED_DIR/attempt-count" 2>/dev/null || printf '0')"

# ── case 2: the same run without a throttle is the control ───────────────────
PLAIN_DIR="$TMPDIR/plain"
make_mode "$PLAIN_DIR" "plain-fixture" "    rate_limit_s: 0"
t0=$(date +%s)
rc2=0
PLAIN_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$STAGES" plain-fixture "$PLAIN_DIR/spec.md" plain-test \
    --workdir "$PLAIN_DIR" 2>&1
)" || rc2=$?
plain_s="$(elapsed_of "$t0")"

if [ "$rc" -eq 0 ] && [ "$attempts" -eq 2 ]; then
  ok "the throttled stage ran two attempts and passed"
else
  not "the throttled stage did not retry (rc=$rc attempts=$attempts): $THROTTLED_OUT"
fi

if printf '%s\n' "$THROTTLED_OUT" | grep -qF "RATE LIMIT: waiting"; then
  ok "the multi-stage runtime announces the wait"
else
  not "the multi-stage runtime did not wait: $THROTTLED_OUT"
fi

if [ "$((throttled_s - plain_s))" -ge 1 ]; then
  ok "the multi-stage runtime waits between attempts (${throttled_s}s vs ${plain_s}s)"
else
  not "the declared throttle was ignored (${throttled_s}s vs ${plain_s}s): $THROTTLED_OUT"
fi

if ! printf '%s\n' "$PLAIN_OUT" | grep -qF "RATE LIMIT"; then
  ok "a stage that declares no throttle is not slowed down"
else
  not "a stage without a throttle was slowed down: $PLAIN_OUT"
fi

# ── case 3: the single-stage runtime keeps the same promise ──────────────────
SINGLE_DIR="$TMPDIR/single"
make_mode "$SINGLE_DIR" "single-throttled-fixture" "    rate_limit_s: 2"
t0=$(date +%s)
rc3=0
SINGLE_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-throttled-fixture "$SINGLE_DIR/spec.md" single-throttled-test \
    --workdir "$SINGLE_DIR" 2>&1
)" || rc3=$?
single_s="$(elapsed_of "$t0")"

SINGLE_PLAIN_DIR="$TMPDIR/single-plain"
make_mode "$SINGLE_PLAIN_DIR" "single-plain-fixture" "    rate_limit_s: 0"
t0=$(date +%s)
rc4=0
SINGLE_PLAIN_OUT="$(
  ORACFIT_ROOT="$ROOT" DISPATCH_RUNNER="$FAKE_RUNNER" \
    "$MODE" single-plain-fixture "$SINGLE_PLAIN_DIR/spec.md" single-plain-test \
    --workdir "$SINGLE_PLAIN_DIR" 2>&1
)" || rc4=$?
single_plain_s="$(elapsed_of "$t0")"

if [ "$rc3" -eq 0 ] && [ "$rc4" -eq 0 ]; then
  ok "the single-stage runtime runs both fixtures"
else
  not "the single-stage runtime failed (rc=$rc3/$rc4): $SINGLE_OUT $SINGLE_PLAIN_OUT"
fi

if printf '%s\n' "$SINGLE_OUT" | grep -qF "RATE LIMIT: waiting" \
  && [ "$((single_s - single_plain_s))" -ge 1 ]; then
  ok "the single-stage runtime waits between attempts (${single_s}s vs ${single_plain_s}s)"
else
  not "the single-stage runtime ignored the throttle (${single_s}s vs ${single_plain_s}s): $SINGLE_OUT"
fi

# ── case 4: the loader refuses a throttle the runtime could not honor ───────
loader_rejects() {
  local label="$1" value="$2" dir="$3"
  mkdir -p "$dir/core/modes"
  {
    echo "id: bad-rate-fixture"
    echo 'version: "1"'
    echo "stages:"
    echo "  - role: run"
    echo "    model_ref: fixture-model"
    echo "    rate_limit_s: $value"
    echo "    max_attempts: 1"
    echo "on_fail: halt"
  } >"$dir/core/modes/bad-rate-fixture.yaml"
  local rc=0
  python3 "$LOADER" validate "$dir/core/modes/bad-rate-fixture.yaml" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ]
}

if loader_rejects "string" "fifteen" "$TMPDIR/bad-string"; then
  ok "the loader refuses a rate_limit_s that is not a number"
else
  not "the loader accepted a rate_limit_s that is not a number"
fi

if loader_rejects "negative" "-5" "$TMPDIR/bad-negative"; then
  ok "the loader refuses a negative rate_limit_s"
else
  not "the loader accepted a negative rate_limit_s"
fi

if loader_rejects "over the ceiling" "99999" "$TMPDIR/bad-big"; then
  ok "the loader refuses a rate_limit_s above the ceiling"
else
  not "the loader accepted a rate_limit_s above the ceiling"
fi

# ── case 5: the loader ceiling and the runtime ceiling are the same number ──
loader_ceiling="$(grep -E '^RATE_LIMIT_MAX_S[[:space:]]*=' "$LOADER" \
  | head -1 | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/')"
runtime_ceiling="$(grep -E '^ORACFIT_RATE_LIMIT_MAX_S=' "$RATE_LIB" \
  | head -1 | sed -E 's/.*:-([0-9]+).*/\1/')"
if [ -n "$loader_ceiling" ] && [ "$loader_ceiling" = "$runtime_ceiling" ]; then
  ok "the loader and the runtime share the same ceiling ($loader_ceiling)"
else
  not "the ceilings drifted apart (loader=${loader_ceiling:-?} runtime=${runtime_ceiling:-?})"
fi

# ── case 6: the wait is bounded, and a human interrupt ends it ──────────────
cat >"$TMPDIR/gate.sh" <<'EOF'
#!/bin/bash
set -uo pipefail
source "$1"
# A wait bigger than the ceiling is clamped: it must not turn into an hour of
# silence.
ORACFIT_RATE_LIMIT_MAX_S=2
# One dispatch happened, so the next wait has something to measure against.
oracfit_rate_limit_record_call "model:fixture-model"
start=$(date +%s)
oracfit_rate_limit_gate 999 "clamped wait" "" "model:fixture-model"
rc=$?
echo "CLAMPED=$(( $(date +%s) - start ))"
echo "RC=$rc"
# A human interrupt ends the wait instead of waiting it out.
ORACFIT_RATE_LIMIT_MAX_S=60
oracfit_rate_limit_record_call "model:fixture-model"
touch "$2"
start=$(date +%s)
oracfit_rate_limit_gate 60 "interrupted wait" "$2" "model:fixture-model"
rc=$?
echo "INTERRUPTED=$(( $(date +%s) - start ))"
echo "RC=$rc"
# The ledger records the end of a dispatch, and the gate reads it back.
oracfit_rate_limit_record_call "model:fixture-model"
echo "LAST=$(oracfit_rate_limit_last_call "model:fixture-model")"
EOF
chmod +x "$TMPDIR/gate.sh"
GATE_OUT="$("$TMPDIR/gate.sh" "$RATE_LIB" "$TMPDIR/interrupt.flag")"
clamped_s="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^CLAMPED=//p')"
interrupted_s="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^INTERRUPTED=//p')"
interrupt_rc="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^RC=//p' | tail -1)"
last_call="$(printf '%s\n' "$GATE_OUT" | sed -n 's/^LAST=//p')"

if [ "${clamped_s:-99}" -ge 1 ] && [ "${clamped_s:-99}" -le 4 ]; then
  ok "a wait above the ceiling is clamped to the ceiling (${clamped_s}s)"
else
  not "the wait was not clamped to the ceiling (${clamped_s}s): $GATE_OUT"
fi

if [ "${interrupted_s:-99}" -le 2 ] && [ "${interrupt_rc:-0}" -eq 1 ]; then
  ok "a human interrupt ends the wait (${interrupted_s}s, rc=1)"
else
  not "the wait outlived the human interrupt (${interrupted_s}s rc=${interrupt_rc:-?}): $GATE_OUT"
fi

if [ -n "$last_call" ] && [ "$last_call" -gt 0 ]; then
  ok "the ledger records the end of a dispatch"
else
  not "the ledger recorded nothing: $GATE_OUT"
fi

echo "test-rate-limit: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
