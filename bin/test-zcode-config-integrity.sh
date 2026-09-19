#!/usr/bin/env bash
# test-zcode-config-integrity.sh — D-INC3 regression
#
# writes: scratch HOME only
# reads:  adapters/zcode/runner.sh, adapters/zcode/measure-home-relocation.sh
#
# sha256 of ~/.zcode/cli/config.json is identical before/after a stub
# dispatch, including SIGTERM mid-run, for both overlay and restore.
# Never calls a real model (ZCODE_BIN is a local sleeper).

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not_() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "=== test-zcode-config-integrity (D-INC3) ==="

SCRATCH="$(mktemp -d /tmp/inc3-zcode-XXXXXX)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

FAKE="$SCRATCH/fake-zcode"
cat >"$FAKE" <<'EOF'
#!/usr/bin/env bash
echo "fake-zcode HOME=${HOME}"
echo "fake-zcode argv=$*"
if [ -n "${FAKE_ZCODE_SLEEP:-}" ]; then
  sleep "$FAKE_ZCODE_SLEEP"
fi
exit 0
EOF
chmod +x "$FAKE"

REG="$SCRATCH/registry.json"
cat >"$REG" <<'EOF'
{"models":[{"id":"inc3-probe","cli_hints":{"zcode":"inc3test/probe-model"}}]}
EOF

SPEC="$SCRATCH/spec.md"
echo "inc3 stub spec" >"$SPEC"

OWNER_HOME="$SCRATCH/owner-home"
OWNER_CFG="$OWNER_HOME/.zcode/cli/config.json"
mkdir -p "$OWNER_HOME/.zcode/cli" "$OWNER_HOME/.zcode/plugins"
echo "plugin-keep" >"$OWNER_HOME/.zcode/plugins/keep.txt"
cat >"$OWNER_CFG" <<'EOF'
{
  "model": { "main": "before/keep-me" },
  "owner_marker": "do-not-touch-inc3",
  "provider": {
    "inc3test": {
      "kind": "openai-compatible",
      "options": { "apiKey": "bait", "baseURL": "http://127.0.0.1:1" }
    }
  }
}
EOF

BEFORE="$(sha256sum "$OWNER_CFG" | awk '{print $1}')"
WD="$SCRATCH/workdir"
mkdir -p "$WD"

run_runner() {
  # args extra env come via the environment already set
  HOME="$OWNER_HOME" \
    ZCODE_BIN="$FAKE" \
    ZCODE_API_KEY="bait" \
    MODEL_REGISTRY="$REG" \
    ORACFIT_WORKDIR="$WD" \
    bash "$ROOT/adapters/zcode/runner.sh" inc3-probe "$SPEC"
}

# ── restore (default) clean exit ────────────────────────────────────────
unset ZCODE_CONFIG_STRATEGY
out="$(run_runner 2>&1)" || true
AFTER="$(sha256sum "$OWNER_CFG" | awk '{print $1}')"
if [ "$BEFORE" = "$AFTER" ]; then
  ok "restore (default): sha256 unchanged after stub dispatch"
else
  not_ "restore (default): sha256 changed ($BEFORE -> $AFTER)"
fi
if echo "$out" | grep -q "owner_marker"; then
  not_ "restore: runner leaked owner_marker (should only touch model.main temporarily)"
fi
if echo "$out" | grep -q "this dispatch temporarily sets your zcode model to inc3test/probe-model; restored on exit"; then
  ok "restore: stderr notice before run"
else
  not_ "restore: missing stderr notice: $out"
fi
if grep -q "do-not-touch-inc3" "$OWNER_CFG"; then
  ok "restore: owner_marker still in file"
else
  not_ "restore: owner_marker missing after run"
fi

# ── restore + SIGTERM mid-run ───────────────────────────────────────────
FAKE_ZCODE_SLEEP=30
HOME="$OWNER_HOME" \
  ZCODE_BIN="$FAKE" \
  ZCODE_API_KEY="bait" \
  MODEL_REGISTRY="$REG" \
  ORACFIT_WORKDIR="$WD" \
  ZCODE_CONFIG_STRATEGY=restore \
  bash "$ROOT/adapters/zcode/runner.sh" inc3-probe "$SPEC" >/dev/null 2>&1 &
