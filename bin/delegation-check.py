#!/usr/bin/env python3
"""delegation-check.py — is it worth delegating this task to this executor, or should the orchestrator do it?

Two modes:
  delegation-check.py --deliverable-lines N [--context a,b] --executor X   BEFORE any spec is written.
      Writing the spec is the orchestrator's expensive part, so refusing only the dispatch saves nothing.
      The spec size is estimated with SPEC_TO_OUTPUT_RATIO and the verdict is cost-only (rules 4/5).
  delegation-check.py <spec> --executor X   measures a finished spec (calibration, not savings).

Exit: 0 DELEGATE · 10 DIRECT (a warning, not an error) · 3 usage / no line budget · 4 unknown price.
Design and rationale: docs/delegation-check.md.
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path

TOKENS_PER_CHAR = 0.25
TOKENS_PER_LINE = 12
TOOL_ROUNDS = 6
OUTPUT_FACTOR = 1.3
DEFAULT_ATTEMPTS = 1.5
MAX_SPEC_RATIO = 0.5
MARGIN = 0.7
# spec ÷ delivered output, measured on the 2026-10-02 specs (tests/fixtures/delegation: 0.91 and 0.98).
SPEC_TO_OUTPUT_RATIO = 0.94
BACKTICKED = re.compile(r"`([^`]+)`")
# english-ok-begin: the spec format still has Portuguese headings; accept both until the rename lands.
LINE_BUDGET = re.compile(r"(?:≤|<=)\s*(\d+)\s+(?:linhas|lines)", re.I)
DELIVERABLES = ("DELIVERABLES", "ENTREGÁVEIS")
VERIFIED_DATA = ("Verified data", "Dados verificados")
# english-ok-end


def fail(code, message):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def section(text, titles):
    lines = text.splitlines(True)
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("#") and any(t in line for t in titles)), None)
    if start is None:
        return ""
    body = []
    for line in lines[start + 1:]:
        if line.startswith("## "):
            break
        body.append(line)
    return "".join(body)


def mean_attempts(workdir, executor):
    ledger = Path(workdir) / ".dispatch/ledger/mode.jsonl"
    if not ledger.is_file():
        return DEFAULT_ATTEMPTS
    values = []
    for line in ledger.read_text(encoding="utf-8").splitlines():
        try:
            row = json.loads(line)
            if row.get("model_id") == executor and "attempt" in row:
                values.append(float(row["attempt"]))
        except (ValueError, TypeError, AttributeError):
            continue
    return sum(values) / len(values) if len(values) >= 3 else DEFAULT_ATTEMPTS


def price(table, model_id):
    entry = (table.get("models") or {}).get(model_id)
    if not isinstance(entry, dict) or entry.get("in") is None or entry.get("out") is None:
        fail(4, f"delegation-check: unknown price for {model_id} — fill it in core/prices.json")
    return float(entry["in"]), float(entry["out"])


def as_int_if_whole(x):
    return int(x) if float(x) == int(x) else x


class Parser(argparse.ArgumentParser):
    def error(self, message):
        fail(3, f"delegation-check: {message}")


def main():
    root = Path(__file__).resolve().parent.parent
    ap = Parser(prog="delegation-check")
    ap.add_argument("spec", nargs="?")
    ap.add_argument("--executor", required=True)
    ap.add_argument("--orchestrator", default="claude-opus-5-5")
    ap.add_argument("--prices", default=str(root / "core/prices.json"))
    ap.add_argument("--workdir", default=".")
    ap.add_argument("--deliverable-lines", type=int, help="lines to deliver (before-the-spec mode)")
    ap.add_argument("--context", default="", help="comma-separated files the executor will read")
    ap.add_argument("--parallel", action="store_true")
    ap.add_argument("--protect-context", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    before_spec = args.spec is None
    if before_spec:
        if not args.deliverable_lines or args.deliverable_lines <= 0:
            fail(3, "delegation-check: without a spec, give the delivery size: --deliverable-lines <n>")
        output_tok = args.deliverable_lines * TOKENS_PER_LINE
        spec_tok = math.ceil(SPEC_TO_OUTPUT_RATIO * output_tok)
        context_files = [c.strip() for c in args.context.split(",") if c.strip()]
    else:
        try:
            text = Path(args.spec).read_text(encoding="utf-8")
        except OSError as e:
            fail(3, f"delegation-check: {e}")
        spec_tok = math.ceil(len(text) * TOKENS_PER_CHAR)
        budgets = [int(n) for n in LINE_BUDGET.findall(section(text, DELIVERABLES))]
        if not budgets:
            fail(3, 'delegation-check: declare a line budget under DELIVERABLES (e.g. "file.py (<= 80 lines)")')
        output_tok = sum(budgets) * TOKENS_PER_LINE
        context_files = BACKTICKED.findall(section(text, VERIFIED_DATA))
    context_tok = 0.0
    for name in context_files:
        path = Path(args.workdir) / name
        if path.is_file():
            context_tok += path.stat().st_size * TOKENS_PER_CHAR

    attempts = mean_attempts(args.workdir, args.executor)
    try:
        table = json.loads(Path(args.prices).read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        fail(4, f"delegation-check: unknown price for {args.executor} — fill it in core/prices.json")
    exec_in, exec_out = price(table, args.executor)
    orch_in, orch_out = price(table, args.orchestrator)
    per_mtok = 1e6
    cost_delegate = (spec_tok * orch_out + output_tok * orch_in) / per_mtok + attempts * (
        context_tok * TOOL_ROUNDS * exec_in + output_tok * OUTPUT_FACTOR * exec_out) / per_mtok
    cost_direct = (output_tok * OUTPUT_FACTOR * orch_out + attempts * context_tok * TOOL_ROUNDS * orch_in) / per_mtok

    if exec_in == 0 and exec_out == 0:
        verdict, reason = "DELEGATE", "executor has no per-token cost"
    elif args.parallel:
        verdict, reason = "DELEGATE", "the orchestrator has parallel work"
    elif args.protect_context:
        verdict, reason = "DELEGATE", "protect the orchestrator's context"
    elif not before_spec and spec_tok / output_tok > MAX_SPEC_RATIO:
        pct = round(100 * spec_tok / output_tok)
        verdict, reason = "DIRECT", f"the spec is {pct}% of the delivery ({spec_tok} of {output_tok} tok)"
    else:
        pct = round(100 * cost_delegate / cost_direct) if cost_direct else 0
        reason = f"delegating costs {pct}% of doing it directly"
        verdict = "DELEGATE" if cost_delegate <= MARGIN * cost_direct else "DIRECT"

    result = {
        "verdict": verdict, "reason": reason, "spec_tok": spec_tok, "output_tok": output_tok,
        "context_tok": as_int_if_whole(context_tok), "attempts": as_int_if_whole(attempts),
        "cost_delegate": cost_delegate, "cost_direct": cost_direct, "executor": args.executor,
        "orchestrator": args.orchestrator, "mode": "before-spec" if before_spec else "spec",
    }
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    else:
        print(f"{verdict} — {reason}; delegate ≈ US${cost_delegate:.4f} vs direct ≈ US${cost_direct:.4f} "
              f"(executor {args.executor}).")
    raise SystemExit(0 if verdict == "DELEGATE" else 10)


if __name__ == "__main__":
    main()
