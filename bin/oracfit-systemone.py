#!/usr/bin/env python3
"""oracfit-systemone.py — POST typed questions to a System-One endpoint.

The supervisor adapter: one client, two backends (llama.cpp on CPU, Eikos on
GPU later). The caller passes the endpoint; this program does not choose a
host, a port, or a URL. It asks and prints what came back. It does not decide.
"""
from __future__ import annotations

import argparse
import json
import socket
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_TIMEOUT_S = 30.0
NO_CONFIDENCE = "\u2014"
HTTP_ERROR_PREVIEW = 512


class SystemoneParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        self.print_usage(sys.stderr)
        print(f"oracfit-systemone: {message}", file=sys.stderr)
        raise SystemExit(3)


def fail(message: str, code: int = 1) -> int:
    print(f"oracfit-systemone: {message}", file=sys.stderr)
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


def parse_ids(ids_csv: str) -> tuple[list[str], int]:
    ids = [part.strip() for part in ids_csv.split(",") if part.strip()]
    if not ids:
        return [], fail("--ids is empty", 3)
    return ids, 0


def select_questions(
    questions: dict[str, Any], ids: list[str] | None
) -> tuple[dict[str, Any], int]:
    if ids is None:
        return dict(questions), 0
    unknown = [qid for qid in ids if qid not in questions]
    if unknown:
        joined = ", ".join(unknown)
        return {}, fail(f"unknown id(s): {joined}", 3)
    selected: dict[str, Any] = {}
    for qid in ids:
        selected[qid] = questions[qid]
    return selected, 0


def format_value(value: Any) -> str:
    if isinstance(value, str):
        return value
    return json.dumps(value, ensure_ascii=False)


def answer_value(answer: Any) -> Any:
    if not isinstance(answer, dict):
        return answer
    qtype = answer.get("type")
    if qtype == "noul" or "noul" in answer:
        return answer.get("noul")
    if qtype == "choice" or "choice" in answer:
        return answer.get("choice")
    if qtype == "score" or "score" in answer:
        return answer.get("score")
    return None


def format_line(qid: str, answer: Any) -> str:
    shown = format_value(answer_value(answer))
    if isinstance(answer, dict) and "confidence" in answer:
        detail = format_value(answer["confidence"])
    else:
        detail = NO_CONFIDENCE
    return f"{qid}  {shown}  {detail}"


def is_timeout(exc: BaseException) -> bool:
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return True
    if isinstance(exc, urllib.error.URLError) and isinstance(exc.reason, BaseException):
        return is_timeout(exc.reason)
    return False


