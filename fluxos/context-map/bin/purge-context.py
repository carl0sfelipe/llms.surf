#!/usr/bin/env python3
"""purge-context.py — delete outdated context instead of carrying it forward.

Every line an agent reads costs tokens on every future task, and a wrong line costs more than a
missing one: the agent trusts it. So stale context is removed, not kept "just in case":

  dead    path no longer exists            -> bullet removed now
  stale   symbol / quote / test not found  -> bullet marked stale=<today>; removed when the mark
                                              is older than --grace days (time for the owner of the
                                              change to rewrite it)
  expired verified= older than --max-age  -> bullet marked stale=<today> (same grace)
  dup     same claim (same path + quote) twice in one file -> later copy removed now
  budget  file over --budget lines after the above -> report only (a human or agent trims it)

A bullet that is rewritten and passes again loses its stale mark. kind=decision bullets are never
touched. Default is a dry run; --apply writes the files and appends every removal to PURGE-LOG.md
(the text stays recoverable through git and the log).

Usage:
  purge-context.py [--root DIR] [--grace 14] [--max-age 180] [--budget 80] [--today YYYY-MM-DD] [--apply]
Exit: 0 nothing to purge or applied; 1 dry run found work; 2 bad input.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cmap_claims import CLAIM_RE, check, context_files, parse  # noqa: E402


def days(a: str, b: dt.date) -> int | None:
    try:
        return (b - dt.date.fromisoformat(a)).days
    except ValueError:
        return None


def set_key(comment: str, key: str, value: str | None) -> str:
    """Add, replace or remove `key=value` inside one claim comment."""
    comment = re.sub(rf"\s+{key}=\S+", "", comment)
    if value is None:
        return comment
    return comment.replace("-->", f"{key}={value} -->", 1)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", type=Path, default=Path("."))
    ap.add_argument("--grace", type=int, default=14)
    ap.add_argument("--max-age", type=int, default=180)
    ap.add_argument("--budget", type=int, default=80)
    ap.add_argument("--today", default=dt.date.today().isoformat())
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2
    today = dt.date.fromisoformat(args.today)

    work, log = 0, []
    for f in context_files(root):
        lines, claims = parse(f)
        drop, seen = set(), set()
        text = "\n".join(lines)
        for c in claims:
            k = c.keys
            if k.get("kind") == "decision":
                continue
            status = check(c, root)
            sig = (k.get("path"), k.get("quote"), k.get("symbol"))
            action = None
            if status == "dead":
                action = "remove:dead"
            elif sig in seen:
                action = "remove:dup"
            elif status != "ok":
                age = days(k["stale"], today) if "stale" in k else None
                action = "remove:stale" if age is not None and age >= args.grace else ("mark:" + status if "stale" not in k else None)
            elif k.get("verified") and (days(k["verified"], today) or 0) > args.max_age and "stale" not in k:
                action = "mark:expired"
            elif "stale" in k:
                action = "unmark"  # rewritten and passing again
            seen.add(sig)
            if not action:
                continue
            work += 1
            rel = f.relative_to(root)
            print(f"{action:16} {rel}:{c.start + 1}  {c.text[:100]}")
            if action.startswith("remove"):
                drop.update(range(c.start, c.end + 1))
                log.append(f"| {args.today} | {rel} | {action.split(':')[1]} | {c.text[:160]} |")
            else:
                block = "\n".join(lines[c.start:c.end + 1])
                m = CLAIM_RE.search(block)
                new = set_key(m.group(0), "stale", None if action == "unmark" else args.today)
                text = text.replace(block, block.replace(m.group(0), new), 1)
        if args.apply and (drop or text != "\n".join(lines)):
            kept = [l for i, l in enumerate(text.splitlines()) if i not in drop]
            f.write_text("\n".join(kept).rstrip() + "\n", encoding="utf-8")
        n = len([l for i, l in enumerate(text.splitlines()) if i not in drop])
        if n > args.budget:
            print(f"budget           {f.relative_to(root)}: {n} lines (budget {args.budget}) — trim by hand")

    if args.apply and log:
        plog = root / "PURGE-LOG.md"
        head = "" if plog.exists() else "# Context purge log\n\n| date | file | reason | removed text |\n|---|---|---|---|\n"
        with plog.open("a", encoding="utf-8") as fh:
            fh.write(head + "\n".join(log) + "\n")
    if not work:
        print("nothing to purge")
    return 0 if (args.apply or not work) else 1


if __name__ == "__main__":
    sys.exit(main())
