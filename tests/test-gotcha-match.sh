#!/bin/bash
# tests/test-gotcha-match.sh — deterministic gotcha evaluate + prescription inject.
# Hermetic: work files live under $TMPDIR. No network, no model, no .dispatch/
# of this checkout.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOTCHA="$ROOT/bin/oracfit-gotcha.py"
MODE="$ROOT/bin/dispatch-mode.sh"
FIX="$ROOT/tests/fixtures/gotchas"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gotcha-match.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$ROOT"

export ORACFIT_ROOT="$ROOT"
unset DISPATCH_MODEL_REF
unset ORACFIT_WORKDIR
unset ORACFIT_EVENTS_FILE
unset ORACFIT_NTFY_TOPIC
unset ORACFIT_RUN_ID
# shellcheck source=../bin/lib-oracfit-gauntlet.sh
source "$ROOT/bin/lib-oracfit-gauntlet.sh"
# shellcheck source=../bin/lib-oracfit-gotcha.sh
source "$ROOT/bin/lib-oracfit-gotcha.sh"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$WORKDIR/last.log" 2>&1; echo $?; set -e; }

BANK="$WORKDIR/bank"
mkdir -p "$BANK"

write_signals() {
  local dest="$1"
  local body="$2"
  printf '%s\n' "$body" >"$dest"
}

write_triad() {
  local dest="$1"
  local patch='{}'
  if [ "$#" -ge 2 ]; then
    patch="$2"
  fi
  GOTCHA_PATCH="$patch" python3 - "$dest" "$ROOT" "$WORKDIR" <<'PY'
import json, os, sys
dest, root, work = sys.argv[1], sys.argv[2], sys.argv[3]
fix = os.path.join("tests", "fixtures", "gotchas")
data = {
    "canary": {
        "fire_fixture": os.path.join(work, "fire.json"),
        "quiet_fixture": os.path.join(fix, "healthy.json"),
    },
    "id": "fixture-gotcha-match",
    "prescription": "PRESCRIPTION_MARKER apply this before anything else.",
    "source_incident": os.path.join(fix, "incident-fixture.md"),
    "status": "active",
    "symptom": "SYMPTOM_MARKER a known failure of this shape.",
    "title": "fixture triad for the deterministic matcher",
    "trigger": {
        "class": "deterministic",
        "clauses": [
            {"kind": "oracle_exit", "value": 1},
        ],
    },
}

def merge(base, overlay):
    if isinstance(base, dict) and isinstance(overlay, dict):
        out = dict(base)
        for key, value in overlay.items():
            out[key] = merge(out[key], value) if key in out else value
        return out
    return overlay

data = merge(data, json.loads(os.environ.get("GOTCHA_PATCH", "{}")))
os.makedirs(os.path.dirname(dest) or ".", exist_ok=True)
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True, ensure_ascii=False)
    fh.write("\n")
PY
}

write_signals "$WORKDIR/fire.json" '{"oracle_exit":1,"behavior_flags":[]}'

eval_bank() {
  python3 "$GOTCHA" evaluate --signals "$1" --bank "$BANK"
}

echo "== 0. evaluate --help"
rc="$(rc_of python3 "$GOTCHA" evaluate --help)"
if [ "$rc" -eq 0 ] && grep -q -- "--signals" "$WORKDIR/last.log"; then
  ok "evaluate --help"
else
  not "evaluate --help (rc=$rc)"
fi

echo "== 1. evaluate closes a deterministic triad"
write_triad "$BANK/fixture-gotcha-match.json"
write_signals "$WORKDIR/sig-fire.json" '{"attempt":"1","signals":{"oracle_exit":1,"behavior_flags":[]}}'
set +e
out="$(eval_bank "$WORKDIR/sig-fire.json" 2>"$WORKDIR/eval.err")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && python3 - "$out" <<'PY'
import json, sys
raw = sys.argv[1].strip()
assert raw, "empty output"
lines = raw.splitlines()
assert len(lines) == 1, raw
d = json.loads(lines[0])
assert d["id"] == "fixture-gotcha-match"
assert d["class"] == "deterministic"
assert d["title"] == "fixture triad for the deterministic matcher"
assert d["prescription"] == "PRESCRIPTION_MARKER apply this before anything else."
PY
then
  ok "evaluate prints id class title prescription"
else
  not "evaluate fire (rc=$rc out='$out' err=$(cat "$WORKDIR/eval.err"))"
