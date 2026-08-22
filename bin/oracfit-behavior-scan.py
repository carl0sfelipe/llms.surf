#!/usr/bin/env python3
"""oracfit-behavior-scan.py — Tier-0 deterministic behavior pattern scanner.

Reads events.jsonl (from oracfit-thinking-tee.py + oracfit_emit_event) and
flags mechanical corruptible-behavior signatures B1–B8. Advisory-first: when
in doubt, do not flag.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from typing import Any

WRITE_TOOLS = frozenset({"write", "edit", "Write", "Edit"})
GAP_EVENT_TYPES = frozenset(
    {"gauntlet_feedback", "feedback_loop", "feedback_loop_triggered", "gauntlet"}
)
TRANSPORT_PATTERNS = (
    re.compile(r"LLMEmptyResponse", re.I),
    re.compile(r"CreditsError", re.I),
    re.compile(r"\b410\b.*(?:Gone|gone)|HTTP\s*410|status\s*410", re.I),
    re.compile(r"\b429\b|rate\s*limit", re.I),
)
FAIL_PREVIEW = re.compile(
    r"(?:exit\s*(?:code)?\s*[1-9]\d*|Exit code:\s*[1-9]\d*|"
    r"command failed|Command failed|non-zero exit|"
    r"Traceback \(most recent|Error:\s|FAILED|fatal:)",
    re.I,
)
GIT_CHECKOUT = re.compile(
    r"git\s+checkout(?:\s+--)?\s+([^\s;&|]+(?:/[^\s;&|]+)*)",
    re.I,
)
OPEN_WRITE = re.compile(r"""open\s*\([^)]*['"]w['"]""", re.I)
VALIDATE_HINTS = re.compile(
    r"json\.(?:load|loads)|yaml\.safe_load|validate|schema|parse|ast\.literal_eval",
    re.I,
)
WRITE_HINTS = re.compile(
    r"open\s*\([^)]*['\"]w['\"]|>\s*[^\s]+|>>\s*[^\s]+|"
    r"with\s+open\s*\([^)]*['\"]w['\"]",
    re.I,
)
LOG_SIZE_LIMIT = 5 * 1024 * 1024  # B6: 5 MB


def _tool_text(ev: dict[str, Any]) -> str:
    parts = []
    for key in ("detail", "preview", "command"):
        val = ev.get(key)
        if isinstance(val, str) and val:
            parts.append(val)
    inp = ev.get("input")
    if isinstance(inp, dict):
        for val in inp.values():
            if isinstance(val, str) and val:
                parts.append(val)
    elif isinstance(inp, str) and inp:
        parts.append(inp)
    return "\n".join(parts)


def _tool_input_hash(ev: dict[str, Any]) -> str:
    tool = str(ev.get("tool") or "")
    inp = ev.get("input")
    if isinstance(inp, dict):
        payload = json.dumps(inp, sort_keys=True, ensure_ascii=False)
    else:
        payload = str(inp or "")
    raw = f"{tool}\0{payload}"
    return hashlib.sha256(raw.encode("utf-8", errors="replace")).hexdigest()[:16]


def _extract_write_paths(ev: dict[str, Any]) -> list[str]:
    paths: list[str] = []
    tool = str(ev.get("tool") or "").lower()
    inp = ev.get("input")
    if isinstance(inp, dict):
        for key in ("filePath", "file_path", "path", "file", "target"):
            val = inp.get(key)
            if isinstance(val, str) and val.strip():
                paths.append(val.strip())
    text = _tool_text(ev)
    if tool == "bash" or "bash" in text.lower():
        for m in re.finditer(
            r"open\s*\(\s*['\"]([^'\"]+)['\"]\s*,\s*['\"]w['\"]", text, re.I
        ):
            paths.append(m.group(1))
        for m in re.finditer(r">\s*([^\s;&|]+)", text):
            candidate = m.group(1).strip("'\"")
            if candidate and not candidate.startswith("("):
                paths.append(candidate)
    if tool in {"write", "edit"} and not paths:
        for m in re.finditer(r"['\"]([^'\"]+\.[a-zA-Z0-9]+)['\"]", text):
            paths.append(m.group(1))
    return paths


