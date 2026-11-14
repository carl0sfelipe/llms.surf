#!/usr/bin/env bash
# tests/test-distill-postmortem.sh — the distiller accepts a human postmortem.
# Hermetic: a temp workdir, ORACFIT_ROOT pointed at this repo, no network,
# no model, no GPU. No file of this checkout is written. The twelve proofs
# are independent of each other.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISTILL="$ROOT/bin/oracfit-distill.py"
GOTCHA="$ROOT/bin/oracfit-gotcha.py"

SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/test-distill-postmortem.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

# A git hook or an outer dispatch may export GIT_DIR & co; the scratch tree must not inherit them.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars 2>/dev/null || true)
unset DISPATCH_ROOT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

export GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_GLOBAL="$SCRATCH/gitconfig"
printf '[user]\n\tuseConfigOnly = true\n[init]\n\tdefaultBranch = main\n' >"$GIT_CONFIG_GLOBAL"

export TMPDIR="$SCRATCH/tmp"
mkdir -p "$TMPDIR"
export ORACFIT_ROOT="$ROOT"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }
rc_of() { set +e; "$@" >"$SCRATCH/last.log" 2>&1; echo $?; set -e; }

# english-ok-begin: fake postmortems must match incidents/ (heading Sintoma, key titulo).
write_postmortem() {
  python3 - "$@" <<'PY'
import sys
dest, iid, title, symptom, cause = sys.argv[1:6]
extra = sys.argv[6] if len(sys.argv) > 6 else ""
text = f"""---
id: {iid}
titulo: {title}
data: 2026-11-13
recorrivel: nao
regra: pendente
status: rascunho
---

# {title}

## Sintoma

{symptom}

## Causa

{cause}{extra}
"""
open(dest, "w", encoding="utf-8").write(text)
PY
}
# english-ok-end

# english-ok-begin: fake usage reports must match emit-usage-feedback.sh (heading Contexto, dirty=sim/nao).
write_report() {
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys
dest, workdir, git_field, task, result, exit_code = sys.argv[1:7]
text = f"""---
id: 2026-11-13-{task}-000000
titulo: uso-dispatch dispatch/{task} → {result}
data: 2026-11-13
kind: uso-dispatch
source: dispatch
status: uso-auto
task: {task}
result: {result}
---

# automatic usage: dispatch / {task} → {result}

## Contexto

| Campo | Valor |
|---|---|
| ts (UTC) | 2026-11-13T12:00:00Z |
| source | `dispatch` |
| task | `{task}` |
| result | `{result}` |
| mode | 1 |
| exit_code | {exit_code} |
| harness | `shell` |
| workdir | `{workdir}` |
| git | `{git_field}` dirty=`sim` |
| spec | `spec.md` (0 bytes, sha256=`—`) |
| oracle | `true` |
"""
open(dest, "w", encoding="utf-8").write(text)
PY
}
# english-ok-end

CAUSE="The call site in \`bin/oracfit-distill.py\` used model \`opencode/deepseek-v4-flash-free\`."

echo "== a postmortem becomes a draft"
P1="$SCRATCH/p1"
mkdir -p "$P1/incidents" "$P1/drafts"
P1_ID="fixture-distill-postmortem"
P1_TITLE="fixture postmortem for the distiller"
P1_INC="$P1/incidents/${P1_ID}.md"
write_postmortem "$P1_INC" "$P1_ID" "$P1_TITLE" "The round printed HELP and exited before any model answered." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P1_INC" --out "$P1/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P1/drafts/${P1_ID}.json" "$P1_INC" "$P1_ID" "$P1_TITLE" <<'PY'
import json, sys
from pathlib import Path
draft_path, incident, iid, title = sys.argv[1:5]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
assert d["id"] == iid, d["id"]
assert d["title"] == title, d["title"]
assert Path(d["source_incident"]).resolve() == Path(incident).resolve(), d["source_incident"]
assert Path(draft_path).name == f"{iid}.json"
PY
then
  ok "a postmortem becomes a draft"
else
  not "a postmortem becomes a draft (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the symptom is the incident's symptom section"
