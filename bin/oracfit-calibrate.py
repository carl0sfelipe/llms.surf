#!/usr/bin/env python3
"""oracfit-calibrate.py — write a calibrated policy from a scored ring.

Reads the ring ledger at the target, copies the measured calibration line
from the owner's score event, and writes a new policy file. The source
policy is not written. The threshold is the number the owner passes; this
command does not measure it and does not invent it.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any

PROG = "oracfit-calibrate"
DEFAULT_RING_DIR = "ring"
LEDGER_NAME = "ledger.jsonl"


class CalibrateParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"{PROG}: {message}", file=sys.stderr)
        raise SystemExit(3)


def fail(message: str, code: int = 1) -> int:
    print(f"{PROG}: {message}", file=sys.stderr)
    return code


def load_json_file(path: Path) -> tuple[Any, str | None]:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, f"cannot read {path}: {exc}"
    try:
        return json.loads(text), None
    except json.JSONDecodeError as exc:
        return None, f"not valid JSON: {exc}"


def ring_dir_name() -> str:
    return os.environ.get("ORACFIT_RING_DIR") or DEFAULT_RING_DIR


def ledger_path(target: Path) -> Path:
    return target / ring_dir_name() / LEDGER_NAME


def last_owner_score(path: Path, ring: str) -> dict[str, Any] | None:
    found: dict[str, Any] | None = None
    try:
        fh = path.open(encoding="utf-8")
    except OSError:
        return None
    with fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict):
                continue
            if event.get("event") == "owner_score" and event.get("ring") == ring:
                found = event
    return found


def same_file(left: Path, right: Path) -> bool:
    try:
        return left.resolve() == right.resolve()
    except OSError:
        return False


def write_policy(path: Path, doc: dict[str, Any]) -> str | None:
    text = json.dumps(doc, ensure_ascii=False, indent=2) + "\n"
    tmp = path.with_name(path.name + ".tmp")
    try:
        tmp.write_text(text, encoding="utf-8")
        os.replace(tmp, path)
    except OSError as exc:
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return f"cannot write {path}: {exc}"
    return None


def cmd_calibrate(
    ring: str,
    target_str: str,
    policy_str: str,
    act_above: float,
    out_str: str,
) -> int:
    if not ring.strip():
        return fail("ring id is empty", 3)

    target = Path(target_str)
    if not target.is_dir():
        return fail(f"target is not a directory: {target}")

    ledger = ledger_path(target)
    event = last_owner_score(ledger, ring)
    if event is None:
        return fail(f"no owner_score event for ring {ring} in {ledger}")

    calibration_line = event.get("calibration_line")
    if not isinstance(calibration_line, str) or not calibration_line.strip():
        return fail(f"owner_score for ring {ring} has no calibration line")

    if not (0.0 <= act_above <= 1.0):
        return fail("act_above must be a number between 0 and 1")

    policy_path = Path(policy_str)
    out_path = Path(out_str)
    if same_file(policy_path, out_path):
        return fail("--out must be a new file; refusing to write the source policy")

    source, err = load_json_file(policy_path)
    if err:
        return fail(err)
    if not isinstance(source, dict):
        return fail("policy must be an object")

    rules = source["rules"] if "rules" in source else {}
    calibrated = {
        "version": source.get("version"),
        "calibration": {"ring": ring, "line": calibration_line},
        "thresholds": {"act_above": float(act_above)},
        "rules": rules,
    }
    err = write_policy(out_path, calibrated)
    if err:
        return fail(err)
    return 0


def build_parser() -> CalibrateParser:
    parser = CalibrateParser(
        prog=PROG,
        description=(
            "Copy a scored ring's calibration line into a new policy file. "
            "Does not write the source policy and does not choose the threshold."
        ),
    )
    parser.add_argument("--ring", required=True, help="ring id (the same id score receives)")
    parser.add_argument("--target", required=True, help="ring target directory")
    parser.add_argument("--policy", required=True, help="source policy JSON (not written)")
    parser.add_argument(
        "--act-above",
        required=True,
        type=float,
        help="owner threshold in 0..1 (required; not measured)",
    )
    parser.add_argument("--out", required=True, help="calibrated policy JSON (a new file)")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return cmd_calibrate(args.ring, args.target, args.policy, args.act_above, args.out)


if __name__ == "__main__":
    sys.exit(main())
