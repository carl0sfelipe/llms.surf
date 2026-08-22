#!/usr/bin/env python3
"""Vision gauntlet helpers — pairing, severity rollup, revise-brief, A/B critic loop.

Used by bin/dispatch-vision-ui-qa.sh (P2). Can run offline unit pieces without API:
  vision-gauntlet-loop.py rollup <findings.jsonl>
  vision-gauntlet-loop.py pair <ours_dir> <bar_dir>
  vision-gauntlet-loop.py brief <findings.jsonl> <report.json> <out.md>
  vision-gauntlet-loop.py ab-loop ...  (needs OPENROUTER key / auth.json)

Exit codes for ab-loop: 0=APPROVED, 1=REVISIONS_REQUIRED, 2=usage error.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import random
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional


SEVERE = {"critical", "major"}


def _load_jsonl(path: Path) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            rows.append(obj)
    return rows


def rollup_severity(rows: List[Dict[str, Any]]) -> str:
    order = {"critical": 3, "major": 2, "minor": 1, "ok": 0}
    worst = 0
    worst_label = "ok"
    for row in rows:
        sev = str(row.get("overall_severity") or "ok").lower()
        score = order.get(sev, 0)
        if score > worst:
            worst = score
            worst_label = sev
    return worst_label


def needs_gauntlet(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [r for r in rows if str(r.get("overall_severity") or "").lower() in SEVERE]


def pair_shots(ours_dir: Path, bar_dir: Path) -> List[Dict[str, str]]:
    """Pair by basename (case-insensitive). Returns list of {ours, bar, name}."""
    def index(d: Path) -> Dict[str, Path]:
        out: Dict[str, Path] = {}
        if not d.is_dir():
            return out
        for p in d.iterdir():
            if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp"}:
                out[p.name.lower()] = p
        return out

    ours = index(ours_dir)
    bars = index(bar_dir)
    pairs = []
    for key, ours_path in sorted(ours.items()):
        bar_path = bars.get(key)
        if bar_path:
            pairs.append({"ours": str(ours_path), "bar": str(bar_path), "name": ours_path.name})
    return pairs


def _auth_key() -> str:
    auth = Path.home() / ".local/share/opencode/auth.json"
    if auth.exists():
        data = json.loads(auth.read_text(encoding="utf-8"))
        key = (data.get("openrouter") or {}).get("key")
        if key:
            return key
    key = os.environ.get("OPENROUTER_API_KEY") or os.environ.get("OR_API_KEY")
    if not key:
        raise SystemExit("missing OpenRouter key (auth.json openrouter.key or OPENROUTER_API_KEY)")
    return key


def _resize_b64(image_path: Path, max_px: int = 1024) -> str:
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "img.jpg"
        # Prefer sips (macOS); fall back to copy.
        rc = subprocess.run(
            ["sips", "-Z", str(max_px), str(image_path), "--out", str(out)],
            capture_output=True,
        )
        src = out if rc.returncode == 0 and out.exists() else image_path
        return base64.b64encode(src.read_bytes()).decode("ascii")


def _extract_json(text: str) -> Optional[Dict[str, Any]]:
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*\n(.*?)```", text, re.S | re.I)
    candidate = fence.group(1).strip() if fence else text
    try:
        obj = json.loads(candidate)
        if isinstance(obj, dict):
            return obj
        if isinstance(obj, list) and obj and isinstance(obj[0], dict):
            return obj[0]
    except json.JSONDecodeError:
        pass
    m = re.search(r"\{.*\}", text, re.S)
    if m:
        try:
            obj = json.loads(m.group(0))
            if isinstance(obj, dict):
                return obj
        except json.JSONDecodeError:
            return None
    return None


def _opencode_engine(model: str) -> bool:
    # Engine v3: modelos opencode-go (ex.: opencode/gemini-3.6-flash) andam via
    # `opencode run` local, nao por OpenRouter.
    return model.startswith("opencode/")


def _opencode_vision(model: str, prompt: str, image_paths: List[Path]) -> str:
    # ARMADILHA (incident 2026-08-11): -f e array variadico — prompt posicional
    # ANTES dos -f, senao o prompt vira caminho de arquivo.
    cmd = ["opencode", "run", "-m", model, prompt]
    for p in image_paths:
        cmd += ["-f", str(p)]
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
    return (proc.stdout or "") + (proc.stderr or "")


def _vision_chat(model: str, prompt: str, image_paths: List[Path], key: str) -> Dict[str, Any]:
    if _opencode_engine(model):
        for attempt in range(1, 4):
            try:
                raw = _opencode_vision(model, prompt, image_paths)
            except subprocess.TimeoutExpired:
                raw = ""
            if raw.strip():
                parsed = _extract_json(raw)
                if parsed is not None:
                    return parsed
                return {"raw": raw}
            time.sleep(10 * attempt)
        return {"error": "failed_3_attempts_opencode"}
    content: List[Dict[str, Any]] = [{"type": "text", "text": prompt}]
    for p in image_paths:
        content.append(
            {
                "type": "image_url",
                "image_url": {"url": f"data:image/jpeg;base64,{_resize_b64(p)}"},
            }
        )
    payload = {"model": model, "messages": [{"role": "user", "content": content}]}
    req = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    try:
        json.dump(payload, req)
        req.close()
        for attempt in range(1, 6):
            proc = subprocess.run(
                [
                    "curl", "-s", "--max-time", "120",
                    "https://openrouter.ai/api/v1/chat/completions",
                    "-H", f"Authorization: Bearer {key}",
                    "-H", "Content-Type: application/json",
                    "-d", f"@{req.name}",
                ],
                capture_output=True,
                text=True,
            )
            try:
                resp = json.loads(proc.stdout or "{}")
            except json.JSONDecodeError:
                resp = {}
            msg = (
                ((resp.get("choices") or [{}])[0].get("message") or {}).get("content")
                or ""
            )
            err = (resp.get("error") or {}).get("code")
            if msg:
                parsed = _extract_json(msg) or {"raw": msg}
                return parsed
            if str(err) == "429":
                time.sleep(60 * attempt)
                continue
            time.sleep(5)
        return {"error": "failed_5_attempts"}
    finally:
        Path(req.name).unlink(missing_ok=True)


def blind_ab_once(
    ours: Path,
    bar: Path,
    model: str,
    key: str,
    previous_gap: str = "",
) -> Dict[str, Any]:
    """Blind A/B: shuffle labels, critic picks better screenshot."""
    slots = [("ours", ours), ("bar", bar)]
    random.shuffle(slots)
    label_to_side = {"A": slots[0][0], "B": slots[1][0]}

    gap_line = ""
    if previous_gap:
        gap_line = (
            f"\nPrevious critic gap (fix if still losing): {previous_gap}\n"
            "Be harsher. Praise is not useful.\n"
        )

    base_prompt = os.environ.get("VISION_AB_PROMPT") or """You are a harsh ecommerce visual QA critic (gauntlet).
