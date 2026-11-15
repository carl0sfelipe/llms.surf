#!/bin/bash
# tests/test-supervisor-env.sh — the supervisor endpoint comes from the
# owner's local file, never from the repo.
#
# Hermetic: the env file lives under a temp dir (ORACFIT_SUPERVISOR_ENV), the
# real ~/.config is never read (HOME and XDG_CONFIG_HOME point at the temp
# dir), no network, no model.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$ROOT/bin/lib-oracfit-supervisor-env.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/supervisor-env.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

# Runs the loader in a clean child shell and prints the three keys.
load() {
  env -i PATH="$PATH" HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/xdg" "$@" bash -c '
    . "$0" && oracfit_supervisor_load_env
    printf "endpoint=%s\ntimeout=%s\npolicy=%s\nother=%s\n" \
      "${ORACFIT_SUPERVISOR_ENDPOINT:-}" "${ORACFIT_SUPERVISOR_TIMEOUT:-}" \
      "${ORACFIT_SUPERVISOR_POLICY:-}" "${SOMETHING_ELSE:-}"
  ' "$LIB"
}

echo "=== test-supervisor-env ==="

cat > "$WORK/a.env" <<'EOF'
# comment
ORACFIT_SUPERVISOR_ENDPOINT=http://127.0.0.1:1/v1/systemone
ORACFIT_SUPERVISOR_TIMEOUT="7"
SOMETHING_ELSE=leak
EOF
out="$(load ORACFIT_SUPERVISOR_ENV="$WORK/a.env")"
if printf '%s\n' "$out" | grep -qx 'endpoint=http://127.0.0.1:1/v1/systemone' \
  && printf '%s\n' "$out" | grep -qx 'timeout=7'; then
  ok "the file sets the endpoint and the timeout"
else
  not "the file sets the endpoint and the timeout ($out)"
fi

if printf '%s\n' "$out" | grep -qx 'other='; then
  ok "a key outside the supervisor keys is ignored"
else
  not "a key outside the supervisor keys is ignored ($out)"
fi

out="$(load ORACFIT_SUPERVISOR_ENV="$WORK/a.env" ORACFIT_SUPERVISOR_ENDPOINT=http://from-env/v1/systemone)"
if printf '%s\n' "$out" | grep -qx 'endpoint=http://from-env/v1/systemone'; then
  ok "a value already in the environment wins"
else
  not "a value already in the environment wins ($out)"
fi

out="$(load ORACFIT_SUPERVISOR_ENV="$WORK/missing.env")"
if printf '%s\n' "$out" | grep -qx 'endpoint='; then
  ok "no file means no endpoint"
else
  not "no file means no endpoint ($out)"
fi

printf 'ORACFIT_SUPERVISOR_ENDPOINT=$(touch %s/pwned)\n' "$WORK" > "$WORK/b.env"
load ORACFIT_SUPERVISOR_ENV="$WORK/b.env" >/dev/null
if [ ! -e "$WORK/pwned" ]; then
  ok "the file is parsed, never executed"
else
  not "the file is parsed, never executed"
fi

mkdir -p "$WORK/xdg/llms-surf"
echo 'ORACFIT_SUPERVISOR_ENDPOINT=http://xdg/v1/systemone' > "$WORK/xdg/llms-surf/supervisor.env"
out="$(load)"
if printf '%s\n' "$out" | grep -qx 'endpoint=http://xdg/v1/systemone'; then
  ok "the default path is under XDG_CONFIG_HOME"
else
  not "the default path is under XDG_CONFIG_HOME ($out)"
fi

missing=""
for f in "$ROOT"/adapters/*/env.sh; do
  case "$f" in */stub/env.sh) continue ;; esac
  grep -q 'oracfit_supervisor_load_env' "$f" || missing="$missing $f"
done
if [ -z "$missing" ]; then
  ok "every real adapter env.sh loads the supervisor file"
else
  not "every real adapter env.sh loads the supervisor file (missing:$missing)"
fi

if ! grep -rqE 'ORACFIT_SUPERVISOR_ENDPOINT=.*https?://' "$ROOT/adapters" "$ROOT/bin"; then
  ok "the repo pins no supervisor URL"
else
  not "the repo pins no supervisor URL"
fi

echo "test-supervisor-env: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
