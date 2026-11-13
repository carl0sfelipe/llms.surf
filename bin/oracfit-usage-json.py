#!/usr/bin/env python3
"""oracfit-usage-json.py — JSON rules for Oracfit usage.jsonl.

Subcommands:
  extra <text>     object for the extra slot (never raw caller text)
  number <text>    JSON integer, or null
  check            validate one stdin line as a JSON object
  repair <file>    repair a usage.jsonl base without dropping rows silently

Exit: 0 ok · 2 payload/line did not parse · 3 usage error
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any


class UsageParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"oracfit-usage-json: {message}", file=sys.stderr)
        raise SystemExit(3)


def coerce_extra(text: str) -> str:
    """Return JSON text for the extra slot: always a JSON object."""
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return json.dumps({"raw": text}, ensure_ascii=False)
    if isinstance(value, dict):
        return text.strip()
    return json.dumps({"raw": text}, ensure_ascii=False)


def coerce_number(text: str) -> str:
    """Return a JSON integer token, or null when text is not a JSON integer."""
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return "null"
    if isinstance(value, bool) or not isinstance(value, int):
        return "null"
    return json.dumps(value)


def parse_object(text: str) -> Any | None:
    try:
        value = json.loads(text)
    except json.JSONDecodeError:
        return None
    if isinstance(value, dict):
        return value
    return None


def first_complete_value_end(text: str) -> tuple[Any, int] | None:
    """Index after the first complete top-level JSON value.

    Uses the stdlib decoder so strings and escapes are respected: a cut
    cannot land inside a quoted string.
    """
    decoder = json.JSONDecoder()
    try:
        value, end = decoder.raw_decode(text)
    except json.JSONDecodeError:
        return None
    return value, end


def line_ending(line: str) -> str:
    if line.endswith("\r\n"):
        return "\r\n"
    if line.endswith("\n"):
        return "\n"
    if line.endswith("\r"):
        return "\r"
    return ""


def try_repair_extra_data(line: str) -> str | None:
    """Cut at the first complete top-level object when leftover data follows.

    Only the extra-data class (the leftover-brace shape) is repaired.
    Truncated lines and non-object first values are not.
    """
    scanned = first_complete_value_end(line)
    if scanned is None:
        return None
    value, end = scanned
    remainder = line[end:]
    if remainder.strip() == "":
        return None
    if not isinstance(value, dict):
        return None
    cut = line[:end]
    if parse_object(cut) is None:
        return None
    return cut


def cmd_extra(text: str) -> int:
    print(coerce_extra(text))
    return 0


def cmd_number(text: str) -> int:
    print(coerce_number(text))
    return 0


def cmd_check() -> int:
    line = sys.stdin.readline()
    try:
        value = json.loads(line)
    except json.JSONDecodeError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    if not isinstance(value, dict):
        print("not a JSON object", file=sys.stderr)
        return 2
    return 0


def cmd_repair(path_str: str, in_place: bool, out_str: str | None) -> int:
    path = Path(path_str)
    if in_place and out_str is not None:
        print("oracfit-usage-json: use only one of --in-place and --out", file=sys.stderr)
        return 3
    if not path.is_file():
        print(f"oracfit-usage-json: file not found: {path}", file=sys.stderr)
        return 3

    if in_place:
        out_path = path
    elif out_str is not None:
        out_path = Path(out_str)
    else:
        out_path = Path(str(path) + ".repaired")
    unrecoverable_path = Path(str(path) + ".unrecoverable")

    with path.open("r", encoding="utf-8", newline="") as fh:
        lines = fh.readlines()

    out_lines: list[str] = []
    unrecoverable: list[str] = []
    parsed = 0
    repaired = 0
    for line in lines:
        if parse_object(line) is not None:
            out_lines.append(line)
            parsed += 1
            continue
        cut = try_repair_extra_data(line)
        if cut is not None:
            ending = line_ending(line) or "\n"
            out_lines.append(cut + ending)
            repaired += 1
            continue
        unrecoverable.append(line if line.endswith(("\n", "\r")) else line + "\n")

    if in_place:
        shutil.copy2(path, Path(str(path) + ".bak"))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", encoding="utf-8", newline="") as fh:
        fh.writelines(out_lines)

    if unrecoverable:
        with unrecoverable_path.open("w", encoding="utf-8", newline="") as fh:
            fh.writelines(unrecoverable)
    elif unrecoverable_path.exists() and unrecoverable_path.resolve() != path.resolve():
        unrecoverable_path.unlink()

    total = len(lines)
    n_unrec = len(unrecoverable)
    print(
        f"total={total} parsed={parsed} repaired={repaired} unrecoverable={n_unrec}"
    )
    return 0


def build_parser() -> UsageParser:
    parser = UsageParser(
        prog="oracfit-usage-json",
        description="JSON rules for the extra slot, numeric slots, line check and base repair.",
    )
    sub = parser.add_subparsers(dest="cmd")

    extra_p = sub.add_parser("extra", help="JSON object for the extra slot")
    extra_p.add_argument("text", help="caller payload")

    number_p = sub.add_parser("number", help="JSON integer or null")
    number_p.add_argument("text", help="caller payload")

    sub.add_parser("check", help="validate one stdin line as a JSON object")

    repair_p = sub.add_parser("repair", help="repair a usage.jsonl file")
    repair_p.add_argument("file", help="usage.jsonl path")
    repair_p.add_argument("--in-place", action="store_true", help="overwrite FILE after copying FILE.bak")
    repair_p.add_argument("--out", dest="out", help="write repaired rows here")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        print("oracfit-usage-json: expected a subcommand", file=sys.stderr)
        return 3
    if args.cmd == "extra":
        return cmd_extra(args.text)
    if args.cmd == "number":
        return cmd_number(args.text)
    if args.cmd == "check":
        return cmd_check()
    if args.cmd == "repair":
        return cmd_repair(args.file, args.in_place, args.out)
    parser.print_usage(sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