Compare TWO storefront screenshots labeled A and B. Labels are arbitrary.
Criteria: broken images, layout, CSS polish, product photo clarity, trust for buying."""
    prompt = f"""{base_prompt}
{gap_line}
Reply ONLY valid JSON:
{{
  "winner": "A" | "B" | "tie",
  "biggest_gap": "single biggest remaining gap on the LOSER vs the winner (empty if tie and both excellent)",
  "reason_pt": "1 frase em portugues"
}}
No praise. Binary job."""

    result = _vision_chat(model, prompt, [slots[0][1], slots[1][1]], key)
    winner_label = str(result.get("winner") or "tie").upper().strip()
    if winner_label in ("A", "B"):
        pick = label_to_side[winner_label]
    else:
        pick = "tie"
    return {
        "pick": pick,  # ours | bar | tie
        "winner_label": winner_label,
        "label_map": label_to_side,
        "biggest_gap": str(result.get("biggest_gap") or "").strip(),
        "reason_pt": str(result.get("reason_pt") or "").strip(),
        "raw": result,
    }


def write_revise_brief(
    findings_path: Path,
    report: Dict[str, Any],
    out_md: Path,
) -> None:
    rows = _load_jsonl(findings_path)
    lines = [
        "# Vision gauntlet — revise brief",
        "",
        f"Verdict: **{report.get('verdict', 'UNKNOWN')}**",
        f"Rounds ceiling: {report.get('ceiling', '?')}",
        "",
        "The critic is harsh. Fix the gaps below before re-shooting / re-dispatch.",
        "",
    ]
    for pair in report.get("pairs") or []:
        lines.append(f"## {pair.get('name') or pair.get('arquivo')}")
        lines.append(f"- map severity: `{pair.get('map_severity', '?')}`")
        lines.append(f"- A/B pick: `{pair.get('pick', '?')}`")
        gap = pair.get("biggest_gap") or ""
        if gap:
            lines.append(f"- **Single biggest remaining gap:** {gap}")
        for r in pair.get("rounds") or []:
            lines.append(f"  - round pick=`{r.get('pick')}` gap=`{r.get('biggest_gap', '')}`")
        lines.append("")

    severe = needs_gauntlet(rows)
    if severe and not (report.get("pairs") or []):
        lines.append("## Map-only findings (no bar pair)")
        for row in severe:
            lines.append(
                f"- `{row.get('arquivo')}` severity=`{row.get('overall_severity')}` — "
                f"{row.get('summary_pt') or ''}"
            )
        lines.append("")

    out_md.parent.mkdir(parents=True, exist_ok=True)
    out_md.write_text("\n".join(lines) + "\n", encoding="utf-8")


def cmd_rollup(args: argparse.Namespace) -> int:
    rows = _load_jsonl(Path(args.findings))
    print(rollup_severity(rows))
    return 0


def cmd_pair(args: argparse.Namespace) -> int:
    pairs = pair_shots(Path(args.ours), Path(args.bar))
    json.dump(pairs, sys.stdout, indent=2, ensure_ascii=False)
    print()
    return 0


def cmd_brief(args: argparse.Namespace) -> int:
    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    write_revise_brief(Path(args.findings), report, Path(args.out))
    print(args.out)
    return 0


def cmd_ab_loop(args: argparse.Namespace) -> int:
    findings = Path(args.findings)
    ours_dir = Path(args.ours)
    bar_dir = Path(args.bar)
    ceiling = int(args.ceiling)
    model = args.model
    interval = float(args.interval)
    report_path = Path(args.report)
    brief_path = Path(args.brief) if args.brief else report_path.with_suffix(".revise.md")

    rows = _load_jsonl(findings)
    by_name = {str(r.get("arquivo") or "").lower(): r for r in rows}
    pairs_fs = pair_shots(ours_dir, bar_dir)
    if not pairs_fs:
        # No pairs: approve only if map has no critical/major
        sev = rollup_severity(rows)
        verdict = "APPROVED" if sev not in SEVERE else "REVISIONS_REQUIRED"
        report = {
            "verdict": verdict,
            "ceiling": ceiling,
            "pairs": [],
            "note": "no basename pairs between ours and bar",
            "map_rollup": sev,
        }
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        write_revise_brief(findings, report, brief_path)
        return 0 if verdict == "APPROVED" else 1

    key = None if _opencode_engine(model) else _auth_key()
    pair_results: List[Dict[str, Any]] = []

    for i, pair in enumerate(pairs_fs):
        name = pair["name"]
        row = by_name.get(name.lower(), {})
        map_sev = str(row.get("overall_severity") or "ok").lower()
        # Always A/B when bar exists; prioritize severe, but also validate ok shots lightly (1 round)
        max_rounds = ceiling if map_sev in SEVERE else min(1, ceiling)
        rounds: List[Dict[str, Any]] = []
        gap = ""
        pick = "tie"
        for rnd in range(1, max_rounds + 1):
            ab = blind_ab_once(Path(pair["ours"]), Path(pair["bar"]), model, key, previous_gap=gap)
            pick = ab["pick"]
            gap = ab.get("biggest_gap") or gap
            rounds.append(
                {
                    "round": rnd,
                    "pick": pick,
                    "biggest_gap": ab.get("biggest_gap") or "",
                    "reason_pt": ab.get("reason_pt") or "",
                }
            )
            print(f"  A/B {name} round {rnd}/{max_rounds}: pick={pick}", file=sys.stderr)
            if pick == "ours":
                break
            if rnd < max_rounds:
                time.sleep(interval)

        pair_results.append(
            {
                "name": name,
                "arquivo": name,
                "map_severity": map_sev,
                "pick": pick,
                "biggest_gap": gap if pick != "ours" else "",
                "rounds": rounds,
            }
        )

    # Win condition: every pair ended with ours (or tie on non-severe), and no unpaired severe
    unpaired_severe = [
        r for r in needs_gauntlet(rows)
        if str(r.get("arquivo") or "").lower() not in {p["name"].lower() for p in pairs_fs}
    ]
    losses = [p for p in pair_results if p["pick"] == "bar"]
    if losses or unpaired_severe:
        verdict = "REVISIONS_REQUIRED"
    else:
        verdict = "APPROVED"

    report = {
        "verdict": verdict,
        "ceiling": ceiling,
        "pairs": pair_results,
        "unpaired_severe": [
            {"arquivo": r.get("arquivo"), "overall_severity": r.get("overall_severity"), "summary_pt": r.get("summary_pt")}
            for r in unpaired_severe
        ],
        "map_rollup": rollup_severity(rows),
    }
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_revise_brief(findings, report, brief_path)
    print(f"vision gauntlet verdict={verdict} report={report_path} brief={brief_path}", file=sys.stderr)
    return 0 if verdict == "APPROVED" else 1


def main() -> None:
    parser = argparse.ArgumentParser(description="Oracfit vision gauntlet (P2)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_roll = sub.add_parser("rollup", help="Print worst overall_severity from jsonl")
    p_roll.add_argument("findings")
    p_roll.set_defaults(func=cmd_rollup)

    p_pair = sub.add_parser("pair", help="JSON list of basename pairs ours↔bar")
    p_pair.add_argument("ours")
    p_pair.add_argument("bar")
    p_pair.set_defaults(func=cmd_pair)

    p_brief = sub.add_parser("brief", help="Write revise markdown from report+findings")
    p_brief.add_argument("findings")
    p_brief.add_argument("report")
    p_brief.add_argument("out")
    p_brief.set_defaults(func=cmd_brief)

    p_ab = sub.add_parser("ab-loop", help="Blind A/B loop until ours wins or ceiling")
    p_ab.add_argument("--findings", required=True)
    p_ab.add_argument("--ours", required=True)
    p_ab.add_argument("--bar", required=True)
    p_ab.add_argument("--report", required=True)
    p_ab.add_argument("--brief", default="")
    p_ab.add_argument("--ceiling", type=int, default=4)
    p_ab.add_argument("--interval", type=float, default=12.0)
    p_ab.add_argument("--model", default=os.environ.get("VISION_MODEL", "google/gemma-4-26b-a4b-it:free"))
    p_ab.set_defaults(func=cmd_ab_loop)

    args = parser.parse_args()
    raise SystemExit(args.func(args))


if __name__ == "__main__":
    main()
