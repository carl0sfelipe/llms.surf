#!/bin/bash
# tests/test-gotcha-bank.sh — first real triad in the gotcha bank.
# Hermetic: no network, no model, no GPU. Runs at the repository root and
# reads the real bank at core/gotchas/. Work files live under $TMPDIR.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GOTCHA="$ROOT/bin/oracfit-gotcha.py"
HEALTHY="$ROOT/tests/fixtures/gotchas/healthy.json"
GENERIC="$ROOT/tests/fixtures/gotchas/generic-failure.json"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/gotcha-bank.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT
cd "$ROOT"

pass=0
fail=0
ok() { echo "  PASS: $1"; pass=$((pass + 1)); }
not() { echo "  FAIL: $1"; fail=$((fail + 1)); }

echo "== the bank is not empty"
set +e
python3 "$GOTCHA" validate >"$WORKDIR/validate.out" 2>"$WORKDIR/validate.err"
validate_rc=$?
set -e
if python3 - "$validate_rc" "$WORKDIR/validate.out" "$WORKDIR/validate.err" <<'PY'
import json, sys
from pathlib import Path

rc = int(sys.argv[1])
out = Path(sys.argv[2]).read_text(encoding="utf-8")
err = Path(sys.argv[3]).read_text(encoding="utf-8")
bank = Path("core/gotchas")
active = []
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("status") == "active":
        active.append(path.name)
if rc != 0:
    raise SystemExit(f"validate rc={rc} out={out!r} err={err!r}")
if not active:
    raise SystemExit("no active triad in core/gotchas")
print("active:", ", ".join(active))
PY
then
  ok "the bank is not empty"
else
  not "the bank is not empty"
fi

echo "== the triad fires on its own evidence"
set +e
python3 - "$GOTCHA" <<'PY'
import json, subprocess, sys
from pathlib import Path

