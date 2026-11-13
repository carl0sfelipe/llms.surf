#!/usr/bin/env python3
"""oracfit-questions.py — validate, list and export the supervisor question set.

The set is one typed question per class-R rule in the rules map. validate proves the
set (and rejects a tampered copy). list prints a one-line index. export prints the
System-One body that a later client can POST to /v1/systemone. This program does not
call a model and does not decide.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SET = REPO_ROOT / "core" / "supervisor" / "questions.json"
INCIDENTS_DIR = (REPO_ROOT / "incidents").resolve()
VALID_TYPES = frozenset({"noul", "choice", "score"})
VALID_STATES = frozenset({"short", "full"})
SIGNAL_TOKENS = (
    "events.jsonl",
    "tool_call",
    "thinking",
    "oracle_exit",
    "behavior_flags",
    "stderr",
    "git_diff",
    "git_status",
    "log_size",
    "ledger",
    "spec",
    "workdir",
)
ID_RE = re.compile(r"^r(\d+)-[a-z0-9]+(?:-[a-z0-9]+)*$")
RULE_LINE_RE = re.compile(r"^\| (\d+) \|")


class QuestionsParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"oracfit-questions: {message}", file=sys.stderr)
        raise SystemExit(3)


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def is_bool(value: Any) -> bool:
    return isinstance(value, bool)


def nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def resolve_existing(path_str: str) -> Path | None:
    """Resolve a path against cwd, then against the repo root. None if it does not exist."""
    raw = Path(path_str)
    if raw.is_absolute():
        return raw if raw.exists() else None
    cwd_candidate = Path.cwd() / raw
    if cwd_candidate.exists():
        return cwd_candidate
    repo_candidate = REPO_ROOT / raw
    if repo_candidate.exists():
        return repo_candidate
    return None


def class_r_rules_from_map(text: str) -> set[int]:
    """A rule line starts with `| <number> |` and has `**R**` in the third field.

    The class legend is not a rule line: its first field is not a number.
    """
    rules: set[int] = set()
    for line in text.splitlines():
        match = RULE_LINE_RE.match(line)
        if not match:
            continue
        parts = [part.strip() for part in line.split("|")]
        # parts[0] is empty; parts[1] number; parts[2] subject; parts[3] class.
        if len(parts) < 4:
            continue
        if "**R**" in parts[3]:
            rules.add(int(match.group(1)))
    return rules


def expected_id_digits(rule: int) -> str:
    if 0 <= rule < 10:
        return f"{rule:02d}"
    return str(rule)


def id_matches_rule(qid: str, rule: int) -> bool:
    match = ID_RE.match(qid)
    if not match:
        return False
    return match.group(1) == expected_id_digits(rule)


def evidence_item_ok(item: Any) -> bool:
    if not isinstance(item, str) or not item:
        return False
    if any(token in item for token in SIGNAL_TOKENS):
        return True
    return resolve_existing(item) is not None


def incident_path_ok(rel: str) -> bool:
    if not isinstance(rel, str) or not rel or rel.startswith("/"):
        return False
    path = (REPO_ROOT / rel).resolve()
    try:
        path.relative_to(INCIDENTS_DIR)
    except ValueError:
        return False
    return path.is_file()


def load_json_file(path: Path) -> tuple[Any, str | None]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"cannot read {path}: {exc}"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as exc:
        return None, f"not valid JSON: {exc}"


def validate_question(q: Any, index: int, seen_ids: dict[str, int], seen_rules: dict[Any, int]) -> list[str]:
    errors: list[str] = []
    label = f"questions[{index}]"
    if not isinstance(q, dict):
        return [f"{label} is not an object"]

    qid = q.get("id")
    if not nonempty_str(qid):
        errors.append(f"{label}: id is missing")
        qid_s = label
    else:
        qid_s = str(qid)
        if qid_s in seen_ids:
            errors.append(f"duplicate id: {qid_s}")
        else:
            seen_ids[qid_s] = index

    rule = q.get("rule")
    if not is_int(rule):
        errors.append(f"{qid_s}: rule is not an integer")
        rule_n: int | None = None
    else:
        rule_n = rule
        if rule_n in seen_rules:
            errors.append(f"duplicate rule {rule_n}")
        else:
            seen_rules[rule_n] = index
        if isinstance(qid, str) and qid and not id_matches_rule(qid, rule_n):
            errors.append(
                f"{qid_s}: id does not match r<n>-<words> for rule {rule_n}"
            )

    qtype = q.get("type")
    if qtype not in VALID_TYPES:
        errors.append(f"{qid_s}: type is not noul, choice or score")
    has_criteria = "criteria" in q
    criteria = q.get("criteria")
    if qtype == "noul":
        if has_criteria:
            errors.append(f"{qid_s}: noul must not have criteria")
    elif qtype == "choice":
        if not isinstance(criteria, dict) or len(criteria) < 2:
            errors.append(
                f"{qid_s}: choice criteria must be an object with two or more keys"
            )
        elif any(not nonempty_str(k) or not isinstance(v, str) for k, v in criteria.items()):
            errors.append(
                f"{qid_s}: choice criteria keys and values must be non-empty strings"
            )
    elif qtype == "score":
        if (
            not isinstance(criteria, list)
            or len(criteria) < 2
            or any(not isinstance(item, str) or not item for item in criteria)
        ):
            errors.append(
                f"{qid_s}: score criteria must be an array of two or more strings"
            )

    instructions = q.get("instructions")
    if not isinstance(instructions, str) or not instructions.strip() or not instructions.endswith("?"):
        errors.append(
            f"{qid_s}: instructions must be a non-empty string ending in '?'"
        )

    evidence = q.get("evidence")
    if not isinstance(evidence, list) or len(evidence) == 0:
        errors.append(f"{qid_s}: evidence is empty")
    else:
        for item in evidence:
            if not evidence_item_ok(item):
                errors.append(
                    f"{qid_s}: evidence item is not a signal token or an existing path: {item!r}"
                )

    cost = q.get("cost")
    if not isinstance(cost, dict):
        errors.append(f"{qid_s}: cost is not an object")
    else:
        calls = cost.get("model_calls")
        if not is_int(calls) or calls < 1:
            errors.append(f"{qid_s}: cost.model_calls must be an integer >= 1")
        state = cost.get("state")
        if state not in VALID_STATES:
            errors.append(f"{qid_s}: cost.state must be short or full")

    asked = q.get("asked")
    if not is_bool(asked):
        errors.append(f"{qid_s}: asked is not a boolean")
        return errors

    incidents = q.get("incidents")
    if not isinstance(incidents, list):
        errors.append(f"{qid_s}: incidents is not a list")
        return errors

    if asked:
        if len(incidents) < 1:
            errors.append(f"{qid_s}: asked is true but incidents is empty")
        for rel in incidents:
            if not isinstance(rel, str) or not incident_path_ok(rel):
                errors.append(f"{qid_s}: incident path does not exist: {rel!r}")
    else:
        if len(incidents) != 0:
            errors.append(f"{qid_s}: asked is false but incidents is not empty")
        reason = q.get("withheld_reason")
        if not nonempty_str(reason):
            errors.append(f"{qid_s}: withheld_reason is missing")
    return errors


def validate_set(data: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(data, dict):
        return ["top level must be an object"]

    version = data.get("version")
    if not is_int(version):
        errors.append("version is not an integer")

    source = data.get("source")
    if not nonempty_str(source):
        errors.append("source is missing")
        map_rules: set[int] | None = None
    else:
        source_path = resolve_existing(source)
        if source_path is None or not source_path.is_file():
            errors.append(f"source does not exist: {source}")
            map_rules = None
        else:
            map_text = source_path.read_text(encoding="utf-8")
            map_rules = class_r_rules_from_map(map_text)

    questions = data.get("questions")
    if not isinstance(questions, list):
        errors.append("questions is not a list")
        return errors

    seen_ids: dict[str, int] = {}
    seen_rules: dict[Any, int] = {}
    for index, question in enumerate(questions):
        errors.extend(validate_question(question, index, seen_ids, seen_rules))

    question_rules = {rule for rule in seen_rules if is_int(rule)}
    if map_rules is not None:
        if len(questions) != len(map_rules):
            errors.append(
                f"expected {len(map_rules)} questions (one per class-R rule), got {len(questions)}"
            )
        extra = question_rules - map_rules
        missing = map_rules - question_rules
        if extra:
            extra_s = ", ".join(str(n) for n in sorted(extra))
            errors.append(f"rules not in the map: {extra_s}")
        if missing:
            missing_s = ", ".join(str(n) for n in sorted(missing))
            errors.append(f"class-R rules with no question: {missing_s}")
    return errors


def emit_set_errors(errors: list[str]) -> int:
    for reason in errors:
        print(f"set: {reason}")
    return 1 if errors else 0


def resolve_set_path(path_str: str) -> Path:
    found = resolve_existing(path_str)
    if found is not None:
        return found
    raw = Path(path_str)
    if raw.is_absolute():
        return raw
    cwd_candidate = Path.cwd() / raw
    if cwd_candidate.exists() or not (REPO_ROOT / raw).exists():
        return cwd_candidate
    return REPO_ROOT / raw


def cmd_validate(set_path: str) -> int:
    path = resolve_set_path(set_path)
    data, load_error = load_json_file(path)
    if load_error:
        return emit_set_errors([load_error])
    return emit_set_errors(validate_set(data))


def load_questions(set_path: str) -> tuple[list[dict[str, Any]], int]:
    path = resolve_set_path(set_path)
    data, load_error = load_json_file(path)
    if load_error:
        print(f"oracfit-questions: {load_error}", file=sys.stderr)
        return [], 1
    if not isinstance(data, dict) or not isinstance(data.get("questions"), list):
        print("oracfit-questions: questions is not a list", file=sys.stderr)
        return [], 1
    out: list[dict[str, Any]] = []
    for item in data["questions"]:
        if isinstance(item, dict):
            out.append(item)
    return out, 0


def filter_questions(
    questions: list[dict[str, Any]],
    asked_only: bool,
    ids: list[str] | None,
) -> tuple[list[dict[str, Any]], int]:
    if ids is not None:
        known = {str(q.get("id")) for q in questions if "id" in q}
        unknown = [qid for qid in ids if qid not in known]
        if unknown:
            joined = ", ".join(unknown)
            print(f"oracfit-questions: unknown id(s): {joined}", file=sys.stderr)
            return [], 3
        wanted = set(ids)
        questions = [q for q in questions if str(q.get("id")) in wanted]
    if asked_only:
        questions = [q for q in questions if q.get("asked") is True]
    return questions, 0


def cmd_list(set_path: str, asked_only: bool) -> int:
    questions, rc = load_questions(set_path)
    if rc:
        return rc
    questions, rc = filter_questions(questions, asked_only, None)
    if rc:
        return rc
    for q in questions:
        qid = q.get("id", "")
        rule = q.get("rule", "")
        qtype = q.get("type", "")
        cost = q.get("cost") if isinstance(q.get("cost"), dict) else {}
        calls = cost.get("model_calls", "")
        state = cost.get("state", "")
        asked = "true" if q.get("asked") is True else "false"
        print(
            f"{qid}  rule={rule}  type={qtype}  cost={calls}  state={state}  asked={asked}"
        )
    return 0


def api_question(q: dict[str, Any]) -> dict[str, Any]:
    body: dict[str, Any] = {
        "type": q.get("type"),
        "instructions": q.get("instructions"),
    }
    if q.get("type") in ("choice", "score") and "criteria" in q:
        body["criteria"] = q["criteria"]
    return body


def cmd_export(set_path: str, asked_only: bool, ids_csv: str | None) -> int:
    questions, rc = load_questions(set_path)
    if rc:
        return rc
    ids: list[str] | None = None
    if ids_csv is not None:
        ids = [part.strip() for part in ids_csv.split(",") if part.strip()]
        if not ids:
            print("oracfit-questions: --ids is empty", file=sys.stderr)
            return 3
    questions, rc = filter_questions(questions, asked_only, ids)
    if rc:
        return rc
    payload = {
        "questions": {
            str(q.get("id")): api_question(q) for q in questions if "id" in q
        }
    }
    sys.stdout.write(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    return 0


def build_parser() -> QuestionsParser:
    parser = QuestionsParser(
        prog="oracfit-questions",
        description="Validate, list and export the supervisor question set.",
    )
    sub = parser.add_subparsers(dest="cmd")

    validate_p = sub.add_parser("validate", help="check the question set contract")
    validate_p.add_argument(
        "--set",
        dest="set_path",
        default=str(DEFAULT_SET),
        help="question set JSON (default: core/supervisor/questions.json)",
    )

    list_p = sub.add_parser("list", help="one line per question")
    list_p.add_argument("--asked-only", action="store_true")
    list_p.add_argument(
        "--set",
        dest="set_path",
        default=str(DEFAULT_SET),
        help=argparse.SUPPRESS,
    )

    export_p = sub.add_parser("export", help="print the System-One request body")
    export_p.add_argument("--asked-only", action="store_true")
    export_p.add_argument("--ids", dest="ids", default=None)
    export_p.add_argument(
        "--set",
        dest="set_path",
        default=str(DEFAULT_SET),
        help=argparse.SUPPRESS,
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        print("oracfit-questions: expected a subcommand", file=sys.stderr)
        return 3
    if args.cmd == "validate":
        return cmd_validate(args.set_path)
    if args.cmd == "list":
        return cmd_list(args.set_path, args.asked_only)
    if args.cmd == "export":
        return cmd_export(args.set_path, args.asked_only, args.ids)
    parser.print_usage(sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