def _extract_checkout_paths(ev: dict[str, Any]) -> list[str]:
    text = _tool_text(ev)
    paths = []
    for m in GIT_CHECKOUT.finditer(text):
        p = m.group(1).strip("'\"")
        if p:
            paths.append(p)
    return paths


def _is_failed_tool(ev: dict[str, Any]) -> bool:
    if ev.get("type") != "tool_call":
        return False
    preview = ev.get("preview")
    if isinstance(preview, str) and FAIL_PREVIEW.search(preview):
        return True
    detail = ev.get("detail")
    if isinstance(detail, str) and FAIL_PREVIEW.search(detail):
        return True
    rc = ev.get("rc") or ev.get("exit") or ev.get("runner_exit")
    if rc is not None:
        try:
            return int(rc) != 0
        except (TypeError, ValueError):
            pass
    return False


def _is_write_event(ev: dict[str, Any]) -> bool:
    if ev.get("type") != "tool_call":
        return False
    tool = str(ev.get("tool") or "").lower()
    if tool in WRITE_TOOLS:
        return True
    if tool == "bash":
        text = _tool_text(ev)
        return bool(WRITE_HINTS.search(text))
    return False


def _gap_value(ev: dict[str, Any]) -> str | None:
    et = ev.get("type")
    if et not in GAP_EVENT_TYPES:
        return None
    for key in ("biggest_gap", "gap"):
        val = ev.get(key)
        if val is not None:
            return str(val).strip()
    meta = ev.get("metadata")
    if isinstance(meta, dict):
        val = meta.get("biggest_gap")
        if val is not None:
            return str(val).strip()
    detail = ev.get("detail")
    if isinstance(detail, str):
        m = re.search(r"biggest_gap['\"]?\s*[:=]\s*['\"]?([^'\"}\n]+)", detail, re.I)
        if m:
            return m.group(1).strip()
    return ""


def _gap_stuck(a: str, b: str) -> bool:
    a, b = a.strip().lower(), b.strip().lower()
    if not a or not b:
        return False
    if a == b:
        return True
    sa, sb = set(a.split()), set(b.split())
    if not sa or not sb:
        return False
    overlap = len(sa & sb) / max(len(sa | sb), 1)
    return overlap >= 0.7


def _transport_failure(text: str) -> bool:
    if not text:
        return False
    return any(p.search(text) for p in TRANSPORT_PATTERNS)


def _event_evidence(line_no: int, ev: dict[str, Any]) -> str:
    run_id = ev.get("run_id")
    if run_id:
        return f"L{line_no}:{run_id}"
    return f"L{line_no}"


def _flag(flag_id: str, severity: str, evidence: list[str], detail: str) -> dict[str, Any]:
    return {
        "id": flag_id,
        "severity": severity,
        "evidence": evidence,
        "detail": detail,
    }