P2="$SCRATCH/p2"
mkdir -p "$P2/incidents" "$P2/drafts"
P2_ID="fixture-distill-symptom"
P2_INC="$P2/incidents/${P2_ID}.md"
P2_SYMPTOM="SYMPTOM_SECTION_MARKER"$'\n'"$(python3 -c 'print("x" * 1500)')"
write_postmortem "$P2_INC" "$P2_ID" "fixture symptom truncation" "$P2_SYMPTOM" "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P2_INC" --out "$P2/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P2/drafts/${P2_ID}.json" "$P2_INC" <<'PY'
import json, re, sys
from pathlib import Path
draft_path, incident = sys.argv[1:3]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
text = Path(incident).read_text(encoding="utf-8")
body = text.split("---", 2)[-1]
match = re.search(r"^## Sintoma\s*$", body, re.M)  # english-ok: postmortem heading
assert match, "missing symptom heading"
start = match.end()
if start < len(body) and body[start] == "\n":
    start += 1
nxt = re.search(r"^## ", body[start:], re.M)
end = start + nxt.start() if nxt else len(body)
section = body[start:end].strip()
assert len(section) > 1200, len(section)
assert d["symptom"] == section[:1200], (len(d["symptom"]), d["symptom"][:80])
assert d["symptom"].startswith("SYMPTOM_SECTION_MARKER")
PY
then
  ok "the symptom is the incident's symptom section"
else
  not "the symptom is the incident's symptom section (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the draft decides nothing"
P3="$SCRATCH/p3"
mkdir -p "$P3/incidents" "$P3/drafts"
P3_ID="fixture-distill-empty"
P3_INC="$P3/incidents/${P3_ID}.md"
write_postmortem "$P3_INC" "$P3_ID" "fixture empty trigger" "The round failed." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P3_INC" --out "$P3/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P3/drafts/${P3_ID}.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert d["prescription"] == ""
assert d["trigger"]["class"] == ""
assert d["trigger"]["clauses"] == []
assert d["status"] == "draft"
assert d["needs"] == ["prescription", "trigger", "canary.fire_fixture"]
assert d["canary"]["quiet_fixture"] == "tests/fixtures/gotchas/healthy.json"
PY
then
  ok "the draft decides nothing"
else
  not "the draft decides nothing (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== every citation is a literal substring of the incident"
P4="$SCRATCH/p4"
mkdir -p "$P4/incidents" "$P4/drafts"
P4_ID="fixture-distill-citations"
P4_INC="$P4/incidents/${P4_ID}.md"
write_postmortem "$P4_INC" "$P4_ID" "fixture citations" "The round failed." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P4_INC" --out "$P4/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P4/drafts/${P4_ID}.json" "$P4_INC" <<'PY'
import json, re, sys
from pathlib import Path
draft_path, incident = sys.argv[1:3]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
raw = Path(incident).read_text(encoding="utf-8")
skel_path = Path(draft_path).with_name(d["id"] + ".fire.json")
assert skel_path.is_file(), skel_path
skel = json.loads(skel_path.read_text(encoding="utf-8"))
citations = skel.get("citations")
assert isinstance(citations, dict), citations
backticks = re.findall(r"`([^`\n]+)`", raw)
assert backticks, "postmortem has no backtick literals"
assert citations, "skeleton has no citations"
for quote in citations.values():
    assert isinstance(quote, str) and quote, quote
    assert quote in raw, quote
    assert quote in backticks, quote
PY
then
  ok "every citation is a literal substring of the incident"
else
  not "every citation is a literal substring of the incident (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the fire fixture skeleton decides nothing"
P5="$SCRATCH/p5"
mkdir -p "$P5/incidents" "$P5/drafts"
P5_ID="fixture-distill-skeleton"
P5_INC="$P5/incidents/${P5_ID}.md"
write_postmortem "$P5_INC" "$P5_ID" "fixture skeleton" "The round failed." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P5_INC" --out "$P5/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P5/drafts/${P5_ID}.json" "$P5_INC" <<'PY'
import json, sys
from pathlib import Path
draft_path, incident = sys.argv[1:3]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
want = Path(draft_path).with_name(d["id"] + ".fire.json")
assert want.is_file(), want
fire = Path(d["canary"]["fire_fixture"])
assert fire.resolve() == want.resolve(), (fire, want)
skel = json.loads(want.read_text(encoding="utf-8"))
assert isinstance(skel, dict)
assert skel["signals"] == {}
assert Path(skel["source_incident"]).resolve() == Path(incident).resolve(), skel["source_incident"]
PY
then
  ok "the fire fixture skeleton decides nothing"
else
  not "the fire fixture skeleton decides nothing (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== a postmortem without a symptom section is refused"
