#!/usr/bin/env python3
"""Summarize a `claude -p --output-format json` reply (stdin) as ONE JSON line (stdout).

    {"cost_usd": 0.41, "in_tok": 1200, "cache_read_tok": 80000, "cache_write_tok": 9000,
     "out_tok": 3100, "denied": ["Write", "Bash"], "denied_writes": 2}

Used by runner.sh to (1) send the executor's real cost to the ledger (docs/delegation-check.md §4 —
the ledger used to record estimated_cost="0") and (2) fail fast when writes were denied
(incident 2026-10-02-claude-code-runner-sai-0-com-escrita-negada).
The runner output has stderr mixed in: take the LAST JSON object whose "type" is "result".
No recognizable object: print nothing and exit 0 — the runner behaves as before.
"""

from __future__ import annotations

import json
import sys

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}


def last_result(text: str) -> dict | None:
    candidates = [text] + text.splitlines()[::-1]
    for block in candidates:
        block = block.strip()
        if not block.startswith("{"):
            continue
        try:
            doc = json.loads(block)
        except ValueError:
            continue
        if isinstance(doc, dict) and doc.get("type") == "result":
            return doc
    return None


def summarize(doc: dict) -> dict:
    usage = doc.get("usage") or {}
    denied = [d.get("tool_name", "?") for d in doc.get("permission_denials") or [] if isinstance(d, dict)]
    return {
        "cost_usd": doc.get("total_cost_usd") or 0,
        "in_tok": usage.get("input_tokens") or 0,
        "cache_read_tok": usage.get("cache_read_input_tokens") or 0,
        "cache_write_tok": usage.get("cache_creation_input_tokens") or 0,
        "out_tok": usage.get("output_tokens") or 0,
        "denied": denied,
        "denied_writes": sum(1 for name in denied if name in WRITE_TOOLS),
    }


if __name__ == "__main__":
    doc = last_result(sys.stdin.read())
    if doc is not None:
        print(json.dumps(summarize(doc)))
