#!/bin/bash
# tests/test-mode-promises.sh — a mode that names a missing file is refused
# at creation time, by the same resolution the runtime uses.
#
# Hermetic: a temp workdir, ORACFIT_ROOT pointed at this repo, no network,
# no model, no GPU. The eight proofs are independent of each other.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
L="$ROOT/bin/llms-surf"
LOADER="$ROOT/bin/lib-oracfit-mode-loader.py"
CONFERENCE="$ROOT/bin/lib-oracfit-mode-promises.sh"
PT_LIB="$ROOT/bin/lib-oracfit-prompt-template.sh"
JS_LIB="$ROOT/bin/lib-oracfit-json-schema.sh"
W="$(mktemp -d /tmp/oracfit-mode-promises.XXXXXX)"
trap 'rm -rf "$W"' EXIT

export DISPATCH_USAGE_FEEDBACK=0
export ORACFIT_ROOT="$ROOT"
unset DISPATCH_RUNNER

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

fresh() {
  local d="$W/$1"
  mkdir -p "$d"
  cd "$d" || return 1
  export ORACFIT_WORKDIR="$d"
}

# ── 1. a mode with a broken promise is refused ──────────────────────────────
echo "== 1. a mode with a broken promise is refused"
fresh p1
mkdir -p core/modes
cat >core/modes/mp_broken_schema.yaml <<'EOF'
id: mp_broken_schema
version: "1"
name: mp_broken_schema
description: names a schema the runtime would not find
stages:
  - role: run
    model_ref: tier:cheap
    json_schema: no_such_schema_xyz
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode validate mp_broken_schema >"$W/p1.out" 2>"$W/p1.err"; then
  not "a mode with a broken promise is refused"
  echo "    validate exited 0; stderr:" >&2
  cat "$W/p1.err" >&2
else
  if grep -q "no_such_schema_xyz" "$W/p1.err" && grep -q "JSON SCHEMA NOT FOUND" "$W/p1.err"; then
    ok "a mode with a broken promise is refused"
  else
    not "a mode with a broken promise is refused"
    echo "    error did not name the broken schema; stderr:" >&2
    cat "$W/p1.err" >&2
  fi
fi

# ── 2. a mode with a broken prompt is refused ───────────────────────────────
echo "== 2. a mode with a broken prompt is refused"
fresh p2
mkdir -p core/modes
cat >core/modes/mp_broken_prompt.yaml <<'EOF'
id: mp_broken_prompt
version: "1"
name: mp_broken_prompt
description: names a prompt the runtime would not find
stages:
  - role: run
    model_ref: tier:cheap
    prompt_template: no_such_prompt_xyz
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode validate mp_broken_prompt >"$W/p2.out" 2>"$W/p2.err"; then
  not "a mode with a broken prompt is refused"
  echo "    validate exited 0; stderr:" >&2
  cat "$W/p2.err" >&2
else
  if grep -q "no_such_prompt_xyz" "$W/p2.err" && grep -q "PROMPT TEMPLATE NOT FOUND" "$W/p2.err"; then
    ok "a mode with a broken prompt is refused"
  else
    not "a mode with a broken prompt is refused"
    echo "    error did not name the broken prompt; stderr:" >&2
    cat "$W/p2.err" >&2
  fi
fi

# ── 3. a mode whose promises resolve passes ─────────────────────────────────
echo "== 3. a mode whose promises resolve passes"
fresh p3
mkdir -p core/modes core/prompts core/schemas
printf 'stage prompt for the fixture\n' >core/prompts/mp_ok_prompt.md
printf '{}\n' >core/schemas/mp_ok_schema.json
cat >core/modes/mp_ok.yaml <<'EOF'
id: mp_ok
version: "1"
name: mp_ok
description: names a prompt and a schema that exist in this workdir
stages:
  - role: run
    model_ref: tier:cheap
    prompt_template: mp_ok_prompt
    json_schema: mp_ok_schema
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode validate mp_ok >"$W/p3.out" 2>"$W/p3.err"; then
  ok "a mode whose promises resolve passes"
else
  not "a mode whose promises resolve passes"
  echo "    validate failed; stderr:" >&2
  cat "$W/p3.err" >&2
fi

# ── 4. a mode without promises passes ───────────────────────────────────────
echo "== 4. a mode without promises passes"
fresh p4
mkdir -p core/modes
cat >core/modes/mp_plain.yaml <<'EOF'
id: mp_plain
version: "1"
name: mp_plain
description: no prompt_template and no json_schema
stages:
  - role: run
    model_ref: tier:cheap
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode validate mp_plain >"$W/p4.out" 2>"$W/p4.err"; then
  ok "a mode without promises passes"
else
  not "a mode without promises passes"
  echo "    validate failed a mode with no promises; stderr:" >&2
  cat "$W/p4.err" >&2
fi

# ── 5. add refuses a mode with a broken promise ─────────────────────────────
echo "== 5. add refuses a mode with a broken promise"
fresh p5
cat >"$W/share-broken.yaml" <<'EOF'
id: mp_add_broken
version: "1"
name: mp_add_broken
description: shared yaml that names a missing schema
stages:
  - role: run
    model_ref: tier:cheap
    json_schema: no_such_schema_add
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode add "$W/share-broken.yaml" >"$W/p5.out" 2>"$W/p5.err"; then
  not "add refuses a mode with a broken promise"
  echo "    add exited 0; dest=$(ls core/modes 2>/dev/null || true)" >&2
