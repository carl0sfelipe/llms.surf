#!/usr/bin/env python3
"""Traduz NDJSON do cursor-agent --output-format stream-json em eventos oracfit.

Cada linha crua vai ao stdout na hora (sem buffer). Com ORACFIT_RUN_ID, grava
tool_call / thinking / metric em events.jsonl no envelope de lib-oracfit-events.sh.
Sem ORACFIT_RUN_ID, só repassa — não cria arquivo.
"""
import json
import os
import sys
from datetime import datetime, timezone

TOOLCALL_SUFFIX = "ToolCall"
PREVIEW_MAX = 160
DETAIL_MAX = 200


def events_path():
    explicit = os.environ.get("ORACFIT_EVENTS_FILE")
    if explicit:
        return explicit
    workdir = os.environ.get("ORACFIT_WORKDIR", "")
    return os.path.join(workdir, ".dispatch", "logs", "events.jsonl")


def relativize(path, workdir):
    if not path:
        return ""
    if not workdir:
        return path
    try:
        abs_path = os.path.abspath(path)
        abs_wd = os.path.abspath(workdir)
        if os.path.commonpath([abs_path, abs_wd]) == abs_wd:
            return os.path.relpath(abs_path, abs_wd)
    except (ValueError, OSError):
        pass
    return path


def tool_from_payload(payload):
    if not isinstance(payload, dict):
        return None, None
    for key, val in payload.items():
        if isinstance(key, str) and key.endswith(TOOLCALL_SUFFIX) and isinstance(val, dict):
            return key[: -len(TOOLCALL_SUFFIX)].lower(), val
    return None, None


def preview_for(tool, inner, workdir):
    args = inner.get("args") if isinstance(inner, dict) else None
    if not isinstance(args, dict):
        args = {}
    if "path" in args and args["path"] is not None:
        target = relativize(str(args["path"]), workdir)
    elif args.get("command") is not None:
        target = str(args["command"])
    elif args.get("pattern") is not None:
        target = str(args["pattern"])
    elif args.get("query") is not None:
        target = str(args["query"])
    else:
        target = ""
    preview = "[%s] %s" % (tool, target) if target else "[%s]" % tool
    return preview[:PREVIEW_MAX]


class EventWriter:
    def __init__(self, run_id, path):
        self.run_id = run_id
        self.path = path
        self.fp = None

    def emit(self, typ, **fields):
        if not self.run_id:
            return
        if self.fp is None:
            dirname = os.path.dirname(self.path)
            if dirname:
                os.makedirs(dirname, exist_ok=True)
            self.fp = open(self.path, "a", encoding="utf-8")
        obj = {
            "v": 1,
            "ts": datetime.now(timezone.utc).isoformat(),
            "run_id": self.run_id,
            "type": typ,
        }
        obj.update(fields)
        self.fp.write(json.dumps(obj, ensure_ascii=False) + "\n")
        self.fp.flush()

    def close(self):
        if self.fp is not None:
            self.fp.close()
            self.fp = None


def main():
    run_id = os.environ.get("ORACFIT_RUN_ID") or ""
    workdir = os.environ.get("ORACFIT_WORKDIR", "")
    writer = EventWriter(run_id, events_path()) if run_id else None
    stream_bytes = 0
    tool_count = 0
    thinking_buf = []

    try:
        while True:
            line = sys.stdin.readline()
            if line == "":
                break
            sys.stdout.write(line)
            sys.stdout.flush()
            stream_bytes += len(line.encode("utf-8"))
            if not writer:
                continue

            raw = line.rstrip("\n")
            try:
                obj = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue

            typ = obj.get("type")
            subtype = obj.get("subtype")

            if typ == "thinking" and subtype == "delta":
                text = obj.get("text")
                if isinstance(text, str) and text:
                    thinking_buf.append(text)
            elif typ == "thinking" and subtype == "completed":
                detail = "".join(thinking_buf)
                thinking_buf = []
                if detail:
                    writer.emit("thinking", detail=detail[:DETAIL_MAX])
            elif typ == "tool_call" and subtype == "started":
                tool, inner = tool_from_payload(obj.get("tool_call"))
                if not tool:
                    continue
                writer.emit("tool_call", tool=tool, preview=preview_for(tool, inner, workdir))
                tool_count += 1
                if tool_count % 10 == 0:
                    writer.emit("metric", name="context_bytes", value=stream_bytes)
            elif typ == "result":
                usage = obj.get("usage") if isinstance(obj.get("usage"), dict) else {}
                writer.emit(
                    "metric",
                    name="cursor_usage",
                    input_tokens=usage.get("inputTokens", 0),
                    output_tokens=usage.get("outputTokens", 0),
                    cache_read_tokens=usage.get("cacheReadTokens", 0),
                    duration_ms=obj.get("duration_ms", 0),
                )
    finally:
        if writer:
            writer.close()


if __name__ == "__main__":
    main()