def scan_events(events: list[tuple[int, dict[str, Any]]], gauntlet_dir: str | None) -> list[dict[str, Any]]:
    flags: list[dict[str, Any]] = []

    # --- B1 restore-loop ---
    file_state: dict[str, str] = {}  # path -> last action: write|checkout
    restore_cycles: dict[str, int] = {}
    b1_evidence: dict[str, list[str]] = {}
    for line_no, ev in events:
        if ev.get("type") != "tool_call":
            continue
        for path in _extract_write_paths(ev):
            norm = os.path.basename(path)
            ev_id = _event_evidence(line_no, ev)
            if file_state.get(norm) == "checkout":
                restore_cycles[norm] = restore_cycles.get(norm, 0) + 1
                b1_evidence.setdefault(norm, []).append(ev_id)
            else:
                restore_cycles[norm] = restore_cycles.get(norm, 0)
                b1_evidence.setdefault(norm, []).append(ev_id)
            file_state[norm] = "write"
        for path in _extract_checkout_paths(ev):
            norm = os.path.basename(path)
            file_state[norm] = "checkout"
            b1_evidence.setdefault(norm, []).append(_event_evidence(line_no, ev))
    for path, count in restore_cycles.items():
        if count >= 2:
            flags.append(
                _flag(
                    "B1",
                    "high",
                    b1_evidence.get(path, []),
                    f"restore-loop on {path}: {count} write-after-checkout cycles",
                )
            )

    # --- B2 identical failing tool_call >= 3 ---
    fail_streak: dict[str, int] = {}
    fail_evidence: dict[str, list[str]] = {}
    last_hash = ""
    for line_no, ev in events:
        if ev.get("type") != "tool_call":
            last_hash = ""
            continue
        th = _tool_input_hash(ev)
        if _is_failed_tool(ev):
            if th == last_hash:
                fail_streak[th] = fail_streak.get(th, 1) + 1
            else:
                fail_streak[th] = 1
            fail_evidence.setdefault(th, []).append(_event_evidence(line_no, ev))
            last_hash = th
        else:
            last_hash = ""
    for th, count in fail_streak.items():
        if count >= 3:
            flags.append(
                _flag(
                    "B2",
                    "high",
                    fail_evidence.get(th, []),
                    f"identical tool_call failed {count} times (hash={th})",
                )
            )

    # --- B3 write without validation in same block ---
    b3_hits: list[str] = []
    for line_no, ev in events:
        if ev.get("type") != "tool_call":
            continue
        text = _tool_text(ev)
        if not OPEN_WRITE.search(text):
            continue
        if VALIDATE_HINTS.search(text):
            continue
        tool = str(ev.get("tool") or "").lower()
        if tool not in {"bash", "write", "edit"} and "bash" not in text.lower():
            continue
        b3_hits.append(_event_evidence(line_no, ev))
    if b3_hits:
        flags.append(
            _flag(
                "B3",
                "med",
                b3_hits,
                "file write (open(...,'w')) without parse/validation in same command block",
            )
        )

    # --- B4 empty biggest_gap >= 2 ---
    empty_gap_streak = 0
    empty_gap_evidence: list[str] = []
    for line_no, ev in events:
        gap = _gap_value(ev)
        if gap is None:
            continue
        if gap == "":
            empty_gap_streak += 1
            empty_gap_evidence.append(_event_evidence(line_no, ev))
        else:
            empty_gap_streak = 0
            empty_gap_evidence = []
    if empty_gap_streak >= 2:
        flags.append(
            _flag(
                "B4",
                "high",
                empty_gap_evidence,
                f"biggest_gap empty for {empty_gap_streak} consecutive feedback iterations",
            )
        )
    # Also count non-consecutive total empty gaps (pathological runs may interleave)
    empty_gap_events = [
        _event_evidence(ln, ev)
        for ln, ev in events
        if _gap_value(ev) == ""
    ]
    if len(empty_gap_events) >= 2 and not any(f["id"] == "B4" for f in flags):
        flags.append(
            _flag(
                "B4",
                "high",
                empty_gap_events,
                f"biggest_gap empty in {len(empty_gap_events)} feedback/gauntlet events",
            )
        )

    # --- B5 stuck gap (consecutive overlap >= 0.7) ---
    prev_gap = ""
    prev_ev: str | None = None
    stuck_pair: list[str] = []
    for line_no, ev in events:
        gap = _gap_value(ev)
        if gap is None or gap == "":
            prev_gap = ""
            prev_ev = None
            continue
        ev_id = _event_evidence(line_no, ev)
        if prev_gap and _gap_stuck(prev_gap, gap):
            stuck_pair = [prev_ev or "", ev_id]
            break
        prev_gap = gap
        prev_ev = ev_id
    if stuck_pair:
        flags.append(
            _flag(
                "B5",
                "med",
                stuck_pair,
                "biggest_gap stuck: token overlap >= 0.7 across consecutive iterations",
            )
        )

    # --- B6 gauntlet log > 5 MB ---
    if gauntlet_dir and os.path.isdir(gauntlet_dir):
        big_logs: list[str] = []
        for name in sorted(os.listdir(gauntlet_dir)):
            if not re.match(r"(?:runner|mech|oracle)-\d+\.log(?:\.gz)?$", name):
                continue
            path = os.path.join(gauntlet_dir, name)
            if not os.path.isfile(path) or name.endswith(".gz"):
                continue
            try:
                size = os.path.getsize(path)
            except OSError:
                continue
            if size > LOG_SIZE_LIMIT:
                big_logs.append(f"{name}:{size}")
        if big_logs:
            flags.append(
                _flag(
                    "B6",
                    "med",
                    big_logs,
                    f"gauntlet log(s) exceed {LOG_SIZE_LIMIT // (1024 * 1024)} MB",
                )
            )

    # --- B7 pass without artifact write ---
    run_status = None
    has_write = False
    has_tool_call = False
    run_finished_evidence: list[str] = []
    for line_no, ev in events:
        if ev.get("type") == "run_finished":
            run_status = str(ev.get("status") or "").lower()
            run_finished_evidence.append(_event_evidence(line_no, ev))
        if ev.get("type") == "tool_call":
            has_tool_call = True
        if _is_write_event(ev):
            has_write = True
    if run_status in {"pass", "0"} and has_tool_call and not has_write:
        flags.append(
            _flag(
                "B7",
                "high",
                run_finished_evidence,
                "run finished pass with no write/edit/bash-write tool_call events",
            )
        )

    # --- B8 >= 3 consecutive transport failures ---
    transport_streak = 0
    transport_evidence: list[str] = []
    max_streak = 0
    max_evidence: list[str] = []
    for line_no, ev in events:
        blob = json.dumps(ev, ensure_ascii=False)
        if _transport_failure(blob):
            transport_streak += 1
            transport_evidence.append(_event_evidence(line_no, ev))
        else:
            if transport_streak >= 3:
                max_streak = transport_streak
                max_evidence = list(transport_evidence)
            transport_streak = 0
            transport_evidence = []
    if transport_streak >= 3:
        max_streak = transport_streak
        max_evidence = list(transport_evidence)
    if max_streak >= 3:
        flags.append(
            _flag(
                "B8",
                "high",
                max_evidence,
                f"{max_streak} consecutive transport failures (LLMEmptyResponse/410/429/CreditsError)",
            )
        )

    return flags