fi

echo "== 2. conjunction: one of two clauses is not enough"
write_triad "$BANK/fixture-gotcha-match.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"oracle_exit","value":1},{"kind":"behavior_flag","value":"B2"}]}}'
write_signals "$WORKDIR/sig-partial.json" '{"oracle_exit":1,"behavior_flags":[]}'
set +e
out="$(eval_bank "$WORKDIR/sig-partial.json" 2>"$WORKDIR/eval.err")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "partial conjunction prints nothing"
else
  not "partial conjunction (rc=$rc out='$out')"
fi
write_signals "$WORKDIR/sig-partial-flag.json" '{"oracle_exit":0,"behavior_flags":["B2"]}'
set +e
out="$(eval_bank "$WORKDIR/sig-partial-flag.json" 2>"$WORKDIR/eval.err")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "the other partial conjunction prints nothing"
else
  not "other partial conjunction (rc=$rc out='$out')"
fi
write_signals "$WORKDIR/sig-both.json" '{"oracle_exit":1,"behavior_flags":["B2"]}'
set +e
out="$(eval_bank "$WORKDIR/sig-both.json" 2>"$WORKDIR/eval.err")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '"id": "fixture-gotcha-match"'; then
  ok "full conjunction prints the triad"
else
  not "full conjunction (rc=$rc out='$out')"
fi

echo "== 3. scalar signals"
write_triad "$BANK/fixture-gotcha-match.json"
write_signals "$WORKDIR/sig-exit-0.json" '{"oracle_exit":0,"behavior_flags":[]}'
set +e
out="$(eval_bank "$WORKDIR/sig-exit-0.json")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "oracle_exit misses on the wrong code"
else
  not "oracle_exit wrong code (rc=$rc out='$out')"
fi
write_signals "$WORKDIR/sig-exit-1.json" '{"oracle_exit":1,"behavior_flags":[]}'
set +e
out="$(eval_bank "$WORKDIR/sig-exit-1.json")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '"id": "fixture-gotcha-match"'; then
  ok "oracle_exit hits on the right code"
else
  not "oracle_exit right code (rc=$rc out='$out')"
fi

write_triad "$BANK/fixture-gotcha-match.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"behavior_flag","value":"B2"}]}}'
write_signals "$WORKDIR/sig-flag-b1.json" '{"oracle_exit":1,"behavior_flags":["B1"]}'
set +e
out="$(eval_bank "$WORKDIR/sig-flag-b1.json")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "behavior_flag misses on the wrong flag"
else
  not "behavior_flag wrong (rc=$rc out='$out')"
fi
write_signals "$WORKDIR/sig-flag-b2.json" '{"oracle_exit":0,"behavior_flags":["B2"]}'
set +e
out="$(eval_bank "$WORKDIR/sig-flag-b2.json")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && echo "$out" | grep -q '"id": "fixture-gotcha-match"'; then
  ok "behavior_flag hits on the right flag"
else
  not "behavior_flag right (rc=$rc out='$out')"
fi

echo "== a draft triad never fires"
write_triad "$BANK/fixture-gotcha-match.json" '{"status":"draft"}'
write_signals "$WORKDIR/sig-draft.json" '{"oracle_exit":1,"behavior_flags":[]}'
set +e
out_draft="$(eval_bank "$WORKDIR/sig-draft.json")"
rc_draft=$?
set -e
write_triad "$BANK/fixture-gotcha-match.json" '{"status":"active"}'
set +e
out_active="$(eval_bank "$WORKDIR/sig-draft.json")"
rc_active=$?
set -e
if [ "$rc_draft" -eq 0 ] && [ -z "$out_draft" ] \
  && [ "$rc_active" -eq 0 ] && echo "$out_active" | grep -q '"id": "fixture-gotcha-match"'; then
  ok "a draft triad never fires"
else
  not "a draft triad never fires (draft rc=$rc_draft out='$out_draft' active rc=$rc_active out='$out_active')"
fi

