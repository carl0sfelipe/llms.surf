#!/usr/bin/env python3
"""check-claims.py — deterministic first pass of post review (zero model tokens).

Every post `posts/<slug>.md` ships with a claim manifest `posts/<slug>.claims.json`
written by the writer at generation time: one entry per number in the post, with
the exact snippet of the source page that supports it. This script checks:

  1. coverage   — every number in the post body has a manifest entry;
  2. coherence  — each entry's value appears in its post text, and one fact does not
                  appear with two different values;
  3. source     — the snippet is still on the page (fetched once, cached) and the
                  value is inside the snippet.

Result per claim: ok | source_changed | value_not_in_snippet | fetch_failed | not_in_post.
The reviewer model then opens only what did not pass, plus a small sample of `ok`.

Usage:
  check-claims.py POST.md [POST.md ...] [--cache DIR] [--out-dir DIR] [--sample N] [--offline]
Exit code: 0 when every number is covered and no claim failed; 1 otherwise; 2 on bad input.
"""
from __future__ import annotations

import argparse
import hashlib
import html
import json
import random
import re
import sys
import urllib.request
from pathlib import Path

# A number as it is written in pt-BR/es/en prose: 1.499 · 11,95 · 4K · 240 · 12–18 · 20%
NUMBER_RE = re.compile(r"(?<![\w/.-])\d[\d.,]*(?:\s?%|\s?[kKmM]\b)?")
IGNORED_LINE_RE = re.compile(r"^\s*(```|https?://|\[.*\]\(https?://|<!--)")
URL_RE = re.compile(r"https?://\S+")
TAG_RE = re.compile(r"<(script|style)\b.*?</\1>|<[^>]+>", re.S | re.I)


def digits(text: str) -> str:
    """Comparable form of a value: only digits, so 1.499 == 1,499 == 1499."""
    return re.sub(r"\D", "", text)


def norm(text: str) -> str:
    return re.sub(r"\s+", " ", html.unescape(text)).strip().lower()


def body_numbers(post_text: str) -> list[str]:
    """Numbers in the post body, skipping front matter, code, URLs and the Sources list."""
    text = post_text
    if text.startswith("---\n"):
        end = text.find("\n---", 4)
        text = text[end + 4:] if end > 0 else text
    found, in_code, in_sources = [], False, False
    for line in text.splitlines():
        if line.startswith("```"):
            in_code = not in_code
            continue
        if in_code or IGNORED_LINE_RE.match(line):
            continue
        if re.match(r"^##\s", line):
            in_sources = bool(re.match(r"^##\s+(Fontes|Sources|Fuentes)\b", line))
            continue
        if in_sources:
            continue
        line = URL_RE.sub("", line)
        for m in NUMBER_RE.finditer(line):
            d = digits(m.group(0))
            if len(d) >= 2 or "%" in m.group(0):  # single digits ("3 modos") are noise
                found.append(d)
    return found


def fetch(url: str, cache: Path, offline: bool) -> str | None:
    key = cache / (hashlib.sha256(url.encode()).hexdigest() + ".txt")
    if key.exists():
        return key.read_text(encoding="utf-8", errors="replace")
    if offline:
        return None
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (claim-check)"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read(4_000_000).decode("utf-8", errors="replace")
    except Exception:
        return None
    text = norm(TAG_RE.sub(" ", raw))
    cache.mkdir(parents=True, exist_ok=True)
    key.write_text(text, encoding="utf-8")
    return text


def check_post(post: Path, cache: Path, offline: bool) -> dict:
    manifest_path = post.with_suffix(".claims.json")
    post_text = post.read_text(encoding="utf-8", errors="replace")
    if not manifest_path.exists():
        return {"post": str(post), "error": "missing manifest", "claims": [], "uncovered": [], "conflicts": []}
    claims = json.loads(manifest_path.read_text(encoding="utf-8"))
    claims = claims.get("claims", claims) if isinstance(claims, dict) else claims

    results, by_fact = [], {}
    covered = set()
    for c in claims:
        value, quote = str(c.get("value", "")), str(c.get("source_quote", ""))
        in_post = str(c.get("post_text", ""))
        covered.add(digits(value))
        status = "ok"
        if digits(value) not in digits(in_post) or norm(in_post) not in norm(post_text):
            status = "not_in_post"
        else:
            page = fetch(str(c.get("url", "")), cache, offline)
            if page is None:
                status = "fetch_failed"
            elif norm(quote) not in page:
                status = "source_changed"
            elif digits(value) not in digits(quote):
                status = "value_not_in_snippet"
        fact = c.get("fact")
        if fact:
            by_fact.setdefault(fact, set()).add(digits(value))
        results.append({**c, "status": status})

    uncovered = sorted({n for n in body_numbers(post_text) if n not in covered and not any(n in cv for cv in covered)})
    conflicts = sorted(f for f, vals in by_fact.items() if len(vals) > 1)
    return {"post": str(post), "claims": results, "uncovered": uncovered, "conflicts": conflicts}


def render(report: dict, sample: list) -> str:
    lines = [f"# Claim check — {Path(report['post']).name}", ""]
    if report.get("error"):
        return "\n".join(lines + [f"ERROR: {report['error']}", ""])
    counts = {}
    for c in report["claims"]:
        counts[c["status"]] = counts.get(c["status"], 0) + 1
    lines.append("counts: " + ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    lines.append(f"numbers without a claim: {len(report['uncovered'])} {' '.join(report['uncovered'][:30])}")
    lines.append(f"facts with two values: {', '.join(report['conflicts']) or 'none'}")
    lines += ["", "## To review (did not pass)", "", "| id | status | post text | url |", "|---|---|---|---|"]
    for c in report["claims"]:
        if c["status"] != "ok":
            lines.append(f"| {c.get('id', '')} | {c['status']} | {c.get('post_text', '')} | {c.get('url', '')} |")
    lines += ["", "## Sample of ok claims (spot check the interpretation)", ""]
    lines += [f"- {c.get('id', '')}: {c.get('post_text', '')} — {c.get('url', '')}" for c in sample]
    return "\n".join(lines) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("posts", nargs="+", type=Path)
    ap.add_argument("--cache", type=Path, default=Path(".claims-cache"))
    ap.add_argument("--out-dir", type=Path, help="write <slug>.claims-check.md here (default: next to the post)")
    ap.add_argument("--sample", type=int, default=3)
    ap.add_argument("--offline", action="store_true", help="use only the cache; never fetch")
    args = ap.parse_args()

    failed = False
    for post in args.posts:
        if not post.is_file():
            print(f"not a file: {post}", file=sys.stderr)
            return 2
        report = check_post(post, args.cache, args.offline)
        oks = [c for c in report["claims"] if c["status"] == "ok"]
        sample = random.Random(post.name).sample(oks, min(args.sample, len(oks)))
        out_dir = args.out_dir or post.parent
        out_dir.mkdir(parents=True, exist_ok=True)
        out = out_dir / f"{post.stem}.claims-check.md"
        out.write_text(render(report, sample), encoding="utf-8")
        bad = report.get("error") or report["uncovered"] or report["conflicts"] or any(
            c["status"] != "ok" for c in report["claims"])
        failed = failed or bool(bad)
        print(f"{'FAIL' if bad else 'OK  '} {post} -> {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
