#!/usr/bin/env python3
"""Render site/blog/posts/*.md into static HTML that matches the site/.doc pages.

Source of truth: markdown + YAML frontmatter in posts/.
Output (checked in, served as-is by GitHub Pages):
  site/blog/index.html
  site/blog/<slug>/index.html

No extra runtime. python3 site/blog/build.py
"""
from __future__ import annotations

import html
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
POSTS = ROOT / "posts"
SITE = ROOT.parent
CANONICAL_HOST = "https://llms.surf"

MARK = """\
<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
  <defs>
    <symbol id="ls-mark" viewBox="26 64 158 58">
      <path d="M32 116 C48 116 58 113 70 102 C82 91 92 76 106 72.5 C118 69.5 128 76 129 85 C129.6 90.5 127 95 123 96.5" fill="none" stroke="#22D3EE" stroke-width="6" stroke-linecap="round"/>
      <path d="M124.5 112.5 C112 117 99.5 110 99.5 99.5 C99.5 89.5 107.5 83 115.5 84.2 C120.5 85 123.5 88 124.6 91.5" fill="none" stroke="#22D3EE" stroke-width="6" stroke-linecap="round"/>
      <circle cx="135.5" cy="110.5" r="4.6" fill="#3FB950"/>
      <path d="M145.5 103.5 L153.5 112 L175.5 88.5" fill="none" stroke="#3FB950" stroke-width="8.5" stroke-linecap="round" stroke-linejoin="round"/>
    </symbol>
  </defs>
</svg>
"""

HEAD_FONTS = """\
<link rel="preconnect" href="https://cdn.jsdelivr.net" crossorigin>
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5.1.2/latin-400.css" media="print" onload="this.media='all'">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/jetbrains-mono@5.1.2/latin-700.css" media="print" onload="this.media='all'">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/inter@5.1.1/latin-400.css" media="print" onload="this.media='all'">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/inter@5.1.1/latin-600.css" media="print" onload="this.media='all'">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/@fontsource/inter@5.1.1/latin-700.css" media="print" onload="this.media='all'">
"""


def parse_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---"):
        raise SystemExit("post missing YAML frontmatter")
    parts = text.split("---", 2)
    if len(parts) < 3:
        raise SystemExit("unterminated frontmatter")
    meta: dict = {}
    key = None
    for raw in parts[1].strip().splitlines():
        if raw.startswith("  - "):
            if key is None:
                raise SystemExit("list item without key")
            meta.setdefault(key, [])
            if not isinstance(meta[key], list):
                meta[key] = []
            meta[key].append(raw[4:].strip().strip('"'))
            continue
        if ":" not in raw:
            continue
        key, val = raw.split(":", 1)
        key = key.strip()
        val = val.strip()
        if val == "":
            meta[key] = []
        else:
            if (val.startswith('"') and val.endswith('"')) or (
                val.startswith("'") and val.endswith("'")
            ):
                val = val[1:-1]
            meta[key] = val
    return meta, parts[2].lstrip("\n")


def required(meta: dict, *keys: str) -> None:
    missing = [k for k in keys if not meta.get(k)]
    if missing:
        raise SystemExit(f"frontmatter missing {missing}")


def inline(text: str) -> str:
    holes: list[str] = []

    def stash(fragment: str) -> str:
        holes.append(fragment)
        return f"\x00H{len(holes) - 1}\x00"

    def code_span(m: re.Match) -> str:
        return stash(f"<code>{html.escape(m.group(1))}</code>")

    def link(m: re.Match) -> str:
        label = inline(m.group(1))
        href = html.escape(m.group(2), quote=True)
        extra = ' rel="noopener"' if href.startswith("http") else ""
        return stash(f'<a href="{href}"{extra}>{label}</a>')

    text = re.sub(r"`([^`]+)`", code_span, text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link, text)
    text = html.escape(text)
    text = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", text)
    text = re.sub(r"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)", r"<em>\1</em>", text)
    text = re.sub(r"\x00H(\d+)\x00", lambda m: holes[int(m.group(1))], text)
    return text


def is_table_sep(line: str) -> bool:
    return bool(re.match(r"^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$", line))


def split_row(line: str) -> list[str]:
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    return [c.strip() for c in line.split("|")]


def render_table(rows: list[str]) -> str:
    header = split_row(rows[0])
    body = [split_row(r) for r in rows[2:]]
    th = "".join(f"<th scope=\"col\">{inline(c)}</th>" for c in header)
    trs = []
    for cells in body:
        tds = "".join(f"<td>{inline(c)}</td>" for c in cells)
        trs.append(f"<tr>{tds}</tr>")
    return (
        '<div class="table-wrap"><table>'
        f"<thead><tr>{th}</tr></thead>"
        f"<tbody>{''.join(trs)}</tbody>"
        "</table></div>"
    )