echo "== the glob filters before the file is read"
GLOB_BANK="$WORKDIR/bank-glob"
GLOB_TREE="$WORKDIR/glob-tree"
mkdir -p "$GLOB_BANK" "$GLOB_TREE"
printf 'HIT_MARKER found\n' >"$GLOB_TREE/keep.log"
mkfifo "$GLOB_TREE/blocker.pipe"
write_triad "$GLOB_BANK/glob.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"text_pattern","path_glob":"keep.log","pattern":"HIT_MARKER"}]}}'
write_signals "$WORKDIR/sig-glob.json" "{\"oracle_exit\":0,\"behavior_flags\":[],\"text_root\":\"$GLOB_TREE\"}"
set +e
timeout 10 python3 "$GOTCHA" evaluate --signals "$WORKDIR/sig-glob.json" --bank "$GLOB_BANK" \
  >"$WORKDIR/glob.out" 2>"$WORKDIR/glob.err"
rc_glob=$?
set -e
if [ "$rc_glob" -eq 0 ] && grep -q '"id": "fixture-gotcha-match"' "$WORKDIR/glob.out"; then
  ok "the glob filters before the file is read"
else
  not "the glob filters before the file is read (rc=$rc_glob out=$(cat "$WORKDIR/glob.out") err=$(cat "$WORKDIR/glob.err"))"
fi

echo "== 4. diffuse names and is not injected"
write_triad "$BANK/fixture-gotcha-match.json" '{"trigger":{"class":"diffuse","clauses":[{"kind":"oracle_exit","value":1}]}}'
write_signals "$WORKDIR/sig-exit-1.json" '{"oracle_exit":1,"behavior_flags":[]}'
set +e
out="$(eval_bank "$WORKDIR/sig-exit-1.json")"
rc=$?
set -e
if [ "$rc" -eq 0 ] && python3 - "$out" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["id"] == "fixture-gotcha-match"
assert d["class"] == "diffuse"
PY
then
  ok "evaluate lists a diffuse triad that closed"
else
  not "evaluate diffuse (rc=$rc out='$out')"
fi
printf '%s\n' "$out" >"$WORKDIR/fires-diffuse.jsonl"
: >"$WORKDIR/accum-diffuse.md"
set +e
injected="$(oracfit_gotcha_inject "$WORKDIR/accum-diffuse.md" "$WORKDIR/fires-diffuse.jsonl")"
inj_rc=$?
set -e
if [ "$inj_rc" -eq 0 ] && [ -z "$injected" ] && [ ! -s "$WORKDIR/accum-diffuse.md" ]; then
  ok "inject skips diffuse and leaves the accumulator empty"
else
  not "inject diffuse (rc=$inj_rc injected='$injected' accum=$(cat "$WORKDIR/accum-diffuse.md"))"
fi

echo "== 5. canary form"
write_triad "$WORKDIR/scalar-ok.json"
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/scalar-ok.json")"
if [ "$rc" -eq 0 ]; then
  ok "scalar triad with a signals-bundle fire canary validates"
else
  not "scalar bundle canary (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi
write_triad "$WORKDIR/scalar-jsonl.json" "{\"canary\":{\"fire_fixture\":\"tests/fixtures/gotchas/fixture-gotcha-canary.fire.jsonl\"}}"
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/scalar-jsonl.json")"
if [ "$rc" -eq 1 ] && grep -q "canary fixture is not a signals bundle: tests/fixtures/gotchas/fixture-gotcha-canary.fire.jsonl" "$WORKDIR/last.log"; then
  ok "scalar triad with an events-file fire canary is refused"
else
  not "scalar jsonl canary (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 6. inject writes; nothing fired leaves the accumulator empty"
write_triad "$BANK/fixture-gotcha-match.json"
write_signals "$WORKDIR/sig-exit-1.json" '{"oracle_exit":1,"behavior_flags":[]}'
eval_bank "$WORKDIR/sig-exit-1.json" >"$WORKDIR/fires-det.jsonl"
: >"$WORKDIR/accum.md"
set +e
injected="$(oracfit_gotcha_inject "$WORKDIR/accum.md" "$WORKDIR/fires-det.jsonl")"
inj_rc=$?
set -e
if [ "$inj_rc" -eq 0 ] && [ "$injected" = "fixture-gotcha-match" ] \
  && grep -q "fixture-gotcha-match" "$WORKDIR/accum.md" \
  && grep -q "fixture triad for the deterministic matcher" "$WORKDIR/accum.md" \
  && grep -q "PRESCRIPTION_MARKER apply this before anything else." "$WORKDIR/accum.md" \
  && grep -q "GOTCHA PRESCRIPTION (deterministic trigger fired)" "$WORKDIR/accum.md"; then
  ok "inject writes id, title and prescription"