gotcha = sys.argv[1]
bank = Path("core/gotchas")
errors = []
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    fire = triad.get("canary", {}).get("fire_fixture")
    if not fire or not Path(fire).is_file():
        errors.append(f"{path}: missing fire fixture {fire!r}")
        continue
    proc = subprocess.run(
        ["python3", gotcha, "evaluate", "--signals", fire],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        errors.append(f"{path}: evaluate rc={proc.returncode} err={proc.stderr!r}")
        continue
    ids = []
    for line in proc.stdout.splitlines():
        if not line.strip():
            continue
        ids.append(json.loads(line)["id"])
    want = triad.get("id")
    if want not in ids:
        errors.append(f"{path}: evaluate did not list {want!r} (ids={ids!r} out={proc.stdout!r})")
if errors:
    raise SystemExit("\n".join(errors))
PY
fire_rc=$?
set -e
if [ "$fire_rc" -eq 0 ]; then
  ok "the triad fires on its own evidence"
else
  not "the triad fires on its own evidence"
fi

echo "== the triad stays quiet on a healthy round"
set +e
python3 - "$GOTCHA" "$HEALTHY" <<'PY'
import json, subprocess, sys
from pathlib import Path

gotcha, healthy = sys.argv[1], sys.argv[2]
if not Path(healthy).is_file():
    raise SystemExit(f"missing healthy round: {healthy}")
proc = subprocess.run(
    ["python3", gotcha, "evaluate", "--signals", healthy],
    capture_output=True, text=True,
)
if proc.returncode != 0:
    raise SystemExit(f"evaluate rc={proc.returncode} err={proc.stderr!r}")
listed = []
for line in proc.stdout.splitlines():
    if line.strip():
        listed.append(json.loads(line)["id"])
bank = Path("core/gotchas")
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    gotcha_id = triad.get("id")
    if gotcha_id in listed:
        raise SystemExit(f"healthy round listed {gotcha_id!r}: {listed!r}")
PY
quiet_rc=$?
set -e
if [ "$quiet_rc" -eq 0 ]; then
  ok "the triad stays quiet on a healthy round"
else
  not "the triad stays quiet on a healthy round"
fi

echo "== the trigger is narrow"
set +e
python3 - "$GOTCHA" "$GENERIC" <<'PY'
import json, subprocess, sys
from pathlib import Path

gotcha, generic = sys.argv[1], sys.argv[2]
if not Path(generic).is_file():
    raise SystemExit(f"missing generic failure bundle: {generic}")
proc = subprocess.run(
    ["python3", gotcha, "evaluate", "--signals", generic],
    capture_output=True, text=True,
)
if proc.returncode != 0:
    raise SystemExit(f"evaluate rc={proc.returncode} err={proc.stderr!r}")
listed = []
for line in proc.stdout.splitlines():
    if line.strip():
        listed.append(json.loads(line)["id"])
bank = Path("core/gotchas")
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    gotcha_id = triad.get("id")
    if gotcha_id in listed:
        raise SystemExit(
            f"generic failure listed {gotcha_id!r}: trigger is too wide ({listed!r})"
        )
PY
narrow_rc=$?
set -e
if [ "$narrow_rc" -eq 0 ]; then
  ok "the trigger is narrow"
else
  not "the trigger is narrow"
fi

echo "== the evidence is real"
set +e
python3 - <<'PY'
import json, sys
from pathlib import Path

bank = Path("core/gotchas")
errors = []
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    source = triad.get("source_incident")
    if not isinstance(source, str) or not Path(source).is_file():
        errors.append(f"{path}: source_incident missing: {source!r}")
        continue
    fire_path = triad.get("canary", {}).get("fire_fixture")
    if not fire_path or not Path(fire_path).is_file():
        errors.append(f"{path}: fire fixture missing: {fire_path!r}")
        continue
    fire = json.loads(Path(fire_path).read_text(encoding="utf-8"))
    cited = fire.get("source_incident")
    if not isinstance(cited, str) or not Path(cited).is_file():
        errors.append(f"{fire_path}: source_incident missing: {cited!r}")
        continue
    citations = fire.get("citations")
    if not isinstance(citations, dict) or not citations:
        errors.append(f"{fire_path}: citations missing")
        continue
    cited_text = Path(cited).read_text(encoding="utf-8")
    for field, quote in citations.items():
        if not isinstance(quote, str) or not quote:
            errors.append(f"{fire_path}: empty citation for {field!r}")
            continue
        if quote not in cited_text:
            errors.append(
                f"{fire_path}: citation for {field!r} not in {cited}: {quote!r}"
            )
if errors:
    raise SystemExit("\n".join(errors))
PY
evidence_rc=$?
set -e
if [ "$evidence_rc" -eq 0 ]; then
  ok "the evidence is real"
else
  not "the evidence is real"
fi

echo "== the trigger names a base that exists"
set +e
python3 - <<'PY'
import json, os, re, sys
from pathlib import Path

KIND_DIRS = {
    "stderr_pattern": "stderr_dir",
    "text_pattern": "text_root",
    "events_pattern": "events_dir",
}

def signals_of(obj):
    inner = obj.get("signals")
    return inner if isinstance(inner, dict) else obj

def pattern_in_dir(base: Path, pattern: str) -> bool:
    regex = re.compile(pattern)
    for dirpath, dirnames, filenames in os.walk(base, onerror=lambda _err: None):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for name in filenames:
            path = Path(dirpath) / name
            try:
                text = path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if regex.search(text):
                return True
    return False

bank = Path("core/gotchas")
errors = []
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    fire_path = triad.get("canary", {}).get("fire_fixture")
    if not fire_path or not Path(fire_path).is_file():
        errors.append(f"{path}: fire fixture missing: {fire_path!r}")
        continue
    fire = json.loads(Path(fire_path).read_text(encoding="utf-8"))
    signals = signals_of(fire)
    clauses = triad.get("trigger", {}).get("clauses") or []
    for clause in clauses:
        if not isinstance(clause, dict):
            continue
        kind = clause.get("kind")
        dir_key = KIND_DIRS.get(kind)
        if not dir_key:
            continue
        base = signals.get(dir_key)
        if not isinstance(base, str) or not base.strip():
            errors.append(f"{path}: {kind} has no {dir_key} in the fire fixture")
            continue
        root = Path(base)
        if not root.is_absolute():
            root = Path.cwd() / root
        if not root.is_dir():
            errors.append(f"{path}: {dir_key} is not a directory: {base!r}")
            continue
        pattern = clause.get("pattern")
        if not isinstance(pattern, str) or not pattern:
            errors.append(f"{path}: {kind} has no pattern")
            continue
        try:
            found = pattern_in_dir(root, pattern)
        except re.error as exc:
            errors.append(f"{path}: invalid pattern {pattern!r}: {exc}")
            continue
        if not found:
            errors.append(
                f"{path}: pattern {pattern!r} does not occur under {base!r}"
            )
if errors:
    raise SystemExit("\n".join(errors))
PY
base_rc=$?
set -e
if [ "$base_rc" -eq 0 ]; then
  ok "the trigger names a base that exists"
else
  not "the trigger names a base that exists"
fi

echo "== the triad is advisory"
set +e
python3 - <<'PY'
import json, sys
from pathlib import Path

bank = Path("core/gotchas")
errors = []
found = False
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    found = True
    trigger_class = (triad.get("trigger") or {}).get("class")
    if trigger_class != "diffuse":
        errors.append(f"{path}: class is {trigger_class!r}, expected 'diffuse'")
if not found:
    errors.append("no active triad")
if errors:
    raise SystemExit("\n".join(errors))
PY
advisory_rc=$?
set -e
if [ "$advisory_rc" -eq 0 ]; then
  ok "the triad is advisory"
else
  not "the triad is advisory"
fi

echo "== every trigger value is quoted from the incident"
set +e
python3 - <<'PY'
import json
from pathlib import Path

bank = Path("core/gotchas")
errors = []
found = False
for path in sorted(p for p in bank.glob("*.json") if p.is_file()):
    triad = json.loads(path.read_text(encoding="utf-8"))
    if triad.get("status") != "active":
        continue
    found = True
    source = triad.get("source_incident")
    if not isinstance(source, str) or not Path(source).is_file():
        errors.append(f"{path}: source_incident missing: {source!r}")
        continue
    incident = Path(source).read_text(encoding="utf-8")
    fire_path = triad.get("canary", {}).get("fire_fixture")
    fire = json.loads(Path(fire_path).read_text(encoding="utf-8"))
    citations = fire.get("citations")
    if not isinstance(citations, dict):
        citations = {}
    cited_text = " ".join(str(v) for v in citations.values())
    clauses = (triad.get("trigger") or {}).get("clauses") or []
    for clause in clauses:
        kind = clause.get("kind")
        if kind in ("text_pattern", "stderr_pattern", "events_pattern"):
            pattern = clause.get("pattern")
            if not isinstance(pattern, str) or not pattern:
                errors.append(f"{path}: {kind} clause has no pattern")
                continue
            if pattern not in incident:
                errors.append(
                    f"{path}: pattern {pattern!r} is not quoted in {source}"
                )
        elif kind == "oracle_exit":
            value = clause.get("value")
            if not isinstance(value, int) or str(value) not in cited_text:
                errors.append(
                    f"{path}: oracle_exit {value!r} is not quoted by any citation"
                )
        elif kind == "behavior_flag":
            value = clause.get("value")
            if not isinstance(value, str) or value not in incident:
                errors.append(
                    f"{path}: behavior_flag {value!r} is not quoted in {source}"
                )
if not found:
    errors.append("no active triad")
if errors:
    raise SystemExit("\n".join(errors))
PY
quoted_rc=$?
set -e
if [ "$quoted_rc" -eq 0 ]; then
  ok "every trigger value is quoted from the incident"
else
  not "every trigger value is quoted from the incident"
fi

echo
echo "test-gotcha-bank: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