def render_md(src: str) -> str:
    lines = src.replace("\r\n", "\n").split("\n")
    out: list[str] = []
    i = 0
    n = len(lines)

    def flush_para(buf: list[str]) -> None:
        if buf:
            out.append("<p>" + inline(" ".join(buf)) + "</p>")
            buf.clear()

    para: list[str] = []
    while i < n:
        line = lines[i]
        if line.startswith("```"):
            flush_para(para)
            lang = line[3:].strip()
            i += 1
            fence: list[str] = []
            while i < n and not lines[i].startswith("```"):
                fence.append(lines[i])
                i += 1
            i += 1
            code = html.escape("\n".join(fence))
            title = html.escape(lang) if lang else "code"
            out.append(
                '<div class="term">'
                f'<div class="term-bar"><span class="dot r"></span><span class="dot a"></span>'
                f'<span class="dot g"></span><span class="term-title">{title}</span></div>'
                f'<pre class="term-body"><code>{code}</code></pre></div>'
            )
            continue
        if is_table_sep(lines[i + 1] if i + 1 < n else "") and "|" in line:
            flush_para(para)
            block = [line, lines[i + 1]]
            i += 2
            while i < n and "|" in lines[i] and lines[i].strip():
                block.append(lines[i])
                i += 1
            out.append(render_table(block))
            continue
        if re.match(r"^#{1,3} ", line):
            flush_para(para)
            level = len(line) - len(line.lstrip("#"))
            out.append(f"<h{level}>{inline(line[level + 1 :])}</h{level}>")
            i += 1
            continue
        if re.match(r"^-{3,}\s*$", line):
            flush_para(para)
            out.append("<hr>")
            i += 1
            continue
        if line.startswith("> "):
            flush_para(para)
            q: list[str] = []
            while i < n and lines[i].startswith("> "):
                q.append(lines[i][2:])
                i += 1
            out.append(
                f'<blockquote class="quote"><p class="q-text">{inline(" ".join(q))}</p></blockquote>'
            )
            continue
        ul = re.match(r"^[-*] (.+)$", line)
        ol = re.match(r"^(\d+)\. (.+)$", line)
        if ul or ol:
            flush_para(para)
            kind = "ul" if ul else "ol"
            items: list[str] = []
            while i < n:
                m = re.match(r"^[-*] (.+)$", lines[i]) if kind == "ul" else re.match(
                    r"^\d+\. (.+)$", lines[i]
                )
                if not m:
                    break
                items.append(f"<li>{inline(m.group(1))}</li>")
                i += 1
            out.append(f"<{kind}>{''.join(items)}</{kind}>")
            continue
        if not line.strip():
            flush_para(para)
            i += 1
            continue
        para.append(line.strip())
        i += 1
    flush_para(para)
    return "\n".join(out)


def page(
    *,
    lang: str,
    title: str,
    description: str,
    canonical: str,
    prefix: str,
    crumb: str,
    body: str,
    extra_head: str = "",
) -> str:
    desc = html.escape(description)
    tit = html.escape(title)
    return f"""<!doctype html>
<html lang="{html.escape(lang)}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{tit} — llms.surf</title>
<meta name="description" content="{desc}">
<meta name="color-scheme" content="dark">
<meta name="theme-color" content="#0B0E14">
<link rel="canonical" href="{html.escape(canonical)}">
<link rel="icon" type="image/svg+xml" href="{prefix}logo.svg">
<link rel="icon" type="image/png" href="{prefix}logo.png">
<link rel="alternate" type="text/plain" href="{prefix}llms.txt" title="llms.txt — agent surface">
<meta property="og:type" content="article">
<meta property="og:site_name" content="LLMs.surf">
<meta property="og:title" content="{tit}">
<meta property="og:description" content="{desc}">
<meta property="og:url" content="{html.escape(canonical)}">
<meta property="og:image" content="{prefix}og.png">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{tit}">
<meta name="twitter:description" content="{desc}">
<script src="{prefix}journey.js" data-key="llms.surf.journey"></script>
<style>html,body{{background:#0B0E14;color:#E6EDF3;color-scheme:dark}}</style>
<link rel="stylesheet" href="{prefix}styles.css?v=2">
{HEAD_FONTS}
{extra_head}
</head>
<body>
{MARK}
<header class="nav">
  <div class="wrap nav-in">
    <a class="logo" href="{prefix}index.html" aria-label="llms.surf — home">
      <svg class="logo-mark" aria-hidden="true"><use href="#ls-mark"></use></svg>
      <span class="logo-word">llms.surf</span>
    </a>
    <nav class="nav-links" aria-label="Site">
      <a href="{prefix}index.html#loop">oracle loop</a>
      <a href="{prefix}blog/">blog</a>
      <a href="{prefix}incidents.html">incidents/</a>
      <a href="{prefix}readme.html">README</a>
    </nav>
    <div class="journey" data-journey-ui>
      <span class="journey-kicker">who is reading</span>
      <div class="journey-seg" role="group" aria-label="Choose human or agent journey">
        <button type="button" class="journey-btn" data-as="human" aria-pressed="false">human</button>
        <button type="button" class="journey-btn" data-as="agent" aria-pressed="false">agent</button>
      </div>
      <a class="journey-llms" href="{prefix}llms.txt">llms.txt</a>
    </div>
    <a class="btn btn-sm" href="{prefix}index.html#quickstart">paddle out</a>
  </div>
</header>
<main class="doc">
  <p class="doc-crumb">{crumb}</p>
{body}
  <div class="doc-links">
    <a class="btn btn-ghost" href="{prefix}index.html">← front page</a>
    <a class="btn btn-ghost" href="{prefix}blog/">blog</a>
    <a class="btn btn-ghost" href="{prefix}readme.html">README</a>
    <a class="btn btn-ghost" href="{prefix}incidents.html">incidents/</a>
  </div>
</main>
<footer class="footer">
  <div class="wrap foot-grid">
    <div class="foot-brand">
      <a class="logo" href="{prefix}index.html" aria-label="llms.surf — home">
        <svg class="logo-mark" aria-hidden="true"><use href="#ls-mark"></use></svg>
        <span class="logo-word">llms.surf</span>
      </a>
      <p class="foot-surf">Built in Saquarema, Brazil — where you never paddle on a guess. Neither do we.</p>
    </div>
    <nav class="foot-links" aria-label="Project links">
      <a href="{prefix}llms.txt">llms.txt</a>
      <a href="{prefix}blog/">blog</a>
      <a href="{prefix}readme.html">README</a>
      <a href="{prefix}incidents.html">incidents/</a>
      <a href="{prefix}v4-plan.html">docs/v4-plan.md</a>
      <a href="https://github.com/carl0sfelipe/llms.surf">github</a>
    </nav>
  </div>
</footer>
<script src="{prefix}app.js" defer></script>
</body>
</html>
"""


