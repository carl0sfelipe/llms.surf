#!/usr/bin/env python3
"""oracfit-gotcha.py — compile an incident into a gotcha triad, validate it, match it,
evaluate it against a signals bundle.

A gotcha is a falsifiable triad: trigger / symptom / prescription. The compiler copies
symptom and prescription from the incident and leaves the trigger empty; the predicate is
written by hand. validate proves the trigger still fires on its canary and stays quiet on
the shared healthy fixture. match lists triads whose conjunction fires on a target file.
evaluate lists triads whose conjunction fires on a round's signals bundle (oracle exit,
behavior flags, and the directories the regex kinds walk).
"""
from __future__ import annotations

import argparse
import fnmatch
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

BANK_DIR = Path("core/gotchas")
SECTION_LIMIT = 1200
TRIGGER_CLASSES = frozenset({"deterministic", "diffuse"})
BEHAVIOR_FLAGS = frozenset({"B1", "B2", "B3", "B4", "B5", "B6", "B7", "B8"})
REGEX_KINDS = frozenset({"stderr_pattern", "text_pattern", "events_pattern"})
SCALAR_KINDS = frozenset({"oracle_exit", "behavior_flag"})
KNOWN_KINDS = SCALAR_KINDS | REGEX_KINDS
REGEX_KIND_DIRS = {
    "stderr_pattern": "stderr_dir",
    "text_pattern": "text_root",
    "events_pattern": "events_dir",
}
SIGNALS_BUNDLE_SUFFIX = ".json"
REQUIRED_FIELDS = ("id", "title", "symptom", "prescription")
# english-ok-begin: incident headings the compiler copies; aliases match by prefix.
SYMPTOM_PREFIXES = ("Sintoma", "O que quebrou / ficou frágil")
PRESCRIPTION_PREFIXES = (
    "Correção aplicada",
    "Correção (aplicada)",
    "Prevenção",
    "Mitigação aplicada na hora",
    "Proteção",
)
# english-ok-end
HEADING_RE = re.compile(r"^## ([^#].*?)\s*$", re.MULTILINE)
FRONTMATTER_RE = re.compile(r"\A---\r?\n(.*?)\r?\n---(?:\r?\n|$)", re.DOTALL)


