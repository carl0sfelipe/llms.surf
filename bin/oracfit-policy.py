#!/usr/bin/env python3
"""oracfit-policy.py — turn typed answers into one supervisor order.

Reads a System-One answers record and a policy file, then writes a decision
record: CONTINUE, INJECT_HINT, RESET, or ESCALATE. It does not inject a hint,
restore a tree, snapshot, pause a run, or call git. The policy writes the
order; the runtime is who executes it.

The validate subcommand checks a policy without answers and without deciding.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

ACTIONS = ("CONTINUE", "INJECT_HINT", "RESET", "ESCALATE")
RANK = {"ESCALATE": 3, "RESET": 2, "INJECT_HINT": 1}
KIND_WORD = {"noul": "mass", "choice": "confidence", "score": "score"}
CONSEQUENCE_RE = re.compile(r"^se .+ -> .+$")
PROG = "oracfit-policy"


class PolicyParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"{PROG}: {message}", file=sys.stderr)
        raise SystemExit(3)


def fail(message: str, code: int = 1) -> int:
    print(f"{PROG}: {message}", file=sys.stderr)
    return code


def is_int(value: Any) -> bool:
    return isinstance(value, int) and not isinstance(value, bool)


def is_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


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


def format_trigger(value: float) -> str:
    text = f"{value:.10f}".rstrip("0").rstrip(".")
    if "." not in text:
        text += ".0"
    return text


def continue_record(reason: str) -> dict[str, Any]:
    return {
        "decision": "CONTINUE",
        "reason": reason,
        "order": {
            "action": "CONTINUE",
            "question_id": "",
            "value": 0.0,
        },
    }


def as_number(value: Any) -> float | None:
    if not is_number(value):
        return None
    return float(value)


def trigger_value(answer: Any) -> tuple[float | None, str]:
    """Return (value, kind) for a raw System-One answer, or (None, "") if it cannot fire."""
    if not isinstance(answer, dict):
        return None, ""
    qtype = answer.get("type")
    if qtype == "noul" or (qtype is None and "noul" in answer):
        return as_number(answer.get("noul")), "noul"
    if qtype == "choice" or (qtype is None and "confidence" in answer):
        return as_number(answer.get("confidence")), "choice"
    if qtype == "score" or (qtype is None and "score" in answer):
        return as_number(answer.get("score")), "score"
    return None, ""


def consequence_ok(item: Any) -> bool:
    return isinstance(item, str) and bool(CONSEQUENCE_RE.match(item.strip()))


def validate_rule(qid: str, raw: Any) -> tuple[dict[str, Any] | None, list[str]]:
    prefix = f"rules.{qid}"
    if not isinstance(raw, dict):
        return None, [f"{prefix} must be an object"]
    errors: list[str] = []
    action = raw.get("action")
    if action not in ACTIONS:
        errors.append(
            f"{prefix} action must be one of {', '.join(ACTIONS)}"
        )
        return None, errors
    rule: dict[str, Any] = {"action": action}
    if action in ("INJECT_HINT", "RESET"):
        hint = raw.get("hint")
        if not nonempty_str(hint):
            errors.append(f"{prefix} {action} needs a non-empty hint")
        else:
            rule["hint"] = hint.strip()
    elif action == "ESCALATE":
        pergunta = raw.get("pergunta")
        if not nonempty_str(pergunta):
            errors.append(f"{prefix} ESCALATE needs a non-empty pergunta")
        else:
            rule["pergunta"] = pergunta.strip()
        se = raw.get("se")
        if not isinstance(se, list) or len(se) < 2:
            errors.append(
                f"{prefix} ESCALATE needs at least two se consequences "
                "in the form 'se <answer> -> <what you do>'"
            )
        else:
            bad = [i for i, item in enumerate(se) if not consequence_ok(item)]
            if bad:
                errors.append(
                    f"{prefix} ESCALATE se entries must match "
                    "'se <answer> -> <what you do>'"
                )
            else:
                rule["se"] = [item.strip() for item in se]
    if errors:
        return None, errors
    return rule, []


def is_calibrated(calibration: dict[str, str]) -> bool:
    return bool(calibration.get("ring", "").strip() and calibration.get("line", "").strip())


def validate_policy(doc: Any) -> tuple[dict[str, Any] | None, list[str]]:
    if not isinstance(doc, dict):
        return None, ["policy must be an object"]
    errors: list[str] = []
    version = doc.get("version")
    if not is_int(version):
        errors.append("version must be an integer")

    thresholds = doc.get("thresholds")
    act_above: float | None = None
    if not isinstance(thresholds, dict):
        errors.append("thresholds must be an object")
    else:
        raw_above = thresholds.get("act_above")
        if not is_number(raw_above):
            errors.append("thresholds.act_above must be a number between 0 and 1")
        else:
            act_above = float(raw_above)
            if act_above < 0 or act_above > 1:
                errors.append("thresholds.act_above must be a number between 0 and 1")

    calibration_in = doc.get("calibration", {})
    ring = ""
    line = ""
    if "calibration" in doc and not isinstance(calibration_in, dict):
        errors.append("calibration must be an object")
    elif isinstance(calibration_in, dict):
        if "ring" in calibration_in and not isinstance(calibration_in["ring"], str):
            errors.append("calibration.ring must be a string")
        else:
            ring = calibration_in.get("ring", "")
            if not isinstance(ring, str):
                ring = ""
        if "line" in calibration_in and not isinstance(calibration_in["line"], str):
            errors.append("calibration.line must be a string")
        else:
            line = calibration_in.get("line", "")
            if not isinstance(line, str):
                line = ""

    rules_in = doc.get("rules", {})
    rules: dict[str, dict[str, Any]] = {}
    if "rules" in doc and not isinstance(rules_in, dict):
        errors.append("rules must be an object")
    elif isinstance(rules_in, dict):
        for qid, raw in rules_in.items():
            rule, rule_errors = validate_rule(str(qid), raw)
            errors.extend(rule_errors)
            if rule is not None:
                rules[str(qid)] = rule

    if errors:
        return None, errors
    assert act_above is not None
    calibration = {"ring": ring, "line": line}
    return {
        "version": version,
        "calibration": calibration,
        "calibrated": is_calibrated(calibration),
        "thresholds": {"act_above": act_above},
        "rules": rules,
    }, []


def decide(answers: dict[str, Any], policy: dict[str, Any]) -> dict[str, Any]:
    if not is_calibrated(policy["calibration"]):
        return continue_record("not calibrated")
    act_above = policy["thresholds"]["act_above"]
    rules: dict[str, dict[str, Any]] = policy["rules"]
    fired: list[tuple[int, float, str, str, dict[str, Any]]] = []
    for qid, answer in answers.items():
        rule = rules.get(qid)
        if rule is None:
            continue
        action = rule["action"]
        rank = RANK.get(action)
        if rank is None:
            continue
        value, kind = trigger_value(answer)
        if value is None or kind == "":
            continue
        if value < act_above:
            continue
        fired.append((rank, value, qid, kind, rule))
    if not fired:
        return continue_record("no rule fired")
    fired.sort(key=lambda row: (-row[0], -row[1]))
    _rank, value, qid, kind, rule = fired[0]
    action = rule["action"]
    reason = f"{qid} fired with {KIND_WORD[kind]} {format_trigger(value)}"
    order: dict[str, Any] = {
        "action": action,
        "question_id": qid,
        "value": float(value),
    }
    if action in ("INJECT_HINT", "RESET"):
        order["hint"] = rule["hint"]
    elif action == "ESCALATE":
        order["pergunta"] = rule["pergunta"]
        order["se"] = list(rule["se"])
    return {"decision": action, "reason": reason, "order": order}


def dump_record(record: dict[str, Any]) -> str:
    return json.dumps(record, ensure_ascii=False, indent=2) + "\n"


def cmd_decide(
    answers_path: str,
    policy_path: str,
    state_path: str | None,
    out_path: str | None,
) -> int:
    answers_doc, err = load_json_file(Path(answers_path))
    if err:
        return fail(err)
    policy_doc, err = load_json_file(Path(policy_path))
    if err:
        return fail(err)
    if state_path is not None:
        _state, err = load_json_file(Path(state_path))
        if err:
            return fail(err)

    policy, errors = validate_policy(policy_doc)
    if errors:
        for message in errors:
            print(f"{PROG}: {message}", file=sys.stderr)
        return 1

    if not isinstance(answers_doc, dict):
        return fail("answers file must be an object")
    answers = answers_doc.get("answers")
    if not isinstance(answers, dict):
        return fail("answers file is missing an answers object")

    record = decide(answers, policy)
    text = dump_record(record)
    if out_path is not None:
        dest = Path(out_path)
        try:
            dest.write_text(text, encoding="utf-8")
        except OSError as exc:
            return fail(f"cannot write {dest}: {exc}")
    sys.stdout.write(text)
    return 0


def cmd_validate(policy_path: str, out_path: str | None) -> int:
    policy_doc, err = load_json_file(Path(policy_path))
    if err:
        return fail(err)
    policy, errors = validate_policy(policy_doc)
    if errors:
        for message in errors:
            print(f"{PROG}: {message}", file=sys.stderr)
        return 1
    text = dump_record(policy)
    if out_path is not None:
        dest = Path(out_path)
        try:
            dest.write_text(text, encoding="utf-8")
        except OSError as exc:
            return fail(f"cannot write {dest}: {exc}")
    sys.stdout.write(text)
    return 0


def build_parser() -> PolicyParser:
    parser = PolicyParser(
        prog=PROG,
        description=(
            "Read typed answers and a policy, write one order. "
            "Does not inject, restore, snapshot, or pause."
        ),
    )
    sub = parser.add_subparsers(dest="cmd")
    decide_p = sub.add_parser("decide", help="write one CONTINUE / INJECT_HINT / RESET / ESCALATE order")
    decide_p.add_argument("--answers", required=True, help="System-One answers record (rung H output)")
    decide_p.add_argument("--policy", required=True, help="policy JSON")
    decide_p.add_argument(
        "--state",
        default=None,
        help="round state JSON; read and not interpreted",
    )
    decide_p.add_argument(
        "--out",
        default=None,
        help="write the decision record (also printed on stdout)",
    )
    validate_p = sub.add_parser(
        "validate",
        help="validate a policy without answers and without deciding",
    )
    validate_p.add_argument("--policy", required=True, help="policy JSON")
    validate_p.add_argument(
        "--out",
        default=None,
        help="write the normalized policy (also printed on stdout)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        print(f"{PROG}: expected a subcommand", file=sys.stderr)
        return 3
    if args.cmd == "decide":
        return cmd_decide(args.answers, args.policy, args.state, args.out)
    if args.cmd == "validate":
        return cmd_validate(args.policy, args.out)
    parser.print_usage(sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