else
  not "inject write (rc=$inj_rc ids='$injected' accum=$(cat "$WORKDIR/accum.md"))"
fi
: >"$WORKDIR/accum-empty.md"
: >"$WORKDIR/fires-none.jsonl"
set +e
injected="$(oracfit_gotcha_inject "$WORKDIR/accum-empty.md" "$WORKDIR/fires-none.jsonl")"
inj_rc=$?
set -e
if [ "$inj_rc" -eq 0 ] && [ -z "$injected" ] && [ ! -s "$WORKDIR/accum-empty.md" ]; then
  ok "inject with no fires leaves the accumulator empty"
else
  not "inject empty (rc=$inj_rc injected='$injected')"
fi

echo "== 7. compose fifth argument"
BASE_SPEC="$WORKDIR/compose-base.md"
ACCUM_FB="$WORKDIR/compose-feedback.md"
GT="$WORKDIR/compose-gt.md"
GOTCHA_MD="$WORKDIR/compose-gotcha.md"
printf '%s\n' "# Base spec" >"$BASE_SPEC"
printf '%s\n' "feedback body" >"$ACCUM_FB"
printf '%s\n' "ground truth body" >"$GT"
printf '%s\n' "GOTCHA_BLOCK_MARKER the prescription" >"$GOTCHA_MD"
OUT4="$WORKDIR/composed-4.md"
OUT5EMPTY="$WORKDIR/composed-5-empty.md"
OUT5="$WORKDIR/composed-5.md"
EMPTY_GOTCHA="$WORKDIR/compose-gotcha-empty.md"
: >"$EMPTY_GOTCHA"
oracfit_gauntlet_compose_spec "$BASE_SPEC" "$ACCUM_FB" "$OUT4" "$GT"
oracfit_gauntlet_compose_spec "$BASE_SPEC" "$ACCUM_FB" "$OUT5EMPTY" "$GT" "$EMPTY_GOTCHA"
oracfit_gauntlet_compose_spec "$BASE_SPEC" "$ACCUM_FB" "$OUT5" "$GT" "$GOTCHA_MD"
if cmp -s "$OUT4" "$OUT5EMPTY"; then
  ok "four-arg compose matches five-arg with an empty gotcha file"
else
  not "four-arg vs empty fifth (diff=$(diff -u "$OUT4" "$OUT5EMPTY" || true))"
fi
if grep -q "GOTCHA_BLOCK_MARKER the prescription" "$OUT5" \
  && grep -q "oracfit-gotcha: deterministic prescriptions; do not remove" "$OUT5" \
  && grep -q "oracfit-gauntlet: injected feedback; do not remove" "$OUT5"; then
  ok "five-arg compose appends prescriptions after feedback"
else
  not "five-arg compose (out=$(cat "$OUT5"))"
fi
if ! grep -q "oracfit-gotcha: deterministic prescriptions" "$OUT4"; then
  ok "four-arg compose has no gotcha block"
else
  not "four-arg leaked a gotcha block"
fi
# Byte-identical to today's four-arg shape: base, then ground truth, then feedback.
if python3 - "$BASE_SPEC" "$ACCUM_FB" "$GT" "$OUT4" <<'PY'
import sys
base, accum, gt, out = sys.argv[1:]
expected = open(base, encoding="utf-8").read()
expected += "\n"
expected += "<!-- oracfit-ground-truth: refresh on each attempt/resume; do not invent beyond this -->\n"
expected += "## GROUND TRUTH (Oracfit inject — authoritative for this run)\n"
expected += "\n"
expected += open(gt, encoding="utf-8").read()
expected += "\n"
expected += "\n"
expected += "<!-- oracfit-gauntlet: injected feedback; do not remove -->\n"
expected += open(accum, encoding="utf-8").read()
got = open(out, encoding="utf-8").read()
assert got == expected, repr((got, expected))
PY
then
  ok "four-arg compose is byte-identical to the previous shape"
else
  not "four-arg compose shape"
fi

echo "== 8. integration: dispatch-mode injects the prescription into attempt 2"
INTEG="$WORKDIR/integ"
mkdir -p "$INTEG/core/modes" "$INTEG/bank"
cat >"$INTEG/core/modes/gotcha-match-fixture.yaml" <<'YAML'
id: gotcha-match-fixture
version: "1"
max_attempts: 2
stages:
  - role: run
    model_ref: fixture-model
