#!/usr/bin/env python3
"""Extract session_id and token usage from a run log.

Usage:
    lib-oracfit-session-facts.py <log_file>

Reads the file line by line (never the whole file at once). Each JSON object
with type "result" and a string session_id replaces the stored facts; the last
such event wins. Usage keys inputTokens, outputTokens, cacheReadTokens and
cacheWriteTokens become integers (missing or non-numeric = 0).

Always prints one JSON object and exits 0. A missing log, an empty log, a
log from another CLI, or a malformed line yields empty facts (session_id ""
and four zeros) rather than a non-zero exit.
"""

import json
import sys


EMPTY = {
    "session_id": "",
    "tokens_input": 0,
    "tokens_output": 0,
    "tokens_cache_read": 0,
    "tokens_cache_write": 0,
}


def token_int(value):
    """Integer token count; anything that is not an int (incl. bool) is 0."""
    if type(value) is int:
        return value
    return 0


def facts_from_event(obj):
    """Facts from one stream object, or None if it is not a result event."""
    if not isinstance(obj, dict):
        return None
    if obj.get("type") != "result":
        return None
    session_id = obj.get("session_id")
    if not isinstance(session_id, str):
        return None
    usage = obj.get("usage")
    if not isinstance(usage, dict):
        usage = {}
    return {
        "session_id": session_id,
        "tokens_input": token_int(usage.get("inputTokens")),
        "tokens_output": token_int(usage.get("outputTokens")),
        "tokens_cache_read": token_int(usage.get("cacheReadTokens")),
        "tokens_cache_write": token_int(usage.get("cacheWriteTokens")),
    }


def facts_from_log(path):
    """Walk path line by line; last valid result event wins. Never raises."""
    facts = dict(EMPTY)
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue
                extracted = facts_from_event(obj)
                if extracted is not None:
                    facts = extracted
    except OSError:
        pass
    return facts


def emit(facts):
    json.dump(facts, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def main(argv):
    path = argv[1] if len(argv) > 1 else ""
    emit(facts_from_log(path) if path else dict(EMPTY))


if __name__ == "__main__":
    try:
        main(sys.argv)
    except Exception:
        emit(dict(EMPTY))
    sys.exit(0)