P6="$SCRATCH/p6"
mkdir -p "$P6/incidents" "$P6/drafts"
P6_ID="fixture-distill-no-symptom"
P6_INC="$P6/incidents/${P6_ID}.md"
# english-ok-begin: postmortem without heading Sintoma, same frontmatter keys as incidents/.
cat >"$P6_INC" <<EOF
---
id: ${P6_ID}
titulo: fixture without a symptom heading
data: 2026-11-13
recorrivel: nao
regra: pendente
status: rascunho
---

# fixture without a symptom heading

## Causa

The symptom heading is missing on purpose.
EOF
# english-ok-end
rc="$(rc_of python3 "$DISTILL" distill --incident "$P6_INC" --out "$P6/drafts")"
if [ "$rc" -ne 0 ] && [ ! -f "$P6/drafts/${P6_ID}.json" ] && [ ! -f "$P6/drafts/${P6_ID}.fire.json" ] \
  && [ -z "$(ls -A "$P6/drafts")" ]; then
  ok "a postmortem without a symptom section is refused"
else
  not "a postmortem without a symptom section is refused (rc=$rc files=$(ls -A "$P6/drafts" 2>/dev/null))"
fi

echo "== the usage report path still works"
P7="$SCRATCH/p7"
mkdir -p "$P7/drafts"
P7_REPORT="$P7/uso-still-works.md"
write_report "$P7_REPORT" "/no/such/workdir-distill-postmortem" "main@deadbee" "usage-still-works" "blocked" "4"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P7_REPORT" --out "$P7/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P7/drafts/usage-still-works.json" "$P7_REPORT" "$P7/drafts" <<'PY'
import json, sys
from pathlib import Path
draft_path, report, out_dir = sys.argv[1:4]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
s = d["symptom"]
assert d["id"] == "usage-still-works"
assert d["source_incident"] == report
assert "blocked" in s, s
assert "exit_code=4" in s, s
assert "diff --git" not in s
assert d["prescription"] == ""
assert d["trigger"]["class"] == ""
assert d["trigger"]["clauses"] == []
assert d["status"] == "draft"
assert d["canary"]["fire_fixture"] == "tests/fixtures/gotchas/usage-still-works.fire.json"
assert d["canary"]["quiet_fixture"] == "tests/fixtures/gotchas/healthy.json"
assert not (Path(out_dir) / "usage-still-works.fire.json").exists()
PY
then
  ok "the usage report path still works"
else
  not "the usage report path still works (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the bank validator ignores the drafts"
P8="$SCRATCH/p8"
mkdir -p "$P8/core/gotchas/drafts" "$P8/incidents"
P8_ID="fixture-distill-bank"
P8_INC="$P8/incidents/${P8_ID}.md"
write_postmortem "$P8_INC" "$P8_ID" "fixture bank ignores drafts" "The round failed." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P8_INC" --out "$P8/core/gotchas/drafts")"
if [ "$rc" -eq 0 ] && [ -f "$P8/core/gotchas/drafts/${P8_ID}.json" ]; then
  set +e
  (cd "$P8" && python3 "$GOTCHA" validate >"$SCRATCH/bank.log" 2>&1)
  bank_rc=$?
  set -e
  if [ "$bank_rc" -eq 0 ]; then
    ok "the bank validator ignores the drafts"
  else
    not "the bank validator ignores the drafts (rc=$bank_rc log=$(cat "$SCRATCH/bank.log"))"
  fi
else
  not "the bank validator ignores the drafts (distill rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the prescription is the incident's correction section"
P9="$SCRATCH/p9"
mkdir -p "$P9/incidents" "$P9/drafts"
P9_ID="fixture-distill-prescription"
P9_INC="$P9/incidents/${P9_ID}.md"
P9_RX="CORRECTION_SECTION_MARKER"$'\n'"$(python3 -c 'print("y" * 1500)')"
# english-ok-begin: heading Correção aplicada is the canonical correction section in incidents/.
write_postmortem "$P9_INC" "$P9_ID" "fixture prescription from correction" "The round failed." "$CAUSE" "$(printf '\n## Correção aplicada\n\n%s\n' "$P9_RX")"
# english-ok-end
rc="$(rc_of python3 "$DISTILL" distill --incident "$P9_INC" --out "$P9/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P9/drafts/${P9_ID}.json" "$P9_INC" <<'PY'
import json, re, sys
from pathlib import Path
draft_path, incident = sys.argv[1:3]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
text = Path(incident).read_text(encoding="utf-8")
body = text.split("---", 2)[-1]
match = re.search(r"^## Correção aplicada\s*$", body, re.M)  # english-ok: postmortem heading
assert match, "missing correction heading"
start = match.end()
if start < len(body) and body[start] == "\n":
    start += 1
