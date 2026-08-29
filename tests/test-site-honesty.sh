#!/bin/bash
# test-site-honesty.sh — the public site may not invent a count.
#
# DATA.stats in site/app.js must equal what git actually contains.
# A decorative count that doesn't match the tree is an incident, not marketing.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/site/app.js"
fail() { echo "FAIL: $*" >&2; exit 1; }
[ -f "$APP" ] || fail "site/app.js missing"

extract() {
  local key="$1"
  python3 - "$APP" "$key" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
# grab the stats object only
m = re.search(r"stats:\s*\{(.*?)\n\s*\}", text, re.S)
if not m:
    sys.exit("stats block not found")
block = m.group(1)
key = sys.argv[2]
km = re.search(rf"{re.escape(key)}:\s*(\d+|\"[^\"]+\")", block)
if not km:
    sys.exit(f"key {key} not found")
print(km.group(1).strip('"'))
PY
}

incidents_disk=$(find "$ROOT/incidents" -name '*.md' ! -name README.md ! -path '*/uso/*' | wc -l | tr -d ' ')
models_disk=$(python3 -c "import json; print(len(json.load(open('$ROOT/model-registry.json'))['models']))")
modes_disk=$(find "$ROOT/core/modes" -name '*.yaml' | wc -l | tr -d ' ')
adapters_disk=$(find "$ROOT/adapters" -mindepth 1 -maxdepth 1 -type d ! -name stub | wc -l | tr -d ' ')
stub_disk=$(find "$ROOT/adapters" -mindepth 1 -maxdepth 1 -type d -name stub | wc -l | tr -d ' ')
suites_disk=$(find "$ROOT/tests" -maxdepth 1 -name 'test-*.sh' | wc -l | tr -d ' ')
version_disk=$(tr -d ' \n' < "$ROOT/VERSION")

incidents_js=$(extract incidents)
models_js=$(extract models)
modes_js=$(extract modes)
adapters_js=$(extract adapters)
stub_js=$(extract adaptersStub)
suites_js=$(extract suites)
version_js=$(extract version)

check() {
  local name="$1" js="$2" disk="$3"
  if [ "$js" != "$disk" ]; then
    fail "$name: site/app.js has $js, tree has $disk"
  fi
  echo "ok $name=$disk"
}

check incidents "$incidents_js" "$incidents_disk"
check models "$models_js" "$models_disk"
check modes "$modes_js" "$modes_disk"
check adapters "$adapters_js" "$adapters_disk"
check adaptersStub "$stub_js" "$stub_disk"
check suites "$suites_js" "$suites_disk"
check version "$version_js" "$version_disk"

# The landing sells the dispatcher in this repo. It must not advertise a
# hosted-inference product that does not exist.
if grep -qiE 'hosted inference is not live|hosted swell|llms\.surf swell' "$ROOT/site/index.html" "$APP" "$ROOT/site/readme.html" "$ROOT/site/v4-plan.html"; then
  fail "site advertises hosted swell — there is no product yet"
fi
if grep -E 'tps: [0-9]' "$APP"; then
  fail "numeric tps in DATA — do not invent a hosted cell"
fi

# Pages exist.
for f in index.html readme.html incidents.html v4-plan.html styles.css logo.svg app.js journey.js llms.txt; do
  [ -f "$ROOT/site/$f" ] || fail "site/$f missing"
done

# llms.txt is the agent surface — same counts as DATA.stats, no invented product.
LLMS="$ROOT/site/llms.txt"
grep -q "version: $version_disk" "$LLMS" || fail "llms.txt version != VERSION"
grep -q "incidents: $incidents_disk" "$LLMS" || fail "llms.txt incidents != tree"
grep -q "models in registry: $models_disk" "$LLMS" || fail "llms.txt models != tree"
grep -q "modes: $modes_disk" "$LLMS" || fail "llms.txt modes != tree"
grep -q "adapters: $adapters_disk + $stub_disk stub" "$LLMS" || fail "llms.txt adapters != tree"
grep -q "test suites: $suites_disk" "$LLMS" || fail "llms.txt suites != tree"
if grep -qiE 'hosted inference is not live|hosted swell' "$LLMS"; then
  fail "llms.txt advertises hosted swell — there is no product yet"
fi

echo "test-site-honesty: ok"
