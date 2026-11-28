"""Shared parsing for context-map: CONTEXT.md bullets carrying a machine-checkable claim.

A claim is a markdown bullet followed (on the same or next lines) by one HTML comment:

    - Orders inherit the attribution of their cart.
      <!-- claim: path=apps/backend/src/subscribers/order.ts symbol=handleOrderPlaced
           quote="order.metadata.attribution = cart.metadata.attribution"
           test="order.test.ts::copies cart attribution" verified=2026-10-19 -->

Keys: path (required, relative to the repo root), symbol, quote, test ("file::name"),
verified (YYYY-MM-DD), kind (fact | decision; decision = no anchor, never auto-checked),
stale (YYYY-MM-DD, written by purge-context.py when the anchor broke).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

CLAIM_RE = re.compile(r"<!--\s*claim:(.*?)-->", re.S)
PAIR_RE = re.compile(r'(\w+)=("(?:[^"\\]|\\.)*"|\S+)')
BULLET_RE = re.compile(r"^\s*[-*]\s")


@dataclass
class Claim:
    file: Path
    start: int  # first line index of the bullet (0-based)
    end: int  # last line index of the claim comment (inclusive)
    text: str
    keys: dict = field(default_factory=dict)


def parse_keys(raw: str) -> dict:
    keys = {}
    for k, v in PAIR_RE.findall(raw):
        if v.startswith('"'):
            v = v[1:-1].replace('\\"', '"')
        keys[k] = v
    return keys


def parse(file: Path) -> tuple[list[str], list[Claim]]:
    lines = file.read_text(encoding="utf-8").splitlines()
    claims, text = [], "\n".join(lines)
    for m in CLAIM_RE.finditer(text):
        end = text.count("\n", 0, m.end())
        comment_start = text.count("\n", 0, m.start())
        start = comment_start
        while start > 0 and not BULLET_RE.match(lines[start]):
            start -= 1
            if start < comment_start - 20:  # no bullet nearby: claim stands alone
                start = comment_start
                break
        bullet = " ".join(l.strip() for l in lines[start:comment_start + 1] if "<!--" not in l)
        claims.append(Claim(file, start, end, bullet, parse_keys(m.group(1))))
    return lines, claims


def norm(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def check(claim: Claim, root: Path) -> str:
    """Return ok | decision | dead | stale_symbol | stale_quote | stale_test | invalid."""
    k = claim.keys
    if k.get("kind") == "decision":
        return "decision"
    if "path" not in k:
        return "invalid"
    target = (root / k["path"]).resolve()
    if not target.exists():
        return "dead"
    body = target.read_text(encoding="utf-8", errors="replace") if target.is_file() else ""
    if k.get("symbol") and not re.search(rf"\b{re.escape(k['symbol'])}\b", body):
        return "stale_symbol"
    if k.get("quote") and norm(k["quote"]) not in norm(body):
        return "stale_quote"
    if k.get("test"):
        tfile, _, tname = k["test"].partition("::")
        hits = list(root.rglob(Path(tfile).name)) if not (root / tfile).exists() else [root / tfile]
        hits = [h for h in hits if "node_modules" not in h.parts]
        if not hits or (tname and not any(tname in h.read_text(encoding="utf-8", errors="replace") for h in hits)):
            return "stale_test"
    return "ok"


def context_files(root: Path, pattern: str = "CONTEXT.md") -> list[Path]:
    return sorted(p for p in root.rglob(pattern) if "node_modules" not in p.parts and ".git" not in p.parts)
