#!/usr/bin/env python3
"""check-context.py — verify every claim pointer in CONTEXT.md files (zero model tokens).

For each claim: the path exists, the symbol is still defined, the quoted line is still in the
file (matched by text, not line number), and the cited test still exists. Optionally reports
source files that no CONTEXT.md mentions (coverage) and files over the line budget.

Usage:
  check-context.py [--root DIR] [--coverage GLOB ...] [--budget N] [--json]
Exit: 0 all claims ok (or decision); 1 any broken claim, uncovered file or budget overflow; 2 bad input.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cmap_claims import check, context_files, parse  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--root", type=Path, default=Path("."))
    ap.add_argument("--coverage", nargs="*", default=[], help="globs of source files that must be cited, e.g. 'apps/backend/src/**/*.ts'")
    ap.add_argument("--budget", type=int, default=80, help="max lines per CONTEXT.md (agents read it before every task)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    root = args.root.resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 2

    results, cited, over = [], set(), []
    for f in context_files(root):
        lines, claims = parse(f)
        if len(lines) > args.budget:
            over.append((str(f.relative_to(root)), len(lines)))
        for c in claims:
            status = check(c, root)
            if "path" in c.keys:
                cited.add(str(Path(c.keys["path"])))
            results.append({"file": str(f.relative_to(root)), "line": c.start + 1,
                            "status": status, "text": c.text[:120], **c.keys})

    uncovered = []
    for g in args.coverage:
        for p in sorted(root.glob(g)):
            rel = str(p.relative_to(root))
            if p.is_file() and rel not in cited and not any(rel.startswith(c.rstrip("/") + "/") for c in cited):
                uncovered.append(rel)

    broken = [r for r in results if r["status"] not in ("ok", "decision")]
    if args.json:
        print(json.dumps({"claims": results, "uncovered": uncovered, "over_budget": over}, ensure_ascii=False, indent=2))
    else:
        counts = {}
        for r in results:
            counts[r["status"]] = counts.get(r["status"], 0) + 1
        print("claims: " + (", ".join(f"{k} {v}" for k, v in sorted(counts.items())) or "none"))
        for r in broken:
            print(f"  {r['status']:13} {r['file']}:{r['line']}  {r['text']}")
        for f, n in over:
            print(f"  over_budget   {f}: {n} lines (budget {args.budget})")
        for u in uncovered:
            print(f"  uncovered     {u}")
    return 1 if broken or uncovered or over else 0


if __name__ == "__main__":
    sys.exit(main())