def dumps(obj: Any) -> str:
    return json.dumps(obj, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
    """Read YAML-like `key: value` lines. Field values stay strings."""
    match = FRONTMATTER_RE.match(text)
    if not match:
        return {}, text
    meta: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        meta[key.strip()] = value.strip()
    return meta, text[match.end():]


def extract_section(body: str, prefixes: tuple[str, ...]) -> str:
    """Body between a matching level-2 heading and the next `## `. Empty if none match."""
    headings = list(HEADING_RE.finditer(body))
    for i, match in enumerate(headings):
        title = match.group(1).strip()
        if not any(title.startswith(prefix) for prefix in prefixes):
            continue
        start = match.end()
        if start < len(body) and body[start] == "\n":
            start += 1
        end = headings[i + 1].start() if i + 1 < len(headings) else len(body)
        text = body[start:end].strip()
        return text[:SECTION_LIMIT]
    return ""


def compile_incident(incident_path: str, text: str) -> dict[str, Any]:
    meta, body = parse_frontmatter(text)
    gotcha_id = meta.get("id", "").strip()
    title = meta.get("titulo", "").strip()
    return {
        "id": gotcha_id,
        "title": title,
        "source_incident": incident_path,
        "symptom": extract_section(body, SYMPTOM_PREFIXES),
        "prescription": extract_section(body, PRESCRIPTION_PREFIXES),
        "trigger": {"class": "", "clauses": []},
        "canary": {
            "fire_fixture": f"tests/fixtures/gotchas/{gotcha_id}.fire.jsonl",
            "quiet_fixture": "tests/fixtures/gotchas/healthy.jsonl",
        },
        "status": "draft",
    }


def clause_matches_text(clause: dict[str, Any], text: str) -> bool:
    """Evaluate one regex clause against a blob of text.

    Shared by validate, match and evaluate. `events_pattern` searches each line;
    `stderr_pattern` and `text_pattern` search the whole blob.
    """
    kind = clause.get("kind")
    pattern = clause.get("pattern")
    if not isinstance(pattern, str) or not pattern:
        return False
    try:
        regex = re.compile(pattern)
    except re.error:
        return False
    if kind == "events_pattern":
        return any(regex.search(line) is not None for line in text.splitlines())
    if kind in ("stderr_pattern", "text_pattern"):
        return regex.search(text) is not None
    return False


def path_glob_matches(path: str, pattern: str) -> bool:
    """Same fnmatch as bash `case`: `*` crosses `/`."""
    candidates = [path.replace("\\", "/"), os.path.basename(path)]
    if os.path.isabs(path):
        try:
            candidates.append(os.path.relpath(path, os.getcwd()).replace("\\", "/"))
        except ValueError:
            pass
    return any(fnmatch.fnmatch(candidate, pattern) for candidate in candidates)


def as_int(value: Any) -> int | None:
    if is_int(value):
        return value
    return None


def is_signals_bundle_path(path: str) -> bool:
    return path.endswith(SIGNALS_BUNDLE_SUFFIX)


def signals_from_obj(obj: dict[str, Any]) -> dict[str, Any]:
    """Read signals from the top of a JSON object, or from a nested `signals` object."""
    inner = obj.get("signals")
    src = inner if isinstance(inner, dict) else obj
    return {
        "oracle_exit": src.get("oracle_exit"),
        "behavior_flags": src.get("behavior_flags"),
        "stderr_dir": src.get("stderr_dir"),
        "text_root": src.get("text_root"),
        "events_dir": src.get("events_dir"),
    }


def resolve_existing_dir(value: Any) -> Path | None:
    """Relative dirs resolve against cwd. Missing or non-dir is not an error: None."""
    if not isinstance(value, str) or not value.strip():
        return None
    path = Path(value)
    if not path.is_absolute():
        path = Path.cwd() / path
    try:
        if path.is_dir():
            return path
    except OSError:
        return None
    return None


def list_readable_files(base: Path) -> list[tuple[str, str]]:
    """(path relative to base, text) for readable files under base. Unreadable files skipped."""
    found: list[tuple[str, str]] = []
    try:
        walker = os.walk(base, onerror=lambda _err: None)
    except OSError:
        return found
    for dirpath, _dirnames, filenames in walker:
        for name in filenames:
            abs_path = Path(dirpath) / name
            try:
                rel = abs_path.relative_to(base).as_posix()
            except ValueError:
                rel = name
            try:
                text = abs_path.read_text(encoding="utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            found.append((rel, text))
    return found


def regex_files_for_kind(kind: str, signals: dict[str, Any]) -> list[tuple[str, str]]:
    overlay = signals.get("_files")
    if isinstance(overlay, list):
        return overlay
    dir_key = REGEX_KIND_DIRS.get(kind)
    if not dir_key:
        return []
    base = resolve_existing_dir(signals.get(dir_key))
    if base is None:
        return []
    return list_readable_files(base)


def regex_clause_holds(clause: dict[str, Any], files: list[tuple[str, str]]) -> bool:
    """One regex clause against a list of (path, text). Glob + regex, shared by all commands."""
    glob = clause.get("path_glob")
    if not isinstance(glob, str) or not glob:
        return False
    for path, text in files:
        if path_glob_matches(path, glob) and clause_matches_text(clause, text):
            return True
    return False


def clause_holds(clause: dict[str, Any], signals: dict[str, Any]) -> bool:
    """One clause against a signals bundle. Shared by validate, match and evaluate."""
    if not isinstance(clause, dict):
        return False
    kind = clause.get("kind")
    if kind == "oracle_exit":
        got = as_int(signals.get("oracle_exit"))
        return got is not None and got == clause.get("value")
    if kind == "behavior_flag":
        flags = signals.get("behavior_flags")
        if not isinstance(flags, list):
            return False
        return clause.get("value") in flags
    if kind in REGEX_KINDS:
        return regex_clause_holds(clause, regex_files_for_kind(kind, signals))
    return False


def trigger_matches_signals(trigger: dict[str, Any], signals: dict[str, Any]) -> bool:
    """Conjunction of every clause over a signals bundle."""
    clauses = trigger.get("clauses")
    if not isinstance(clauses, list) or not clauses:
        return False
    for clause in clauses:
        if not clause_holds(clause, signals):
            return False
    return True


def trigger_matches_file(trigger: dict[str, Any], path: str) -> bool:
    """Conjunction of clauses over one file. Non-regex kinds are not satisfied."""
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return False
    return trigger_matches_signals(trigger, {"_files": [(path, text)]})


def trigger_has_scalar_clause(trigger: dict[str, Any]) -> bool:
    clauses = trigger.get("clauses")
    if not isinstance(clauses, list):
        return False
    for clause in clauses:
        if isinstance(clause, dict) and clause.get("kind") in SCALAR_KINDS:
            return True
    return False


def trigger_matches_canary(trigger: dict[str, Any], path: str) -> bool:
    """Fire/quiet fixture: `.json` is a signals bundle; anything else is a file."""
    if is_signals_bundle_path(path):
        data, load_error = load_json(path)
        if load_error or not isinstance(data, dict):
            return False
        return trigger_matches_signals(trigger, signals_from_obj(data))
    return trigger_matches_file(trigger, path)


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def validate_gotcha(path: str, data: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["not a JSON object"]

    for name in REQUIRED_FIELDS:
        if not nonempty_str(data.get(name)):
            errors.append(f"missing or empty field: {name}")

    source = data.get("source_incident")
    if not nonempty_str(source) or not os.path.isfile(str(source)):
        errors.append(f"source incident not found: {source}")

    trigger = data.get("trigger")
    if not isinstance(trigger, dict):
        trigger = {}
    trigger_class = trigger.get("class")
    if trigger_class not in TRIGGER_CLASSES:
        errors.append(f"invalid trigger class: {trigger_class}")

    clauses = trigger.get("clauses")
    if not isinstance(clauses, list) or not clauses:
        errors.append("trigger clauses are empty")
        clauses = []

    for clause in clauses:
        if not isinstance(clause, dict):
            errors.append(f"invalid clause kind: {clause}")
            continue
        kind = clause.get("kind")
        if kind not in KNOWN_KINDS:
            errors.append(f"invalid clause kind: {kind}")
            continue
        if kind == "oracle_exit":
            if not is_int(clause.get("value")):
                errors.append("invalid oracle_exit clause")
        elif kind == "behavior_flag":
            flag = clause.get("value")
            if flag not in BEHAVIOR_FLAGS:
                errors.append(f"invalid behavior_flag clause: {flag}")
        else:
            pattern = clause.get("pattern")
            if not isinstance(pattern, str) or not pattern:
                errors.append("invalid regex: missing pattern")
            else:
                try:
                    re.compile(pattern)
                except re.error as exc:
                    errors.append(f"invalid regex: {exc}")
            glob = clause.get("path_glob")
            if not isinstance(glob, str) or not glob:
                errors.append("clause is missing path_glob")

    canary = data.get("canary") if isinstance(data.get("canary"), dict) else {}
    fire = canary.get("fire_fixture")
    quiet = canary.get("quiet_fixture")
    fire_ok = nonempty_str(fire) and os.path.isfile(str(fire))
    quiet_ok = nonempty_str(quiet) and os.path.isfile(str(quiet))
    if not fire_ok:
        errors.append(f"canary fixture not found: {fire}")
    if not quiet_ok:
        errors.append(f"canary fixture not found: {quiet}")
    if trigger_has_scalar_clause(trigger) and nonempty_str(fire) and not is_signals_bundle_path(str(fire)):
        errors.append(f"canary fixture is not a signals bundle: {fire}")
    if fire_ok and not trigger_matches_canary(trigger, str(fire)):
        errors.append("canary does not fire")
    if quiet_ok and trigger_matches_canary(trigger, str(quiet)):
        errors.append("canary fires on the quiet fixture")

    status = data.get("status")
    if status != "active":
        errors.append(f"status is not active: {status}")
    return errors


def iter_bank() -> list[str]:
    if not BANK_DIR.is_dir():
        return []
    return sorted(str(path) for path in BANK_DIR.glob("*.json") if path.is_file())


def load_json(path: str) -> tuple[Any | None, str | None]:
    try:
        text = Path(path).read_text(encoding="utf-8")
    except OSError:
        return None, "not valid json"
    try:
        return json.loads(text), None
    except json.JSONDecodeError:
        return None, "not valid json"


def cmd_compile(incident: str, out: str | None) -> int:
    if not os.path.isfile(incident):
        print(f"oracfit-gotcha compile: not a file: {incident}", file=sys.stderr)
        return 2
    text = Path(incident).read_text(encoding="utf-8")
    payload = dumps(compile_incident(incident, text))
    if out:
        Path(out).write_text(payload, encoding="utf-8")
    else:
        sys.stdout.write(payload)
    return 0


def cmd_validate(files: list[str]) -> int:
    if files:
        missing = [path for path in files if not os.path.isfile(path)]
        if missing:
            for path in missing:
                print(f"oracfit-gotcha validate: not a file: {path}", file=sys.stderr)
            return 2
        targets = files
    else:
        targets = iter_bank()

    ok_n = 0
    failed_n = 0
    for path in targets:
        data, load_error = load_json(path)
        errors = [load_error] if load_error else validate_gotcha(path, data)
        if errors:
            failed_n += 1
            for reason in errors:
                print(f"ERROR {path}: {reason}")
        else:
            ok_n += 1
    print(f"gotcha validate: {ok_n} ok, {failed_n} failed")
    return 1 if failed_n else 0


def iter_bank_dir(bank: Path) -> list[str]:
    if not bank.is_dir():
        return []
    return sorted(str(path) for path in bank.glob("*.json") if path.is_file())


def cmd_evaluate(signals_path: str, bank_dir: str | None) -> int:
    if not os.path.isfile(signals_path):
        print(f"oracfit-gotcha evaluate: not a file: {signals_path}", file=sys.stderr)
        return 2
    data, load_error = load_json(signals_path)
    if load_error or not isinstance(data, dict):
        print(f"oracfit-gotcha evaluate: invalid signals file: {signals_path}", file=sys.stderr)
        return 2

    bank = Path(bank_dir) if bank_dir else BANK_DIR
    if not bank.is_dir():
        print(f"oracfit-gotcha evaluate: not a directory: {bank}", file=sys.stderr)
        return 2

    signals = signals_from_obj(data)
    hits: list[dict[str, str]] = []
    for path in iter_bank_dir(bank):
        triad, triad_error = load_json(path)
        if triad_error or not isinstance(triad, dict):
            continue
        trigger = triad.get("trigger")
        if not isinstance(trigger, dict):
            continue
        gotcha_id = triad.get("id")
        if not nonempty_str(gotcha_id):
            continue
        if not trigger_matches_signals(trigger, signals):
            continue
        hits.append({
            "id": str(gotcha_id),
            "class": str(trigger.get("class") or ""),
            "title": str(triad.get("title") or ""),
            "prescription": str(triad.get("prescription") or ""),
        })
    hits.sort(key=lambda row: row["id"])
    for row in hits:
        sys.stdout.write(json.dumps(row, ensure_ascii=False) + "\n")
    return 0


def cmd_match(target: str) -> int:
    if not os.path.isfile(target):
        print(f"oracfit-gotcha match: not a file: {target}", file=sys.stderr)
        return 1
    hits: list[str] = []
    for path in iter_bank():
        data, load_error = load_json(path)
        if load_error or not isinstance(data, dict):
            continue
        trigger = data.get("trigger")
        if not isinstance(trigger, dict):
            continue
        gotcha_id = data.get("id")
        if not nonempty_str(gotcha_id):
            continue
        if trigger_matches_file(trigger, target):
            hits.append(str(gotcha_id))
    if not hits:
        print("no match")
        return 0
    for gotcha_id in sorted(hits):
        print(gotcha_id)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="oracfit-gotcha",
        description="Compile, validate, match and evaluate gotcha triads.",
    )
    sub = parser.add_subparsers(dest="cmd")

    compile_p = sub.add_parser("compile", help="copy symptom and prescription from an incident")
    compile_p.add_argument("incident")
    compile_p.add_argument("--out")

    validate_p = sub.add_parser("validate", help="check triad files against the canary contract")
    validate_p.add_argument("files", nargs="*")

    match_p = sub.add_parser("match", help="list triad ids whose trigger fires on a file")
    match_p.add_argument("target", nargs="?")

    evaluate_p = sub.add_parser(
        "evaluate",
        help="list triads whose trigger fires on a signals bundle",
    )
    evaluate_p.add_argument("--signals", required=True, help="JSON signals bundle")
    evaluate_p.add_argument(
        "--bank",
        default=None,
        help="triad bank directory (default: core/gotchas)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        return 2
    if args.cmd == "compile":
        return cmd_compile(args.incident, args.out)
    if args.cmd == "validate":
        return cmd_validate(args.files)
    if args.cmd == "match":
        if not args.target:
            print("oracfit-gotcha match: expected a target file", file=sys.stderr)
            return 1
        return cmd_match(args.target)
    if args.cmd == "evaluate":
        return cmd_evaluate(args.signals, args.bank)
    parser.print_usage(sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
