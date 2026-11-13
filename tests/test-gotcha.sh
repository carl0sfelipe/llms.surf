#!/bin/bash
# tests/test-gotcha.sh — gotcha triad compiler, validator and canary.
# Hermetic: work files live under $TMPDIR. No network, no model, no .dispatch/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOTCHA="$ROOT/bin/oracfit-gotcha.py"
FIX="$ROOT/tests/fixtures/gotchas"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gotcha.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$ROOT"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$WORKDIR/last.log" 2>&1; echo $?; set -e; }

write_triad() {
  local dest="$1"
  local patch='{}'
  if [ "$#" -ge 2 ]; then
    patch="$2"
  fi
  GOTCHA_PATCH="$patch" python3 - "$dest" "$ROOT" <<'PY'
import json, os, sys
dest, root = sys.argv[1], sys.argv[2]
fix = os.path.join("tests", "fixtures", "gotchas")
data = {
    "canary": {
        "fire_fixture": os.path.join(fix, "fixture-gotcha-canary.fire.jsonl"),
        "quiet_fixture": os.path.join(fix, "healthy.jsonl"),
    },
    "id": "fixture-gotcha-canary",
    "prescription": "PRESCRIPTION_MARKER the compiler must copy this prescription body unchanged.",
    "source_incident": os.path.join(fix, "incident-fixture.md"),
    "status": "active",
    "symptom": "SYMPTOM_MARKER the compiler must copy this symptom body unchanged.",
    "title": "fixture incident for the gotcha compiler",
    "trigger": {
        "class": "deterministic",
        "clauses": [
            {
                "kind": "events_pattern",
                "path_glob": "*",
                "pattern": "GOTCHA_FIRE_MARKER",
            }
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
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True, ensure_ascii=False)
    fh.write("\n")
PY
}

echo "== 1. compile copies symptom and prescription, leaves the trigger empty"
rc="$(rc_of python3 "$GOTCHA" compile tests/fixtures/gotchas/incident-fixture.md --out "$WORKDIR/draft.json")"
if [ "$rc" -eq 0 ]; then
  ok "compile exit 0"
else
  not "compile exit 0 (rc=$rc)"
fi
if python3 - "$WORKDIR/draft.json" <<'PY'
import json, sys
raw = open(sys.argv[1], encoding="utf-8").read()
d = json.loads(raw)
assert raw == json.dumps(d, indent=2, sort_keys=True, ensure_ascii=False) + "\n", raw
assert d["id"] == "fixture-gotcha-canary"
assert d["title"] == "fixture incident for the gotcha compiler"
assert d["source_incident"] == "tests/fixtures/gotchas/incident-fixture.md"
assert "SYMPTOM_MARKER" in d["symptom"]
assert "Second line of the symptom" in d["symptom"]
assert "PRESCRIPTION_MARKER" in d["prescription"]
assert "Second line of the prescription" in d["prescription"]
assert "CAUSE_MARKER" not in d["symptom"]
assert "CAUSE_MARKER" not in d["prescription"]
assert d["trigger"]["class"] == ""
assert d["trigger"]["clauses"] == []
assert d["status"] == "draft"
assert d["canary"]["fire_fixture"] == "tests/fixtures/gotchas/fixture-gotcha-canary.fire.jsonl"
assert d["canary"]["quiet_fixture"] == "tests/fixtures/gotchas/healthy.jsonl"
PY
then
  ok "compile JSON fields"
else
  not "compile JSON fields"
fi

echo "== 2. draft is refused"
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/draft.json")"
if [ "$rc" -eq 1 ] && grep -q "trigger clauses are empty" "$WORKDIR/last.log"; then
  ok "draft validate mentions empty clauses"
else
  not "draft validate (rc=$rc log=$(head -c 200 "$WORKDIR/last.log"))"
fi

echo "== 3. a complete triad is accepted"
write_triad "$WORKDIR/complete.json"
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/complete.json")"
if [ "$rc" -eq 0 ]; then
  ok "complete triad validate exit 0"
else
  not "complete triad validate (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 4. conjunction: both regex clauses must hold"
write_triad "$WORKDIR/conjunction.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"events_pattern","path_glob":"*","pattern":"GOTCHA_FIRE_MARKER"},{"kind":"events_pattern","path_glob":"*","pattern":"GOTCHA_SECOND_MARKER"}]}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/conjunction.json")"
if [ "$rc" -eq 1 ] && grep -q "canary does not fire" "$WORKDIR/last.log"; then
  ok "partial conjunction does not fire"
else
  not "partial conjunction (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 5. invalid trigger class"
write_triad "$WORKDIR/bad-class.json" '{"trigger":{"class":"maybe"}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/bad-class.json")"
if [ "$rc" -eq 1 ] && grep -q "invalid trigger class" "$WORKDIR/last.log"; then
  ok "invalid class refused"
else
  not "invalid class (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 6. invalid behavior_flag"
write_triad "$WORKDIR/bad-flag.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"behavior_flag","value":"B9"}]}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/bad-flag.json")"
if [ "$rc" -eq 1 ] && grep -q "invalid behavior_flag" "$WORKDIR/last.log"; then
  ok "invalid flag refused"
