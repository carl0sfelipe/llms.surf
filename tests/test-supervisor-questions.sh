#!/bin/bash
# tests/test-supervisor-questions.sh — typed question set, validator and export.
# Hermetic: work files live under $TMPDIR. No network, no model, no writes to
# the workdir.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
Q="$ROOT/bin/oracfit-questions.py"
SET="$ROOT/core/supervisor/questions.json"
MAP="$ROOT/fluxos/_comum/mapa-regras.md"  # english-ok: on-disk path of the rules map

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/supervisor-questions.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$ROOT"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$WORKDIR/last.log" 2>&1; echo $?; set -e; }

tamper() {
  local kind="$1"
  local dest="$2"
  python3 - "$SET" "$dest" "$kind" <<'PY'
import json, sys
src, dest, kind = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(src, encoding="utf-8"))
qs = data["questions"]
if kind == "empty_evidence":
    qs[0]["evidence"] = []
elif kind == "bad_type":
    qs[0]["type"] = "nope"
    qs[0].pop("criteria", None)
elif kind == "missing_incident":
    for q in qs:
        if q.get("asked") is True:
            q["incidents"] = ["incidents/does-not-exist.md"]
            break
elif kind == "extra_rule":
    qs[0]["rule"] = 999
    qs[0]["id"] = "r999-not-in-the-map"
elif kind == "dup_id":
    qs[1]["id"] = qs[0]["id"]
elif kind == "noul_criteria":
    for q in qs:
        if q.get("type") == "noul":
            q["criteria"] = {"a": "one", "b": "two"}
            break
else:
    raise SystemExit(f"unknown tamper {kind}")
with open(dest, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PY
}

echo "== 1. the shipped question set validates"
rc="$(rc_of python3 "$Q" validate --set "$SET")"
if [ "$rc" -eq 0 ] && ! grep -q "^set:" "$WORKDIR/last.log"; then
  ok "validate exit 0 with no set: lines"
else
  not "validate shipped set (rc=$rc log=$(head -c 400 "$WORKDIR/last.log"))"
fi

echo "== 2. every class-R rule has exactly one question"
if python3 - "$SET" "$MAP" <<'PY'
import json, re, sys
set_path, map_path = sys.argv[1], sys.argv[2]
data = json.load(open(set_path, encoding="utf-8"))
q_rules = [q["rule"] for q in data["questions"]]
text = open(map_path, encoding="utf-8").read()
map_rules = []
for line in text.splitlines():
    m = re.match(r"^\| (\d+) \|", line)
    if not m:
        continue
    parts = [p.strip() for p in line.split("|")]
    if len(parts) >= 4 and "**R**" in parts[3]:
        map_rules.append(int(m.group(1)))
assert len(map_rules) == 27, map_rules
assert len(q_rules) == 27, q_rules
assert set(q_rules) == set(map_rules), (sorted(set(q_rules)), sorted(set(map_rules)))
assert len(q_rules) == len(set(q_rules)), q_rules
PY
then
  ok "set of rule numbers equals the map (27)"
else
  not "set of rule numbers equals the map (27)"
fi

echo "== 3. every asked question cites an incident that exists"
if python3 - "$SET" "$ROOT" <<'PY'
import json, os, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
root = sys.argv[2]
for q in data["questions"]:
    if q.get("asked") is not True:
        continue
    paths = q.get("incidents")
    assert isinstance(paths, list) and len(paths) >= 1, q["id"]
    for rel in paths:
        assert os.path.isfile(os.path.join(root, rel)), (q["id"], rel)
PY
then
  ok "asked questions cite existing incident files"
else
  not "asked questions cite existing incident files"
fi

echo "== 4. a question without incident history is withheld"
if python3 - "$SET" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for q in data["questions"]:
    if q.get("asked") is not False:
        continue
    assert q.get("incidents") == [], q["id"]
    reason = q.get("withheld_reason")
    assert isinstance(reason, str) and reason.strip(), q["id"]