def load_posts() -> list[dict]:
    posts = []
    for path in sorted(POSTS.glob("*.md")):
        meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
        required(meta, "title", "date", "slug", "description")
        meta["tags"] = meta.get("tags") or []
        meta["lang"] = meta.get("lang") or "en"
        meta["author"] = meta.get("author") or ""
        meta["canonical"] = meta.get("canonical") or f"{CANONICAL_HOST}/blog/{meta['slug']}"
        meta["body"] = body
        meta["source"] = path.name
        posts.append(meta)
    posts.sort(key=lambda p: p["date"], reverse=True)
    return posts


def write_post(post: dict) -> None:
    dest = ROOT / post["slug"]
    dest.mkdir(parents=True, exist_ok=True)
    tags = " · ".join(html.escape(t) for t in post["tags"])
    meta_bits = [html.escape(post["date"])]
    if post["author"]:
        meta_bits.append(html.escape(post["author"]))
    if tags:
        meta_bits.append(tags)
    article = (
        f'  <h1>{html.escape(post["title"])}</h1>\n'
        f'  <p class="doc-sub blog-meta">{" · ".join(meta_bits)}</p>\n'
        f'{render_md(post["body"])}\n'
    )
    crumb = (
        f'<a href="../../index.html">llms.surf</a> / '
        f'<a href="../">blog</a> / {html.escape(post["slug"])}'
    )
    html_out = page(
        lang=post["lang"],
        title=post["title"],
        description=post["description"],
        canonical=post["canonical"],
        prefix="../../",
        crumb=crumb,
        body=article,
    )
    (dest / "index.html").write_text(html_out, encoding="utf-8")


def write_index(posts: list[dict]) -> None:
    items = []
    for p in posts:
        tags = "".join(f'<span class="chip">{html.escape(t)}</span>' for t in p["tags"])
        items.append(
            '<article class="blog-item">'
            f'<p class="blog-meta">{html.escape(p["date"])}'
            + (f' · {html.escape(p["author"])}' if p["author"] else "")
            + "</p>"
            f'<h2><a href="{html.escape(p["slug"])}/">{html.escape(p["title"])}</a></h2>'
            f'<p>{html.escape(p["description"])}</p>'
            f'<p class="chips">{tags}</p>'
            "</article>"
        )
    body = (
        "  <h1>blog</h1>\n"
        '  <p class="doc-sub">writing from the dispatcher — same facts as the tree, no invented numbers.</p>\n'
        + "\n".join(items)
    )
    html_out = page(
        lang="en",
        title="blog",
        description="llms.surf blog: harness notes, oracle discipline, and measured runs.",
        canonical=f"{CANONICAL_HOST}/blog",
        prefix="../",
        crumb='<a href="../index.html">llms.surf</a> / blog',
        body=body,
    )
    (ROOT / "index.html").write_text(html_out, encoding="utf-8")


def main() -> None:
    posts = load_posts()
    if not posts:
        raise SystemExit("no posts in site/blog/posts/")
    for p in posts:
        write_post(p)
        print(f"ok post /blog/{p['slug']}/  ←  posts/{p['source']}")
    write_index(posts)
    print(f"ok index /blog/  ({len(posts)} post(s))")


if __name__ == "__main__":
    main()
