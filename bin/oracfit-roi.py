#!/usr/bin/env python3
"""oracfit-roi.py — o que cada executor custou e acertou, a partir dos ledgers."""
import argparse
import json
import os
import sys
from collections import defaultdict
from pathlib import Path

LEDGER = ".dispatch/ledger/mode.jsonl"
CAMPOS = ("ts", "model_id", "task", "status", "attempt", "estimated_cost", "flash_work_s")


def die(code, msg):
    print(msg, file=sys.stderr)
    raise SystemExit(code)


def novo():
    return {
        "runs": 0, "pass": 0, "primeira_n": 0, "pass_custo": 0,
        "tent": 0.0, "tempo": 0.0, "custo_medido_usd": 0.0, "runs_com_custo": 0,
    }


def parse_row(d):
    if not isinstance(d, dict) or any(k not in d for k in CAMPOS):
        return None
    try:
        att = float(d["attempt"])
        tempo = float(d["flash_work_s"])
        cost = float(d["estimated_cost"])
        out = float(d["executor_out_tok"]) if "executor_out_tok" in d else None
    except (TypeError, ValueError):
        return None
    return d["model_id"], d["status"], str(d["attempt"]), att, tempo, cost, out


def fecha(m):
    r = m["runs"]
    pc = m["pass_custo"]
    return {
        "runs": r,
        "pass": m["pass"],
        "taxa_pass": m["pass"] / r,
        "primeira": round(100 * m["primeira_n"] / r),
        "tentativas_media": m["tent"] / r,
        "tempo_medio_s": m["tempo"] / r,
        "custo_medido_usd": m["custo_medido_usd"],
        "runs_com_custo": m["runs_com_custo"],
        "custo_por_pass_usd": (m["custo_medido_usd"] / pc) if pc else "n/d",
    }


def main():
    ap = argparse.ArgumentParser(prog="oracfit-roi")
    ap.add_argument("--workdir", action="append", default=[])
    ap.add_argument("--desde")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    wds = args.workdir or [os.getcwd()]
    paths = [Path(w) / LEDGER for w in wds]
    exist = [p for p in paths if p.is_file()]
    if not exist:
        die(3, "oracfit-roi: nenhum ledger encontrado: " + ", ".join(str(p) for p in paths))
    acc, ign = defaultdict(novo), 0
    for p in exist:
        for raw in p.read_text(encoding="utf-8").splitlines():
            if not raw.strip():
                continue
            try:
                d = json.loads(raw)
            except json.JSONDecodeError:
                ign += 1
                continue
            row = parse_row(d)
            if row is None:
                ign += 1
                continue
            mid, status, att_s, att, tempo, cost, out = row
            if args.desde and str(d["ts"]) < args.desde:
                continue
            m = acc[mid]
            m["runs"] += 1
            m["tent"] += att
            m["tempo"] += tempo
            if status == "pass":
                m["pass"] += 1
                if att_s == "1":
                    m["primeira_n"] += 1
            if out is not None and out > 0:
                m["custo_medido_usd"] += cost
                m["runs_com_custo"] += 1
                if status == "pass":
                    m["pass_custo"] += 1
    modelos = {k: fecha(acc[k]) for k, _ in sorted(acc.items(), key=lambda kv: (-kv[1]["runs"], kv[0]))}
    if args.json:
        print(json.dumps({"modelos": modelos, "linhas_ignoradas": ign}, ensure_ascii=False))
        return
    for mid, r in modelos.items():
        cm = "n/d" if r["runs_com_custo"] == 0 else r["custo_medido_usd"]
        cpp = "n/d" if r["runs_com_custo"] == 0 else r["custo_por_pass_usd"]
        print(
            f"{mid}  runs={r['runs']}  pass={r['pass']}  taxa_pass={r['taxa_pass']}  "
            f"primeira={r['primeira']}  tentativas_media={r['tentativas_media']}  "
            f"tempo_medio_s={r['tempo_medio_s']}  custo_medido_usd={cm}  "
            f"runs_com_custo={r['runs_com_custo']}  custo_por_pass_usd={cpp}"
        )
    sug = [f"{mid}={r['tentativas_media']}" for mid, r in modelos.items() if r["runs"] >= 3]
    if sug:
        print("tentativas_esperadas sugeridas para check-delegacao: " + " ".join(sug))


if __name__ == "__main__":
    main()