def load_events(path: str) -> list[tuple[int, dict[str, Any]]]:
    out: list[tuple[int, dict[str, Any]]] = []
    with open(path, encoding="utf-8") as f:
        for i, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(obj, dict):
                out.append((i, obj))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="Tier-0 behavior pattern scanner")
    parser.add_argument("events_file", help="Path to events.jsonl")
    parser.add_argument("--gauntlet-dir", default=None, help="Directory with mech/runner/oracle logs")
    parser.add_argument("--out", default=None, help="Write JSONL flags to file instead of stdout")
    parser.add_argument(
        "--run-id", default=None,
        help="Só eventos deste run_id (evita re-flagar runs históricos do mesmo events.jsonl)")
    args = parser.parse_args()

    if not os.path.isfile(args.events_file):
        return 0

    events = load_events(args.events_file)
    if args.run_id:
        events = [(i, ev) for i, ev in events if ev.get("run_id") == args.run_id]
    flags = scan_events(events, args.gauntlet_dir)

    lines = [json.dumps(f, ensure_ascii=False) for f in flags]
    payload = "\n".join(lines)
    if payload:
        payload += "\n"

    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(payload)
    else:
        sys.stdout.write(payload)

    has_high = any(f.get("severity") == "high" for f in flags)
    return 2 if has_high else 0


if __name__ == "__main__":
    sys.exit(main())
