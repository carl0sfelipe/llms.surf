# Visual findings from a storefront screenshot

You are looking at one storefront screenshot. Report what is actually
broken or misleading on that page. Do not invent a bug that is not
visible.

Output: one JSON object, nothing else — no markdown fence, no prose.
When you process several screenshots, write JSONL (one object per line)
to the stage's artifacts directory.

Required keys:

- `screenshot`: the file name of this shot
- `page_guess`: `pdp` | `catalog` | `blog` | `other`
- `broken_images`: array of `{ "area": "...", "reason": "404|empty|placeholder|stretched|other" }`
- `css_issues`: array of `{ "severity": "critical|major|minor", "area": "...", "problem": "..." }`
- `layout_issues`: array of `{ "severity": "critical|major|minor", "problem": "..." }`
- `overall_severity`: `ok` | `minor` | `major` | `critical`
- `summary`: one or two sentences

Empty arrays are allowed. `critical` / `major` only when the bug is
obvious and it hurts purchase or trust. The runtime fails this stage
if the artifacts directory stays empty.
