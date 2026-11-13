# lib-oracfit-gotcha.sh — deterministic gotcha match and prescription injection.
# Source me after lib-oracfit-root.sh.
#
# Public:
#   oracfit_gotcha_signals <workdir> <gauntlet_dir> <events_file> <oracle_exit> <attempt>
#   oracfit_gotcha_fires <signals_file> <bank_dir> <out_file>
#   oracfit_gotcha_inject <accum> <fires_file> [note]
#   oracfit_gotcha_match_inject <workdir> <gauntlet_dir> <events_file> \
#       <oracle_exit> <attempt> <accum> [note]
#
# Bank: ${ORACFIT_GOTCHA_BANK:-$ORACFIT_ROOT/core/gotchas}

_oracfit_gotcha_root() {
  if [ -n "${ORACFIT_ROOT:-}" ]; then
    printf '%s\n' "$ORACFIT_ROOT"
    return 0
  fi
  (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
}

_oracfit_gotcha_bank() {
  local root
  root="$(_oracfit_gotcha_root)"
  printf '%s\n' "${ORACFIT_GOTCHA_BANK:-$root/core/gotchas}"
}

# Scan Tier-0, write the round's signals bundle, print its path.
oracfit_gotcha_signals() {
  local workdir="${1:?}"
  local gauntlet_dir="${2:?}"
  local events_file="${3:?}"
  local oracle_exit="${4:?}"
  local attempt="${5:?}"
  local root flags_file signals_file
  root="$(_oracfit_gotcha_root)"
  if ! mkdir -p "$gauntlet_dir"; then
    echo "gotcha: signals unavailable: cannot create ${gauntlet_dir}" >&2
    return 1
  fi
  flags_file="${gauntlet_dir}/behavior-attempt-${attempt}.jsonl"
  signals_file="${gauntlet_dir}/signals-attempt-${attempt}.json"
  if ! : >"$flags_file"; then
    echo "gotcha: signals unavailable: cannot write ${flags_file}" >&2
    return 1
  fi
  # Scanner exit 2 means a high-severity flag — information, not an error.
  if [ -n "${ORACFIT_RUN_ID:-}" ]; then
    python3 "$root/bin/oracfit-behavior-scan.py" "$events_file" \
      --out "$flags_file" \
      --gauntlet-dir "$gauntlet_dir" \
      --run-id "$ORACFIT_RUN_ID" >/dev/null 2>&1 || true
  else
    python3 "$root/bin/oracfit-behavior-scan.py" "$events_file" \
      --out "$flags_file" \
      --gauntlet-dir "$gauntlet_dir" >/dev/null 2>&1 || true
  fi
  if ! python3 - "$workdir" "$gauntlet_dir" "$events_file" "$oracle_exit" "$attempt" \
      "$flags_file" "$signals_file" <<'PY'
import json, os, sys

workdir, gauntlet_dir, events_file, oracle_exit_s, attempt, flags_file, signals_file = sys.argv[1:]

def abs_dir(path):
    if not path:
        return ""
    if os.path.isdir(path):
        return os.path.abspath(path)
    parent = os.path.dirname(path)
    if parent and os.path.isdir(parent):
        return os.path.abspath(parent)
    return os.path.abspath(path)

flags = []
try:
    with open(flags_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            fid = obj.get("id")
            if isinstance(fid, str) and fid:
                flags.append(fid)
except OSError:
    pass

try:
    oracle_exit = int(oracle_exit_s)
except ValueError:
    print("oracle_exit is not an integer: " + oracle_exit_s, file=sys.stderr)
    raise SystemExit(1)

events_dir = abs_dir(os.path.dirname(events_file) or ".")
payload = {
    "attempt": attempt,
    "signals": {
        "oracle_exit": oracle_exit,
        "behavior_flags": flags,
        "stderr_dir": abs_dir(gauntlet_dir),
        "text_root": abs_dir(workdir),
        "events_dir": events_dir,
    },
}
with open(signals_file, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, sort_keys=True, ensure_ascii=False)
    fh.write("\n")
PY
  then
    echo "gotcha: signals unavailable: cannot write signals bundle" >&2
    return 1
  fi
  printf '%s\n' "$signals_file"
  return 0
}

# Evaluate the bank against a signals bundle. Print how many triads fired.
oracfit_gotcha_fires() {
  local signals_file="${1:?}"
  local bank_dir="${2:?}"
  local out_file="${3:?}"
  local root n
  root="$(_oracfit_gotcha_root)"
  if ! python3 "$root/bin/oracfit-gotcha.py" evaluate --signals "$signals_file" --bank "$bank_dir" \
      >"$out_file"; then
    return 1
  fi
  n="$(python3 -c '
import sys
path = sys.argv[1]
n = 0
try:
    for line in open(path, encoding="utf-8"):
        if line.strip():
            n += 1
except OSError:
    n = 0
print(n)
' "$out_file")"
  printf '%s\n' "$n"
  return 0
}

# Append deterministic prescriptions to the accumulator. Print injected ids.
oracfit_gotcha_inject() {
  local accum="${1:?}"
  local fires_file="${2:?}"
  local note="${3:-}"
  python3 - "$accum" "$fires_file" "$note" <<'PY'
import json, os, sys

accum, fires_file, note = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
try:
    with open(fires_file, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            if obj.get("class") != "deterministic":
                continue
            gotcha_id = obj.get("id")
            if not isinstance(gotcha_id, str) or not gotcha_id:
                continue
            rows.append(obj)
except OSError:
    rows = []

if not rows:
    raise SystemExit(0)

os.makedirs(os.path.dirname(accum) or ".", exist_ok=True)
parts = [
    "",
    "## GOTCHA PRESCRIPTION (deterministic trigger fired) — apply FIRST",
    "",
]
note_line = note.splitlines()[0].strip() if note else ""
if note_line:
    parts.append("Note: " + note_line)
    parts.append("")
parts.append(
    "The following known failure fired in this run. Apply the prescription below before anything else."
)
parts.append("")
ids = []
for row in rows:
    gotcha_id = str(row.get("id") or "")
    title = str(row.get("title") or "")
    prescription = str(row.get("prescription") or "")
    parts.append(f"### {gotcha_id} — {title}")
    parts.append("")
    parts.append(prescription)
    parts.append("")
    ids.append(gotcha_id)
text = "\n".join(parts)
if not text.endswith("\n"):
    text += "\n"
with open(accum, "a", encoding="utf-8") as fh:
    fh.write(text)
sys.stdout.write(",".join(ids) + "\n")
PY
}

# Signals → evaluate → inject. Print injected ids. Exit 1 if a step failed.
oracfit_gotcha_match_inject() {
  local workdir="${1:?}"
  local gauntlet_dir="${2:?}"
  local events_file="${3:?}"
  local oracle_exit="${4:?}"
  local attempt="${5:?}"
  local accum="${6:?}"
  local note="${7:-}"
  local signals_file fires_file bank ids
  bank="$(_oracfit_gotcha_bank)"
  if ! signals_file="$(oracfit_gotcha_signals "$workdir" "$gauntlet_dir" "$events_file" "$oracle_exit" "$attempt")"; then
    return 1
  fi
  fires_file="${gauntlet_dir}/fires-attempt-${attempt}.jsonl"
  if ! oracfit_gotcha_fires "$signals_file" "$bank" "$fires_file" >/dev/null; then
    return 1
  fi
  if ! ids="$(oracfit_gotcha_inject "$accum" "$fires_file" "$note")"; then
    return 1
  fi
  if [ -n "$ids" ]; then
    printf '%s\n' "$ids"
  fi
  return 0
}