else
  if grep -q "no_such_schema_add" "$W/p5.err" && [ ! -e core/modes/mp_add_broken.yaml ]; then
    ok "add refuses a mode with a broken promise"
  else
    not "add refuses a mode with a broken promise"
    echo "    dest exists or error did not name the schema; stderr:" >&2
    cat "$W/p5.err" >&2
    ls -la core/modes 2>/dev/null || true
  fi
fi

# ── 6. add installs a mode whose promises resolve ───────────────────────────
echo "== 6. add installs a mode whose promises resolve"
fresh p6
mkdir -p core/prompts core/schemas
printf 'shared prompt\n' >core/prompts/mp_add_ok.md
printf '{}\n' >core/schemas/mp_add_ok.json
cat >"$W/share-ok.yaml" <<'EOF'
id: mp_add_ok
version: "1"
name: mp_add_ok
description: shared yaml whose prompt and schema resolve in the dest workdir
stages:
  - role: run
    model_ref: tier:cheap
    prompt_template: mp_add_ok
    json_schema: mp_add_ok
    oracle: true
    max_attempts: 1
on_fail: halt
EOF
if "$L" mode add "$W/share-ok.yaml" >"$W/p6.out" 2>"$W/p6.err" \
    && [ -f core/modes/mp_add_ok.yaml ]; then
  ok "add installs a mode whose promises resolve"
else
  not "add installs a mode whose promises resolve"
  echo "    add failed or did not write the yaml; stderr:" >&2
  cat "$W/p6.err" >&2
fi

# ── 7. the shipped modes still validate ─────────────────────────────────────
echo "== 7. the shipped modes still validate"
fresh p7
shipped_ok=1
if ! "$L" mode validate ui_visual_qa >"$W/p7a.out" 2>"$W/p7a.err"; then
  shipped_ok=0
  echo "    ui_visual_qa failed; stderr:" >&2
  cat "$W/p7a.err" >&2
fi
if ! "$L" mode validate vision_catalog >"$W/p7b.out" 2>"$W/p7b.err"; then
  shipped_ok=0
  echo "    vision_catalog failed; stderr:" >&2
  cat "$W/p7b.err" >&2
fi
if [ "$shipped_ok" -eq 1 ]; then
  ok "the shipped modes still validate"
else
  not "the shipped modes still validate"
fi

# ── 8. the check uses the runtime resolution ────────────────────────────────
echo "== 8. the check uses the runtime resolution"
fresh p8
mkdir -p core/prompts core/schemas core/modes
printf 'conference-proof-prompt\n' >core/prompts/conference_proof.md
printf '{"title":"conference-proof-schema"}\n' >core/schemas/conference_proof.json
cat >core/modes/conference_proof.yaml <<'EOF'
id: conference_proof
version: "1"
name: conference_proof
description: fixture so the conference and the runtime lib see the same file
stages:
  - role: run
    model_ref: tier:cheap
    prompt_template: conference_proof
    json_schema: conference_proof
    oracle: true
    max_attempts: 1
on_fail: halt
EOF

conf_pt="$(
  bash "$CONFERENCE" resolve prompt_template conference_proof \
    --root "$ROOT" --workdir "$PWD"
)"
conf_js="$(
  bash "$CONFERENCE" resolve json_schema conference_proof \
    --root "$ROOT" --workdir "$PWD"
)"
# The full check path (loader declares, conference resolves) must agree too.
check_out="$(
  bash "$CONFERENCE" check core/modes/conference_proof.yaml \
    --root "$ROOT" --workdir "$PWD" --print-resolved
)"
check_pt="$(printf '%s\n' "$check_out" | awk -F'\t' '$1=="prompt_template"{print $3}')"
check_js="$(printf '%s\n' "$check_out" | awk -F'\t' '$1=="json_schema"{print $3}')"

# Direct call of the runtime libs — the comparison the spec asks for.
# shellcheck source=../bin/lib-oracfit-prompt-template.sh
. "$PT_LIB"
# shellcheck source=../bin/lib-oracfit-json-schema.sh
. "$JS_LIB"
rt_pt="$(ORACFIT_WORKDIR="$PWD" ORACFIT_ROOT="$ROOT" oracfit_prompt_template_resolve conference_proof)"
rt_js="$(ORACFIT_WORKDIR="$PWD" ORACFIT_ROOT="$ROOT" oracfit_json_schema_resolve conference_proof)"

want_pt="$PWD/core/prompts/conference_proof.md"
want_js="$PWD/core/schemas/conference_proof.json"
if [ "$conf_pt" = "$rt_pt" ] && [ "$conf_pt" = "$want_pt" ] \
    && [ "$conf_js" = "$rt_js" ] && [ "$conf_js" = "$want_js" ] \
    && [ "$check_pt" = "$rt_pt" ] && [ "$check_js" = "$rt_js" ]; then
  ok "the check uses the runtime resolution"
else
  not "the check uses the runtime resolution"
  echo "    conference prompt=$conf_pt" >&2
  echo "    check prompt=$check_pt" >&2
  echo "    runtime prompt=$rt_pt" >&2
  echo "    want prompt=$want_pt" >&2
  echo "    conference schema=$conf_js" >&2
  echo "    check schema=$check_js" >&2
  echo "    runtime schema=$rt_js" >&2
  echo "    want schema=$want_js" >&2
fi

echo ""
echo "test-mode-promises: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
