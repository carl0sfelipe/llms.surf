#!/usr/bin/env python3
"""oracfit-supervisor-plan.py — show the supervisor policy as a readable plan.

Calls the policy engine's validate subcommand and joins the result with the
question set. It does not ask, decide, connect to a network, call a model, or
write the workdir. The only file it writes is --out, and only when given.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

PROG = "oracfit-supervisor-plan"
BIN_DIR = Path(__file__).resolve().parent
REPO_ROOT = BIN_DIR.parent
ENGINE = BIN_DIR / "oracfit-policy.py"
DEFAULT_POLICY = REPO_ROOT / "core" / "supervisor" / "policy.json"
DEFAULT_QUESTIONS = REPO_ROOT / "core" / "supervisor" / "questions.json"


class PlanParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"{PROG}: {message}", file=sys.stderr)
        raise SystemExit(3)


def fail(message: str, code: int = 1) -> int:
    print(f"{PROG}: {message}", file=sys.stderr)
    return code


def nonempty_str(value: Any) -> bool:
    return isinstance(value, str) and bool(value.strip())


def load_json_file(path: Path) -> tuple[Any, str | None]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"cannot read {path}: {exc}"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as exc:
        return None, f"not valid JSON: {exc}"


def format_value(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


def validate_via_engine(policy_path: Path) -> tuple[dict[str, Any] | None, int]:
    try:
        proc = subprocess.run(
            [sys.executable, str(ENGINE), "validate", "--policy", str(policy_path)],
            capture_output=True,
            text=True,
        )
    except OSError as exc:
        return None, fail(f"cannot run policy engine: {exc}")
    if proc.returncode != 0:
        if proc.stderr:
            sys.stderr.write(proc.stderr)
        return None, 1
    try:
        policy = json.loads(proc.stdout)
    except json.JSONDecodeError as exc:
        return None, fail(f"policy engine returned invalid JSON: {exc}")
    if not isinstance(policy, dict):
        return None, fail("policy engine returned a non-object")
    return policy, 0


def load_questions(
    path: Path,
) -> tuple[list[dict[str, Any]], dict[str, dict[str, Any]], int]:
    doc, err = load_json_file(path)
    if err:
        return [], {}, fail(err)
    if not isinstance(doc, dict):
        return [], {}, fail("questions file must be an object")
    raw = doc.get("questions")
    if not isinstance(raw, list):
        return [], {}, fail("questions file is missing a questions list")
    questions: list[dict[str, Any]] = []
    by_id: dict[str, dict[str, Any]] = {}
    for item in raw:
        if not isinstance(item, dict):
            continue
        qid = item.get("id")
        if not nonempty_str(qid):
            continue
        questions.append(item)
        by_id[str(qid)] = item
    return questions, by_id, 0


def append_field(lines: list[str], label: str, value: Any) -> None:
    if value is None:
        return
    lines.append(f"{label}: {format_value(value)}")


def append_criteria(lines: list[str], criteria: Any) -> None:
    if criteria is None:
        return
    lines.append("criteria:")
    if isinstance(criteria, dict):
        for key, val in criteria.items():
            lines.append(f"  {key}: {format_value(val)}")
        return
    if isinstance(criteria, list):
        for item in criteria:
            lines.append(f"  - {format_value(item)}")
        return
    lines.append(f"  {format_value(criteria)}")


def append_evidence(lines: list[str], evidence: Any) -> None:
    if evidence is None:
        return
    if isinstance(evidence, list):
        lines.append("evidence: " + ", ".join(format_value(item) for item in evidence))
        return
    lines.append(f"evidence: {format_value(evidence)}")


def append_cost(lines: list[str], cost: Any) -> None:
    if cost is None:
        return
    if isinstance(cost, dict):
        parts = [f"{key}={format_value(val)}" for key, val in cost.items()]
        lines.append("cost: " + " ".join(parts))
        return
    lines.append(f"cost: {format_value(cost)}")


def append_action(lines: list[str], rule: dict[str, Any]) -> None:
    action = rule.get("action")
    append_field(lines, "action", action)
    if action in ("INJECT_HINT", "RESET"):
        if "hint" in rule:
            append_field(lines, "hint", rule["hint"])
        return
    if action == "ESCALATE":
        if "pergunta" in rule:
            append_field(lines, "pergunta", rule["pergunta"])
        se = rule.get("se")
        if isinstance(se, list):
            for item in se:
                lines.append(format_value(item))


def format_question(qid: str, question: dict[str, Any], rule: dict[str, Any]) -> list[str]:
    lines = [f"id: {qid}"]
    if "type" in question:
        append_field(lines, "type", question["type"])
    if "instructions" in question:
        append_field(lines, "instructions", question["instructions"])
    append_criteria(lines, question.get("criteria"))
    append_evidence(lines, question.get("evidence"))
    append_cost(lines, question.get("cost"))
    append_action(lines, rule)
    return lines


def render_plan(
    policy_path: str,
    questions_path: str,
    policy: dict[str, Any],
    questions: list[dict[str, Any]],
    by_id: dict[str, dict[str, Any]],
) -> str:
    calibration = policy.get("calibration", {})
    thresholds = policy.get("thresholds") if isinstance(policy.get("thresholds"), dict) else {}
    rules = policy.get("rules") if isinstance(policy.get("rules"), dict) else {}
    lines = [
        f"policy: {policy_path}",
        f"questions: {questions_path}",
    ]
    if policy.get("calibrated"):
        ring = calibration.get("ring", "") if isinstance(calibration, dict) else ""
        lines.append(f"calibration: {ring}")
    else:
        lines.append("calibration: not calibrated: every case will CONTINUE")
    if "act_above" in thresholds:
        lines.append(f"threshold: {format_value(thresholds['act_above'])}")
    lines.append(f"mapped: {len(rules)} of {len(questions)} questions")
    if not rules:
        lines.append("nobody is asked")
        return "\n".join(lines) + "\n"
    for qid, rule in rules.items():
        lines.append("")
        if not isinstance(rule, dict):
            rule = {}
        lines.extend(format_question(str(qid), by_id[str(qid)], rule))
    return "\n".join(lines) + "\n"


def cmd_plan(policy_str: str, questions_str: str, out_path: str | None) -> int:
    policy_path = Path(policy_str)
    questions_path = Path(questions_str)
    policy, rc = validate_via_engine(policy_path)
    if policy is None:
        return rc
    questions, by_id, rc = load_questions(questions_path)
    if rc != 0:
        return rc
    rules = policy.get("rules") if isinstance(policy.get("rules"), dict) else {}
    unknown = [str(qid) for qid in rules if str(qid) not in by_id]
    if unknown:
        for qid in unknown:
            print(f"{PROG}: unknown question id: {qid}", file=sys.stderr)
        return 1
    text = render_plan(policy_str, questions_str, policy, questions, by_id)
    if out_path is not None:
        dest = Path(out_path)
        try:
            dest.write_text(text, encoding="utf-8")
        except OSError as exc:
            return fail(f"cannot write {dest}: {exc}")
    sys.stdout.write(text)
    return 0


def build_parser() -> PlanParser:
    parser = PlanParser(
        prog=PROG,
        description=(
            "Show the supervisor policy as a readable plan. "
            "Does not ask, decide, or connect."
        ),
    )
    parser.add_argument(
        "--policy",
        default=str(DEFAULT_POLICY),
        help="policy JSON (default: the shipped policy in this checkout)",
    )
    parser.add_argument(
        "--questions",
        default=str(DEFAULT_QUESTIONS),
        help="question set JSON (default: the shipped set in this checkout)",
    )
    parser.add_argument(
        "--out",
        default=None,
        help="write the plan (also printed on stdout)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return cmd_plan(args.policy, args.questions, args.out)


if __name__ == "__main__":
    sys.exit(main())