def utc_stamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def post_json(endpoint: str, body: dict[str, Any], timeout: float) -> tuple[bytes | None, int]:
    payload = json.dumps(body, ensure_ascii=False).encode("utf-8")
    req = urllib.request.Request(
        endpoint,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # A proxy would take a caller-supplied loopback URL off the box.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    try:
        with opener.open(req, timeout=timeout) as resp:
            status = getattr(resp, "status", None) or resp.getcode()
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        preview = b""
        try:
            preview = (exc.read() or b"")[:HTTP_ERROR_PREVIEW]
        except OSError:
            preview = b""
        text = preview.decode("utf-8", "replace")
        return None, fail(f"HTTP {exc.code}: {text}")
    except (TimeoutError, socket.timeout, urllib.error.URLError, OSError) as exc:
        if is_timeout(exc):
            return None, fail("request exceeded the time ceiling")
        cause: Any = exc.reason if isinstance(exc, urllib.error.URLError) else exc
        return None, fail(str(cause))
    if status is None or status < 200 or status >= 300:
        preview = raw[:HTTP_ERROR_PREVIEW].decode("utf-8", "replace")
        return None, fail(f"HTTP {status}: {preview}")
    return raw, 0


def parse_response(
    raw: bytes, asked_ids: list[str]
) -> tuple[dict[str, Any] | None, Any, int]:
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        return None, None, fail(f"response is not valid JSON: {exc}")
    if not isinstance(data, dict):
        return None, None, fail("response is not an object")
    if "answers" not in data:
        return None, None, fail("response is missing answers")
    answers = data["answers"]
    if not isinstance(answers, dict):
        return None, None, fail("answers is not an object")
    returned = set(answers)
    missing = [qid for qid in asked_ids if qid not in returned]
    extra = [qid for qid in answers if qid not in set(asked_ids)]
    if missing or extra:
        parts: list[str] = []
        if missing:
            parts.append("missing answers for: " + ", ".join(missing))
        if extra:
            parts.append("unexpected answers for: " + ", ".join(extra))
        return None, None, fail("; ".join(parts))
    usage = data["usage"] if "usage" in data else None
    return answers, usage, 0


def cmd_ask(
    endpoint: str,
    questions_path: str,
    state_path: str,
    ids_csv: str | None,
    out_path: str | None,
    timeout: float,
) -> int:
    if timeout <= 0:
        return fail("--timeout must be greater than 0", 3)

    qpath = Path(questions_path)
    questions_doc, err = load_json_file(qpath)
    if err:
        return fail(err)
    if not isinstance(questions_doc, dict) or not isinstance(
        questions_doc.get("questions"), dict
    ):
        return fail("questions file must be an object with a questions object")

    ids: list[str] | None = None
    if ids_csv is not None:
        ids, rc = parse_ids(ids_csv)
        if rc:
            return rc

    selected, rc = select_questions(questions_doc["questions"], ids)
    if rc:
        return rc

    spath = Path(state_path)
    state, err = load_json_file(spath)
    if err:
        return fail(err)

    asked_ids = list(selected)
    body = {"state": state, "questions": selected}
    requested_at = utc_stamp()
    raw, rc = post_json(endpoint, body, timeout)
    if rc:
        return rc
    assert raw is not None
    answers, usage, rc = parse_response(raw, asked_ids)
    if rc:
        return rc
    assert answers is not None

    record = {
        "endpoint": endpoint,
        "requested_at": requested_at,
        "questions": asked_ids,
        "answers": answers,
        "usage": usage,
    }
    if out_path is not None:
        dest = Path(out_path)
        try:
            dest.write_text(
                json.dumps(record, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
        except OSError as exc:
            return fail(f"cannot write {dest}: {exc}")

    for qid in asked_ids:
        sys.stdout.write(format_line(qid, answers[qid]) + "\n")
    return 0


def build_parser() -> SystemoneParser:
    parser = SystemoneParser(
        prog="oracfit-systemone",
        description=(
            "POST typed questions to a System-One endpoint. "
            "Asks and prints the answers. Does not decide."
        ),
    )
    sub = parser.add_subparsers(dest="cmd")
    ask_p = sub.add_parser("ask", help="POST typed questions to a System-One endpoint")
    ask_p.add_argument(
        "--endpoint",
        required=True,
        help="URL of POST /v1/systemone (no default; the caller supplies it)",
    )
    ask_p.add_argument(
        "--questions",
        required=True,
        help="JSON file in the export shape: {\"questions\": {\"<id>\": {...}}}",
    )
    ask_p.add_argument(
        "--state",
        required=True,
        help="JSON file with the round's state, sent as-is",
    )
    ask_p.add_argument(
        "--ids",
        default=None,
        help="comma-separated question ids to ask (default: every id in the file)",
    )
    ask_p.add_argument(
        "--out",
        default=None,
        help="write the audit record (endpoint, requested_at, questions, answers, usage)",
    )
    ask_p.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT_S,
        help=f"time ceiling of the HTTP call, in seconds (default: {int(DEFAULT_TIMEOUT_S)})",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not args.cmd:
        parser.print_usage(sys.stderr)
        print("oracfit-systemone: expected a subcommand", file=sys.stderr)
        return 3
    if args.cmd == "ask":
        return cmd_ask(
            args.endpoint,
            args.questions,
            args.state,
            args.ids,
            args.out,
            args.timeout,
        )
    parser.print_usage(sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