on_fail: halt
YAML
# english-ok-begin: the spec headings the gauntlet gate still parses are Portuguese.
cat >"$INTEG/spec.md" <<'EOF'
# Gotcha match fixture

## Objetivo
Nao invente numero, prazo, citacao ou fonte alem dos listados.

## Dados verificados
O fixture nao precisa de fatos numericos.

## Verificacao
test -f marker.txt && grep -q "work done" marker.txt

## Oraculo
- comando: test -f marker.txt && grep -q "work done" marker.txt
- exit esperado: 0

## Barra
- nome: gotcha match fixture

NUNCA use declare const como workaround — importe de verdade.
EOF
# english-ok-end
write_triad "$INTEG/bank/fixture-gotcha-match.json"
FAKE_RUNNER="$WORKDIR/fake-runner.sh"
cat >"$FAKE_RUNNER" <<'EOF'
#!/bin/bash
set -euo pipefail
wd="${ORACFIT_WORKDIR:-$PWD}"
count_file="$wd/attempt-count"
count=0
if [ -f "$count_file" ]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" >"$count_file"
if [ -n "${2:-}" ] && [ -f "$2" ]; then
  cp "$2" "$wd/received-spec-${count}.md"
fi
if [ "$count" -ge 2 ]; then
  printf 'work done\n' >"$wd/marker.txt"
fi
exit 0
EOF
chmod +x "$FAKE_RUNNER"

integ_rc=0
INTEG_OUT="$(
  DISPATCH_RUNNER="$FAKE_RUNNER" \
  DISPATCH_USAGE_FEEDBACK=0 \
  ORACFIT_GOTCHA_BANK="$INTEG/bank" \
    "$MODE" gotcha-match-fixture "$INTEG/spec.md" gotcha-match-integ \
    --workdir "$INTEG" 2>&1
)" || integ_rc=$?

EVENTS="$INTEG/.dispatch/logs/events.jsonl"
SPEC2="$INTEG/received-spec-2.md"
SPEC1="$INTEG/received-spec-1.md"

n_match=0
if [ -f "$EVENTS" ]; then
  n_match="$(python3 -c '
import json, sys
n = 0
try:
    fh = open(sys.argv[1], encoding="utf-8")
except OSError:
    print(0)
    raise SystemExit(0)
for line in fh:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except ValueError:
        continue
    if obj.get("type") == "gotcha_match":
        n += 1
print(n)
' "$EVENTS")"
fi

if [ "$integ_rc" -eq 0 ] && [ -f "$SPEC2" ] \
  && grep -q "PRESCRIPTION_MARKER apply this before anything else." "$SPEC2" \
  && grep -q "fixture-gotcha-match" "$SPEC2" \
  && grep -q "oracfit-gotcha: deterministic prescriptions; do not remove" "$SPEC2"; then
  ok "attempt 2 spec contains the triad prescription"
else
  not "attempt 2 spec (rc=$integ_rc spec2=$( [ -f "$SPEC2" ] && cat "$SPEC2" || echo missing) out=$INTEG_OUT)"
fi
if [ -f "$SPEC1" ] && ! grep -q "PRESCRIPTION_MARKER apply this before anything else." "$SPEC1"; then
  ok "attempt 1 spec has no prescription yet"
else
  not "attempt 1 spec leaked a prescription (exists=$( [ -f "$SPEC1" ] && echo yes || echo no))"
fi
if [ "$n_match" -eq 1 ]; then
  ok "gotcha_match event was emitted"
else
  not "gotcha_match count=$n_match events=$( [ -f "$EVENTS" ] && cat "$EVENTS" || echo missing)"
fi
if [ -f "$EVENTS" ] && python3 - "$EVENTS" <<'PY'
import json, sys
hits = []
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.strip()
    if not line:
        continue
    obj = json.loads(line)
    if obj.get("type") == "gotcha_match":
        hits.append(obj)
assert len(hits) == 1, hits
ev = hits[0]
assert str(ev.get("attempt")) == "1"
assert str(ev.get("oracle_exit")) == "1"
assert str(ev.get("fired")) == "1"
assert str(ev.get("deterministic")) == "1"
assert "fixture-gotcha-match" in str(ev.get("ids") or "")
PY
then
  ok "gotcha_match carries attempt, oracle_exit, counts and ids"
else
  not "gotcha_match fields"
fi

echo
echo "test-gotcha-match: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