rpid=$!
sleep 0.3
kill -TERM "$rpid" 2>/dev/null || true
wait "$rpid" 2>/dev/null || true
unset FAKE_ZCODE_SLEEP
AFTER_TERM="$(sha256sum "$OWNER_CFG" | awk '{print $1}')"
if [ "$BEFORE" = "$AFTER_TERM" ]; then
  ok "restore: sha256 unchanged after SIGTERM mid-run"
else
  not_ "restore: sha256 changed after SIGTERM ($BEFORE -> $AFTER_TERM)"
fi

# ── overlay clean exit ──────────────────────────────────────────────────
out="$(ZCODE_CONFIG_STRATEGY=overlay run_runner 2>&1)" || true
AFTER_OV="$(sha256sum "$OWNER_CFG" | awk '{print $1}')"
if [ "$BEFORE" = "$AFTER_OV" ]; then
  ok "overlay: sha256 unchanged after stub dispatch"
else
  not_ "overlay: sha256 changed ($BEFORE -> $AFTER_OV)"
fi
if [ -L "$WD/.dispatch/zcode-home/.zcode/plugins" ] || [ -L "$WD/.dispatch/zcode-home/.zcode/plugins/keep.txt" ]; then
  ok "overlay: non-config ~/.zcode entries are symlinks"
else
  not_ "overlay: expected symlink for plugins under overlay home"
fi
if [ -f "$WD/.dispatch/zcode-home/.zcode/cli/config.json" ] && [ ! -L "$WD/.dispatch/zcode-home/.zcode/cli/config.json" ]; then
  ok "overlay: cli/config.json is a real modified copy"
else
  not_ "overlay: overlay config missing or is a symlink (would write through)"
fi
if grep -q "do-not-touch-inc3" "$OWNER_CFG" && grep -q "before/keep-me" "$OWNER_CFG"; then
  ok "overlay: owner file still has original model.main"
else
  not_ "overlay: owner file mutated"
fi

# ── overlay + SIGTERM ───────────────────────────────────────────────────
FAKE_ZCODE_SLEEP=30
HOME="$OWNER_HOME" \
  ZCODE_BIN="$FAKE" \
  ZCODE_API_KEY="bait" \
  MODEL_REGISTRY="$REG" \
  ORACFIT_WORKDIR="$WD" \
  ZCODE_CONFIG_STRATEGY=overlay \
  bash "$ROOT/adapters/zcode/runner.sh" inc3-probe "$SPEC" >/dev/null 2>&1 &
rpid=$!
sleep 0.3
kill -TERM "$rpid" 2>/dev/null || true
wait "$rpid" 2>/dev/null || true
unset FAKE_ZCODE_SLEEP
AFTER_OV_TERM="$(sha256sum "$OWNER_CFG" | awk '{print $1}')"
if [ "$BEFORE" = "$AFTER_OV_TERM" ]; then
  ok "overlay: sha256 unchanged after SIGTERM mid-run"
else
  not_ "overlay: sha256 changed after SIGTERM ($BEFORE -> $AFTER_OV_TERM)"
fi

# ── bad strategy is loud ────────────────────────────────────────────────
rc=0
ZCODE_CONFIG_STRATEGY=invented run_runner >/dev/null 2>&1 || rc=$?
if [ "$rc" -eq 3 ]; then
  ok "unknown ZCODE_CONFIG_STRATEGY exits 3"
else
  not_ "unknown strategy should exit 3, got $rc"
fi

# ── measure script refuses to invent without the binary ─────────────────
rc=0
out="$(env -u ZCODE_BIN PATH=/usr/bin:/bin HOME="$SCRATCH/no-zcode-home" \
  bash "$ROOT/adapters/zcode/measure-home-relocation.sh" 2>&1)" || rc=$?
if [ "$rc" -eq 3 ] && echo "$out" | grep -q "Do not invent"; then
  if echo "$out" | grep -qE 'HOME relocado:'; then
    not_ "measure script printed sim/não without a binary"
  else
    ok "measure script exits 3 without zcode (no invented lines)"
  fi
else
  not_ "measure script should exit 3 without binary, got rc=$rc out=$out"
fi

echo ""
echo "=== $pass passed, $fail failed ==="
[ "$fail" -eq 0 ]