PY
then
  ok "withheld questions have empty incidents and a reason"
else
  not "withheld questions have empty incidents and a reason"
fi

echo "== 5. the export has the System-One shape"
rc="$(rc_of python3 "$Q" export)"
if [ "$rc" -ne 0 ]; then
  not "export exit 0 (rc=$rc log=$(head -c 200 "$WORKDIR/last.log"))"
else
  cp "$WORKDIR/last.log" "$WORKDIR/export-all.json"
  if python3 - "$WORKDIR/export-all.json" "$SET" <<'PY'
import json, sys
exported = json.load(open(sys.argv[1], encoding="utf-8"))
shipped = json.load(open(sys.argv[2], encoding="utf-8"))
assert list(exported.keys()) == ["questions"], exported.keys()
body = exported["questions"]
assert isinstance(body, dict) and body
by_id = {q["id"]: q for q in shipped["questions"]}
for qid, q in body.items():
    src = by_id[qid]
    keys = set(q.keys())
    assert q["type"] in ("noul", "choice", "score"), q
    assert "instructions" in q
    assert "rule" not in q and "evidence" not in q
    assert "cost" not in q and "incidents" not in q
    if q["type"] == "noul":
        assert keys == {"type", "instructions"}, keys
        assert "criteria" not in src
    elif q["type"] == "choice":
        assert keys == {"type", "instructions", "criteria"}, keys
        assert isinstance(q["criteria"], dict) and len(q["criteria"]) >= 2
    elif q["type"] == "score":
        assert keys == {"type", "instructions", "criteria"}, keys
        assert isinstance(q["criteria"], list) and len(q["criteria"]) >= 2
        assert all(isinstance(x, str) for x in q["criteria"])
assert set(body) == {q["id"] for q in shipped["questions"]}
PY
  then
    ok "export body is type + instructions (+ criteria)"
  else
    not "export body is type + instructions (+ criteria)"
  fi
fi

rc="$(rc_of python3 "$Q" export --asked-only)"
if [ "$rc" -ne 0 ]; then
  not "export --asked-only exit 0 (rc=$rc)"
else
  cp "$WORKDIR/last.log" "$WORKDIR/export-asked.json"
  if python3 - "$WORKDIR/export-asked.json" "$SET" <<'PY'
import json, sys
exported = json.load(open(sys.argv[1], encoding="utf-8"))
shipped = json.load(open(sys.argv[2], encoding="utf-8"))
body = exported["questions"]
withheld = [q["id"] for q in shipped["questions"] if q.get("asked") is False]
asked = [q["id"] for q in shipped["questions"] if q.get("asked") is True]
for qid in withheld:
    assert qid not in body, qid
for qid in asked:
    assert qid in body, qid
PY
  then
    ok "export --asked-only drops withheld questions"
  else
    not "export --asked-only drops withheld questions"
  fi
fi

echo "== 6. the validator rejects a tampered set"
for kind in empty_evidence bad_type missing_incident extra_rule dup_id noul_criteria; do
  dest="$WORKDIR/${kind}.json"
  tamper "$kind" "$dest"
  rc="$(rc_of python3 "$Q" validate --set "$dest")"
  if [ "$rc" -eq 1 ] && grep -q "^set:" "$WORKDIR/last.log"; then
    ok "tamper $kind exits 1"
  else
    not "tamper $kind (rc=$rc log=$(head -c 240 "$WORKDIR/last.log"))"
  fi
done

echo "== 7. every question declares its cost"
if python3 - "$SET" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
for q in data["questions"]:
    cost = q.get("cost")
    assert isinstance(cost, dict), q["id"]
    calls = cost.get("model_calls")
    assert isinstance(calls, int) and not isinstance(calls, bool), q["id"]
    assert cost.get("state") in ("short", "full"), q["id"]
PY
then
  ok "every question has cost.model_calls and cost.state"
else
  not "every question has cost.model_calls and cost.state"
fi

echo
echo "test-supervisor-questions: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