nxt = re.search(r"^## ", body[start:], re.M)
end = start + nxt.start() if nxt else len(body)
section = body[start:end].strip()
assert len(section) > 1200, len(section)
assert d["prescription"] == section[:1200], (len(d["prescription"]), d["prescription"][:80])
assert d["prescription"].startswith("CORRECTION_SECTION_MARKER")
PY
then
  ok "the prescription is the incident's correction section"
else
  not "the prescription is the incident's correction section (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== a postmortem without a correction section has an empty prescription"
P10="$SCRATCH/p10"
mkdir -p "$P10/incidents" "$P10/drafts"
P10_ID="fixture-distill-no-correction"
P10_INC="$P10/incidents/${P10_ID}.md"
write_postmortem "$P10_INC" "$P10_ID" "fixture without a correction heading" "The round failed." "$CAUSE"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P10_INC" --out "$P10/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P10/drafts/${P10_ID}.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert d["prescription"] == ""
assert d["status"] == "draft"
assert d["trigger"]["class"] == ""
assert d["trigger"]["clauses"] == []
PY
then
  ok "a postmortem without a correction section has an empty prescription"
else
  not "a postmortem without a correction section has an empty prescription (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the accepted section names are a closed list"
P11="$SCRATCH/p11"
mkdir -p "$P11/incidents" "$P11/drafts"
P11_ID="fixture-distill-closed-list"
P11_INC="$P11/incidents/${P11_ID}.md"
# File order is the reverse of the accepted-name list so that picking the
# first heading in the file, or the last, cannot pass as picking the first
# name in the list.
# english-ok-begin: closed list of correction headings from incidents/.
write_postmortem "$P11_INC" "$P11_ID" "fixture closed list of correction headings" "The round failed." "$CAUSE" "$(cat <<'EOF'

## Prevenção

PREVENTION_SECTION_MARKER the prevention body.

## Correção aplicada

APPLIED_CORRECTION_MARKER the applied correction body.

## Correção (aplicada)

PAREN_CORRECTION_MARKER the parenthesized correction body.
EOF
)"
# english-ok-end
rc="$(rc_of python3 "$DISTILL" distill --incident "$P11_INC" --out "$P11/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P11/drafts/${P11_ID}.json" "$P11_INC" <<'PY'
import json, re, sys
from pathlib import Path
draft_path, incident = sys.argv[1:3]
d = json.loads(Path(draft_path).read_text(encoding="utf-8"))
text = Path(incident).read_text(encoding="utf-8")
body = text.split("---", 2)[-1]
match = re.search(r"^## Correção aplicada\s*$", body, re.M)  # english-ok: first name in the closed list
assert match, "missing applied-correction heading"
start = match.end()
if start < len(body) and body[start] == "\n":
    start += 1
nxt = re.search(r"^## ", body[start:], re.M)
end = start + nxt.start() if nxt else len(body)
section = body[start:end].strip()
assert d["prescription"] == section[:1200], d["prescription"]
assert d["prescription"].startswith("APPLIED_CORRECTION_MARKER")
assert "PREVENTION_SECTION_MARKER" not in d["prescription"]
assert "PAREN_CORRECTION_MARKER" not in d["prescription"]
PY
then
  ok "the accepted section names are a closed list"
else
  not "the accepted section names are a closed list (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo "== the usage report draft still has an empty prescription"
P12="$SCRATCH/p12"
mkdir -p "$P12/drafts"
P12_REPORT="$P12/uso-empty-prescription.md"
write_report "$P12_REPORT" "/no/such/workdir-distill-prescription" "main@deadbee" "usage-empty-prescription" "blocked" "4"
rc="$(rc_of python3 "$DISTILL" distill --incident "$P12_REPORT" --out "$P12/drafts")"
if [ "$rc" -eq 0 ] && python3 - "$P12/drafts/usage-empty-prescription.json" <<'PY'
import json, sys
from pathlib import Path
d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
assert d["id"] == "usage-empty-prescription"
assert d["prescription"] == ""
assert d["status"] == "draft"
PY
then
  ok "the usage report draft still has an empty prescription"
else
  not "the usage report draft still has an empty prescription (rc=$rc log=$(head -c 200 "$SCRATCH/last.log"))"
fi

echo
echo "test-distill-postmortem: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
