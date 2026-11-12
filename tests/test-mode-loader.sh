#!/usr/bin/env bash
# tests/test-mode-loader.sh — the mode loader has ONE reader.
#
# The loader reads a mode file with PyYAML when it is installed and with its own
# fallback parser when it is not. When the two disagree, the same mode behaves
# differently on two machines: the inline-comment ref (incident
# 2026-11-12-model-ref-com-comentario-inline) was exactly that — a fallback
# parser that kept the comment inside the value.
#
#  T1  the fallback parser and PyYAML produce the SAME tree for every mode and
#      every example (no machine gets a different mode)
#  T2  the fallback parser finds the stages of a mode (the bug that made
#      'stages' come out as a string)
#  T3  a stage with both model_ref and command is refused: the runtime would
#      call the model and drop the command
#  T4  an inline comment after a value does not travel inside the value

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$REPO_ROOT/bin/lib-oracfit-mode-loader.py"
pass=0
fail=0

ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

WORK=$(mktemp -d /tmp/test-mode-loader.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

has_pyyaml() { python3 -c 'import yaml' 2>/dev/null; }

echo "== T1/T2. the fallback parser agrees with PyYAML"
if has_pyyaml; then
  python3 - "$REPO_ROOT" "$LOADER" <<'PY'
import glob, importlib.util, json, os, sys
repo, loader_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("mode_loader", loader_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
import yaml

def norm(data):
    return json.dumps(data, sort_keys=True, indent=1, default=str)

files = sorted(glob.glob(os.path.join(repo, "core", "modes", "*.yaml")))
files += sorted(glob.glob(os.path.join(repo, "examples", "*.yaml")))
bad = []
for path in files:
    text = open(path, encoding="utf-8").read()
    try:
        reference = yaml.safe_load(text)
    except Exception as exc:            # a mode PyYAML cannot read is broken
        bad.append((path, f"PyYAML failed: {exc}"))
        continue
    fallback = mod._load_yaml(text)
    if norm(reference) != norm(fallback):
        bad.append((path, "the fallback parser and PyYAML disagree"))
    stages = fallback.get("stages") if isinstance(fallback, dict) else None
    if not isinstance(stages, list) or not stages:
        bad.append((path, "the fallback parser did not find the stages list"))
for path, why in bad:
    print(f"    {os.path.relpath(path, repo)}: {why}")
print(f"    compared {len(files)} mode files")
sys.exit(1 if bad else 0)
PY
  if [ $? -eq 0 ]; then
    ok "fallback parser and PyYAML agree on every mode file"
  else
    not "fallback parser and PyYAML disagree"
  fi
else
  ok "PyYAML is not installed: the fallback parser is the only reader"
fi

echo "== T3. a stage cannot be both a model call and a command"
cat >"$WORK/both.yaml" <<'YAML'
id: both
version: "1"
name: both
description: a stage that declares a model and a command at once
stages:
  - role: run
    model_ref: tier:cheap
    command: bash -c 'echo hi'
    oracle: true
    max_attempts: 1
gauntlet:
  enabled: true
on_fail: halt
YAML
python3 "$LOADER" validate "$WORK/both.yaml" >"$WORK/both.out" 2>&1
if [ $? -eq 2 ] && grep -q "both model_ref and command" "$WORK/both.out"; then
  ok "validate refuses a stage with model_ref and command"
else
  not "validate accepted a stage with model_ref and command"
  cat "$WORK/both.out"
fi

echo "== T4. an inline comment does not travel inside the value"
cat >"$WORK/comment.yaml" <<'YAML'
id: comment
version: "1"
name: comment
description: a ref with a comment after the value
stages:
  - role: run
    model_ref: tier:cheap   # tier:cheap | tier:mid | tier:expensive
    oracle: true
    max_attempts: 1
gauntlet:
  enabled: true
on_fail: halt
YAML
python3 "$LOADER" dump "$WORK/comment.yaml" >"$WORK/comment.json" 2>/dev/null
if python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
ref = data["stages"][0]["model_ref"]
sys.exit(0 if ref == "tier:cheap" else 1)
' "$WORK/comment.json"; then
  ok "the comment stayed outside the value"
else
  not "the comment traveled inside the model_ref"
fi

echo ""
echo "mode loader: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
