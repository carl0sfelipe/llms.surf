#!/usr/bin/env python3
"""oracfit-roi.py — what each executor cost and how often it got it right, from the ledgers.

Unmeasured cost is shown as "n/a", never 0: older rows and direct-mode rows (model_id "orchestrator",
cost_source "orchestrator-unmeasured") carry estimated_cost "0" without executor_out_tok.
Design: docs/delegation-check.md §4.
"""
import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

LEDGER = ".dispatch/ledger/mode.jsonl"
REQUIRED = ("ts", "model_id", "task", "status", "attempt", "estimated_cost", "flash_work_s")


def fail(code, message):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def empty_totals():
    return {"runs": 0, "pass": 0, "first_try": 0, "pass_with_cost": 0,
            "attempts": 0.0, "time_s": 0.0, "measured_cost_usd": 0.0, "runs_with_cost": 0}


def parse_row(row):
    if not isinstance(row, dict) or any(k not in row for k in REQUIRED):
        return None
    try:
        attempt = float(row["attempt"])
        time_s = float(row["flash_work_s"])
        cost = float(row["estimated_cost"])
        out_tok = float(row["executor_out_tok"]) if "executor_out_tok" in row else None
    except (TypeError, ValueError):
        return None
    return row["model_id"], row["status"], str(row["attempt"]), attempt, time_s, cost, out_tok


def summarize(t):
    runs, paid_passes = t["runs"], t["pass_with_cost"]
    return {
        "runs": runs,
        "pass": t["pass"],
        "pass_rate": t["pass"] / runs,
        "first_try_pct": round(100 * t["first_try"] / runs),
        "mean_attempts": t["attempts"] / runs,
        "mean_time_s": t["time_s"] / runs,
        "measured_cost_usd": t["measured_cost_usd"],
        "runs_with_cost": t["runs_with_cost"],
        "cost_per_pass_usd": (t["measured_cost_usd"] / paid_passes) if paid_passes else "n/a",
    }


def main():
    ap = argparse.ArgumentParser(prog="oracfit-roi")
    ap.add_argument("--workdir", action="append", default=[])
    ap.add_argument("--since", help="only rows with ts >= YYYY-MM-DD")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    paths = [Path(w) / LEDGER for w in (args.workdir or [os.getcwd()])]
    found = [p for p in paths if p.is_file()]
    if not found:
        fail(3, "oracfit-roi: no ledger found: " + ", ".join(str(p) for p in paths))
    totals, ignored = defaultdict(empty_totals), 0
    for path in found:
        for raw in path.read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            try:
                row = json.loads(raw)
            except json.JSONDecodeError:
                ignored += 1
                continue
            parsed = parse_row(row)
            if parsed is None:
                ignored += 1
                continue
            model_id, status, attempt_text, attempt, time_s, cost, out_tok = parsed
            if args.since and str(row["ts"]) < args.since:
                continue
            t = totals[model_id]
            t["runs"] += 1
            t["attempts"] += attempt
            t["time_s"] += time_s
            if status == "pass":
                t["pass"] += 1
                if attempt_text == "1":
                    t["first_try"] += 1
            if out_tok is not None and out_tok > 0:
                t["measured_cost_usd"] += cost
                t["runs_with_cost"] += 1
                if status == "pass":
                    t["pass_with_cost"] += 1
    models = {k: summarize(totals[k])
              for k, _ in sorted(totals.items(), key=lambda kv: (-kv[1]["runs"], kv[0]))}
    if args.json:
        print(json.dumps({"models": models, "ignored_lines": ignored}, ensure_ascii=False))
        return
    for model_id, r in models.items():
        measured = r["runs_with_cost"] > 0
        cost = f"{r['measured_cost_usd']:.4f}" if measured else "n/a"
        per_pass = f"{r['cost_per_pass_usd']:.4f}" if measured and r["cost_per_pass_usd"] != "n/a" else "n/a"
        print(f"{model_id}  runs={r['runs']}  pass={r['pass']}  pass_rate={r['pass_rate']:.2f}  "
              f"first_try={r['first_try_pct']}%  mean_attempts={r['mean_attempts']:.2f}  "
              f"mean_time_s={r['mean_time_s']:.1f}  measured_cost_usd={cost}  "
              f"runs_with_cost={r['runs_with_cost']}  cost_per_pass_usd={per_pass}")
    hints = [f"{m}={r['mean_attempts']:.2f}" for m, r in models.items() if r["runs"] >= 3]
    if hints:
        print("suggested expected attempts for delegation-check: " + " ".join(hints))


if __name__ == "__main__":
    main()