else
  not "invalid flag (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 7. invalid regex"
write_triad "$WORKDIR/bad-regex.json" '{"trigger":{"class":"deterministic","clauses":[{"kind":"events_pattern","path_glob":"*","pattern":"("}]}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/bad-regex.json")"
if [ "$rc" -eq 1 ] && grep -q "invalid regex" "$WORKDIR/last.log"; then
  ok "invalid regex refused"
else
  not "invalid regex (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 8. fire fixture does not trip the trigger"
write_triad "$WORKDIR/no-fire.json" '{"canary":{"fire_fixture":"tests/fixtures/gotchas/healthy.jsonl"}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/no-fire.json")"
if [ "$rc" -eq 1 ] && grep -q "canary does not fire" "$WORKDIR/last.log"; then
  ok "canary does not fire"
else
  not "canary does not fire (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 9. quiet fixture trips the trigger"
write_triad "$WORKDIR/loud-quiet.json" '{"canary":{"quiet_fixture":"tests/fixtures/gotchas/fixture-gotcha-canary.fire.jsonl"}}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/loud-quiet.json")"
if [ "$rc" -eq 1 ] && grep -q "fires on the quiet fixture" "$WORKDIR/last.log"; then
  ok "canary fires on the quiet fixture"
else
  not "quiet fixture (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 10. source incident missing"
write_triad "$WORKDIR/no-source.json" '{"source_incident":"no-such-incident.md"}'
rc="$(rc_of python3 "$GOTCHA" validate "$WORKDIR/no-source.json")"
if [ "$rc" -eq 1 ] && grep -q "source incident not found" "$WORKDIR/last.log"; then
  ok "missing source incident"
else
  not "missing source incident (rc=$rc log=$(cat "$WORKDIR/last.log"))"
fi

echo "== 11. match lists the id on fire, none on quiet"
mkdir -p "$WORKDIR/tree/core/gotchas"
cp "$WORKDIR/complete.json" "$WORKDIR/tree/core/gotchas/fixture-gotcha-canary.json"
set +e
match_fire="$(cd "$WORKDIR/tree" && python3 "$GOTCHA" match "$FIX/fixture-gotcha-canary.fire.jsonl" 2>"$WORKDIR/match.err")"
rc_fire=$?
match_quiet="$(cd "$WORKDIR/tree" && python3 "$GOTCHA" match "$FIX/healthy.jsonl" 2>>"$WORKDIR/match.err")"
rc_quiet=$?
set -e
if [ "$rc_fire" -eq 0 ] && [ "$match_fire" = "fixture-gotcha-canary" ]; then
  ok "match on fire fixture"
else
  not "match on fire fixture (rc=$rc_fire out='$match_fire' err=$(cat "$WORKDIR/match.err"))"
fi
if [ "$rc_quiet" -eq 0 ] && [ "$match_quiet" = "no match" ]; then
  ok "match on quiet fixture"
else
  not "match on quiet fixture (rc=$rc_quiet out='$match_quiet')"
fi

echo "== 12. quiet fixture is the shared healthy.jsonl"
if python3 - "$WORKDIR/draft.json" "$WORKDIR/complete.json" "$FIX/healthy.jsonl" <<'PY'
import json, os, sys
draft = json.load(open(sys.argv[1], encoding="utf-8"))
complete = json.load(open(sys.argv[2], encoding="utf-8"))
quiet = "tests/fixtures/gotchas/healthy.jsonl"
assert draft["canary"]["quiet_fixture"] == quiet
assert complete["canary"]["quiet_fixture"] == quiet
assert os.path.isfile(sys.argv[3])
assert os.path.samefile(sys.argv[3], quiet)
PY
then
  ok "shared quiet fixture"
else
  not "shared quiet fixture"
fi

echo
echo "test-gotcha: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
