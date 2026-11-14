#!/usr/bin/env bash
# tests/test-cursor-frontmatter.sh — a spec that starts with YAML frontmatter
# must reach cursor-agent as the prompt, not as an option. Mechanism for the
# 2026-11-14 dogfood miss: without the end-of-options separator, "---" is
# read as an unknown option and the agent aborts before any model call.
#
# Hermetic: temp dir, fake cursor-agent on PATH, no network, no model, no GPU.
# The fake refuses unknown hyphen-leading arguments the way the real agent
# does. A fake that accepts everything would not prove the separator.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$REPO_ROOT/adapters/cursor/runner.sh"
FIX="$REPO_ROOT/tests/fixtures/cursor-stream-sample.jsonl"

# A parent dispatch exports these; the runner would then write into that log.
unset ORACFIT_EVENTS_FILE ORACFIT_RUN_ID
unset CURSOR_AGENT_BIN CURSOR_AGENT_SUBCOMMAND CURSOR_WORKDIR
unset DISPATCH_RUNNER_FORMAT_JSON

W=$(mktemp -d "${TMPDIR:-/tmp}/test-cursor-frontmatter.XXXXXX")
trap 'rm -rf "$W"' EXIT
export TMPDIR="$W/tmp"
mkdir -p "$TMPDIR" "$W/bin" "$W/wd" "$W/fake"

export FAKE_STATE_DIR="$W/fake"
export FAKE_STREAM="$FIX"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Known options are the ones adapters/cursor/runner.sh passes today.
# Flags: -p, --force. Value options: --model, --resume, --output-format,
# --workspace. After "--" everything is positional.
cat > "$W/bin/cursor-agent" <<'EOF'
#!/usr/bin/env bash
set -uo pipefail
positional=""
positional_set=0
resume_opt=""
after_sep=0
while [ "$#" -gt 0 ]; do
  if [ "$after_sep" -eq 1 ]; then
    if [ "$positional_set" -eq 0 ]; then
      positional="$1"
      positional_set=1
    fi
    shift
    continue
  fi
  case "$1" in
    --)
      after_sep=1
      shift
      ;;
    -p|--force)
      shift
      ;;
    --model|--output-format|--workspace)
      shift
      [ "$#" -gt 0 ] && shift
      ;;
    --resume)
      shift
      if [ "$#" -gt 0 ]; then
        resume_opt="$1"
        shift
      fi
      ;;
    -*)
      echo "error: unknown option" >&2
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done
printf '%s' "$positional" > "$FAKE_STATE_DIR/positional"
printf '%s' "$resume_opt" > "$FAKE_STATE_DIR/resume_opt"
cat "$FAKE_STREAM"
exit 0
EOF
chmod +x "$W/bin/cursor-agent"

printf '%s\n' '{"models":[{"id":"grok","cli_hints":{"cursor":"cursor-grok-4.6-xhigh-fast"}}]}' > "$W/reg.json"

# YAML frontmatter: first line is the triple-dash fence.
cat > "$W/front.md" <<'EOF'
---
id: demo
---

Do the work.
EOF

cat > "$W/plain.md" <<'EOF'
Do the work without a fence.
EOF

cat > "$W/list.md" <<'EOF'
- a list item at the start
and the rest of the spec
EOF

reset_fake() {
  rm -f "$FAKE_STATE_DIR/positional" "$FAKE_STATE_DIR/resume_opt"
}

invoke() {
  RUN_RC=0
  PATH="$W/bin:$PATH" \
    CURSOR_API_KEY=x \
    MODEL_REGISTRY="$W/reg.json" \
    ORACFIT_WORKDIR="$W/wd" \
    bash "$RUNNER" "$@" >"$W/stdout.txt" 2>"$W/stderr.txt" || RUN_RC=$?
}

# The runner delivers the spec via $(cat file), which strips trailing newlines.
prompt_is() {
  python3 - "$FAKE_STATE_DIR/positional" "$1" <<'PY'
import pathlib
import sys

got = pathlib.Path(sys.argv[1]).read_bytes()
want = pathlib.Path(sys.argv[2]).read_bytes()
while want.endswith(b"\n"):
    want = want[:-1]
sys.exit(0 if got == want else 1)
PY
}

echo "=== test-cursor-frontmatter ==="

reset_fake
invoke grok "$W/front.md"
if [ "$RUN_RC" -eq 0 ] && prompt_is "$W/front.md"; then
  ok "a spec with frontmatter reaches the agent as the prompt"
else
  not "a spec with frontmatter reaches the agent as the prompt"
fi

reset_fake
BITE_RC=0
BITE_OUT=$("$W/bin/cursor-agent" "$(cat "$W/front.md")" 2>&1) || BITE_RC=$?
if [ "$BITE_RC" -ne 0 ] && printf '%s\n' "$BITE_OUT" | grep -q "error: unknown option"; then
  ok "the fake agent bites"
else
  not "the fake agent bites"
fi

reset_fake
invoke grok "$W/plain.md"
if [ "$RUN_RC" -eq 0 ] && prompt_is "$W/plain.md"; then
  ok "a plain spec still works"
else
  not "a plain spec still works"
fi

reset_fake
invoke grok "$W/list.md"
if [ "$RUN_RC" -eq 0 ] && prompt_is "$W/list.md"; then
  ok "a spec that starts with a single dash still works"
else
  not "a spec that starts with a single dash still works"
fi

reset_fake
SESSION_ID="s-resume-1"
invoke grok "$W/plain.md" --session "$SESSION_ID"
if [ "$RUN_RC" -eq 0 ] \
  && prompt_is "$W/plain.md" \
  && [ "$(cat "$FAKE_STATE_DIR/resume_opt")" = "$SESSION_ID" ]; then
  ok "the resume option stays an option"
else
  not "the resume option stays an option"
fi

if grep -vE '^[[:space:]]*#' "$RUNNER" | grep -Fq -- '"$BIN" "${ARGS[@]}" -- "$(cat "$SPEC_FILE")"'; then
  ok "the runner source keeps the separator"
else
  not "the runner source keeps the separator"
fi

echo "test-cursor-frontmatter: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
