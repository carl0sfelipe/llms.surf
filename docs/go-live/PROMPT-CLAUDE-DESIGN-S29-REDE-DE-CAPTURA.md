# PROMPT — Claude Design round 2 (bestmodel): A REDE DE CAPTURA (4 páginas)

> Como usar: cole ESTE arquivo inteiro no Claude Design (Opus). Ele é
> autocontido — não precisa abrir repositório. O anexo único é o
> `assets/theme.css` do site atual (fim deste documento há a instrução de
> anexo; NADA mais).

## CONTEXT (read first)

bestmodel.run is becoming a **proof network for local-AI benchmarks**.
Today, benchmark numbers live scattered and unproven across Reddit,
Twitter, GitHub and blogs. Our machine already exists in production:

- **Claims** — anyone registers a number + hardware they found or did;
  it is born class `reported` (honest badge, excluded from rankings).
- **Votes** — the community judges plausible / impossible.
- **Signed runs** — a CLI run signed with a per-user Ed25519 key settles
  a claim into `settled_verified` (cryptographic proof).
- **Reports** — "this run is unreal": a moderator reviews; a confirmed
  fake marks the claim `refuted` and credits the reporter (+5 points).
- **551 community cells** already imported with verified provenance
  (550/550 metrics identical to the source snapshot — checked, not presumed).

Round 1 of this redesign delivered a static directory skin. **The owner
rejected it as a replacement** — his existing site wins on design. This
round delivers ONLY the four social pages that are missing, **in the
existing site's design language**. You are designing organs for a living
body, not a new body.

## NON-NEGOTIABLES (same as round 1, plus one learned the hard way)

1. **MOBILE-FIRST.** Every page works beautifully at 360px. No min-width
   gating of any kind. Feature queries only.
2. **HONESTY.** Numbers render ONLY from live API responses (contracts
   below). Today production has **zero contributors and zero signed
   runs** — empty states are REQUIRED and must be beautiful and honest
   ("the wall fills as people post"). Sample data is allowed ONLY in a
   clearly-badgeable `SAMPLE` fixture mode that never renders as real.
   No price, no dates, no invented counts, never imply a community exists.
3. **OUTPUT.** Pure HTML/CSS/JS, no build step, no frameworks, no npm.
   Relative paths. Works under Vercel cleanUrls (no trailing slash).
4. **THE DESIGN IS THE EXISTING SITE — evolve, never replace.** The
   attached `theme.css` is the law: tokens `--bg:#0B0C0E`, surfaces
   `--surface/--surface-2/--surface-3`, hairline borders `--hair`,
   accent `--amber:#E0A458`, status `--green/--red`, fonts Inter /
   Inter Tight / JetBrains Mono, mono for all data. The site's visual
   grammar is a **scroll narrative of scenes** (`.scene`, `.on` reveal
   classes, staged transitions) with `--mono` microcopy. Reuse it. Do
   not introduce a new grid system, new hero pattern, or new palette.
5. **THE UX LAW (round-1 defect — this is the owner's #1 complaint).**
   In the goal selector, **intent/modality, machine/rig and quantisation
   are ALWAYS separate controls, never merged, never folded into one
   option list**. A visitor must never see "Reference rig A" and "turn
   text into text" competing in the same dropdown or the same chip row.
   Each dimension gets its own labelled control, in this order:
   what-it-does → what-machine → quantisation → context. Any page that
   filters models must follow this law.

## THE 4 PAGES (deliver exactly these files)

All data comes from the same-origin API (Vercel rewrites `/v1/*` to the
backend; base URL = `""`). Session token: `localStorage.bm_token` (the
existing console issues it; these pages READ it, they never re-implement
auth — a "sign in" CTA links to `/console`).

### 1. `claims.html` — The Wall (public capture feed)

`GET /v1/claims?status=open|settled_verified|refuted|retracted&sort=recent|controversial|strongest&limit=25&offset=0`
→ JSON array of claims. Exact row shape (render these fields, no others):

```json
{
  "id": "uuid",
  "claimant_handle": "string or null (null = localmaxxing pool import)",
  "source": "localmaxxing or null",
  "external_ref": "string or null",
  "model_release_id": "string",
  "quantization_profile_id": "string or null",
  "gpu_model_id": "string or null",
  "context_tokens": 32768,
  "claimed_metrics": { "decode_tok_s": 41.5, "prefill_tok_s": 940, "ttft_ms": 733, "peak_vram_mib": 23040 },
  "note": "string or null",
  "source_url": "https://reddit.com/... or null",
  "status": "open | settled_verified | refuted | retracted",
  "prior_snapshot": { "pool": { "basis": "measured", "p50_decode_tok_s": 38.2, "run_count": 4 } },
  "created_at": "2026-08-31T00:00:00+00:00",
  "tally": { "plausible_count": 3, "impossible_count": 1, "margin": 50, "voter_count": 4 }
}
```

Design requirements:
- **`source_url` is the hero of this page**: when present, render a
  provenance chip "found on reddit.com / x.com / github.com …" linking
  out (domain extracted, favicon-free, mono font). This is the product:
  unproven numbers from the wild, captured with their origin.
- Status badges using existing semantics: `open` (amber), 
  `settled_verified` (green, "measured"), `refuted` (red), `retracted` (dim).
- The engine's honest cross-signal when `prior_snapshot.pool` exists:
  "engine says: measured 38.2 tok/s median on this class of rig" — the
  claimed number NEXT TO the engine's basis, never blended.
- Filter chips (status) + sort select + offset pagination ("load more").
- Fixed CTA to `submit.html`: "found a run in the wild? capture it".
- Empty state (production truth today): a beautiful, honest
  "the wall is empty — be the first to capture a run" — never fake rows.

### 2. `claim.html` — Claim detail (`?id=<uuid>`)

- `GET /v1/claims/{id}` → same row shape + full `tally` and
  `prior_snapshot` (roofline branch: `prior_snapshot.roofline.expected_decode_tok_s`,
  basis "formula").
- Sections: the claimed numbers (big, mono) · the source (source_url chip
  or "self-reported") · the engine's honest cross-signal · votes block ·
  actions.
- **Vote** (only with token; `POST /v1/claims/{id}/votes`,
  body `{"verdict":"plausible"|"impossible"}`; 401 → sign-in CTA;
  self-vote 409 → show API message). Show tally as a margin bar.
- **⚑ Report** (`POST /v1/claims/{id}/reports`, body
  `{"reason_category":"numbers_unreal|wrong_hardware|wrong_model|duplicate|other","reason_detail":"≤1000"}`;
  401 → "sign in to report"; 409 → API explains open/duplicated or
  dismissed case). Modal matches the console's pattern. A confirmed
  report = "fake caught, +5 points" — say it in the modal, it is the
  mechanic that keeps the pool honest.
- **Settle block** (status open): the exact command
  `benchmark-probe upload --settle-claim <id>` in a copyable code chip —
  "prove it with a signed run".
- Hidden/degraded states: 404 ("no such claim"), refuted (red banner,
  report credited), settled_verified (green banner "verified by signed
  run", show `benchmark_run_id` short form).

### 3. `submit.html` — The capture funnel

- Headline concept: **"Found a benchmark in the wild? Give it a home
  with provenance."** (numbers without origin are noise; here they get
  a source, votes and a path to proof).
- Form fields (exact API contract `POST /v1/claims`, Bearer
  `localStorage.bm_token`, `Content-Type: application/json`):
  - `source_url` — REQUIRED when "I found it online" is selected;
    optional if "I ran it myself" (toggle segmented control, two modes —
    separate controls, UX law). Validated http(s) client-side.
  - `model_release_id` — select populated from the frozen index the site
    already ships (`data/derived/models.json`), grouped by modality
    (UX law: its own labelled control).
  - `claimed_metrics.decode_tok_s` — required, number.
  - optional: `quantization_profile_id`, `gpu_model_id`, `context_tokens`, `note`.
- Without a token: the form renders disabled with a single honest CTA
  "sign in to capture → /console". Never post unauthenticated.
- Success state: the created claim's card + links to the wall and the
  detail page. Failure states surface the API's `detail` message verbatim.

### 4. `profile.html` — Track record of a contributor (`?handle=...`)

- `GET /v1/users/{handle}` → exact shape:
```json
{
  "handle": "string", "display_name": "string", "created_at": "…",
  "reputation": { "points": 0, "tier": "L0", "updated_at": null },
  "badges": [ { "…": "…" } ],
  "follow": { "followers": 0, "following": 0, "viewer_is_following": false },
  "rigs": [ { "slug": "…", "nickname": "…", "is_public": true, "created_at": "…" } ]
}
```
- The Track Record ladder rendered from REAL signals only: validated
  signed runs (`benchmark_run` via badges/API), reports credited — **if
  the signal is absent, the level renders as "not yet", never hidden**.
  Ladder copy (frozen, from the owner's approved copy): Contributor →
  Replicator → Auditor; "granted by a verified act; levels are not
  self-declared and do not decay; every act is attributable to an
  Ed25519 key."
- Follow button (`POST/DELETE /v1/users/{handle}/follow`, token; 401 →
  sign-in CTA). Rigs listed only when `is_public`.
- 404 state: "no such handle".

## AUTO-AUDIT (do this before answering — rounds, not suggestions)

Round 1 — every page at 360px AND 1440px: no horizontal scroll, no
min-width gate, selects never merge dimensions (UX law), touch targets
≥44px, mono numerals aligned.
Round 2 — honesty sweep: with the API returning zeros, does ANY page show
a number that the API did not produce? (If yes: delete it.) Are empty
states rendered? Is `source_url` the hero of the wall?
Round 3 — purity: zero frameworks, zero npm, zero external requests
(fonts are already on the site), relative paths, cleanUrls-safe links
(no trailing slashes), token read from `localStorage.bm_token` only.
Report the audit as a table in your delivery notes.

## OUTPUT

One zip: `bestmodel-social/` containing
`claims.html`, `claim.html`, `submit.html`, `profile.html`,
`assets/social.css`, `assets/social.js`, `data/fixtures.sample.json`
(SAMPLE-badged, clearly `_sample: true`, used only when the API is
absent — mirroring the round-1 pattern the owner praised). Delivery
notes = audit table + list of files. Nothing else: do NOT redeliver
index/leaderboard/hardware/track-record; do NOT touch the existing site.

## ATTACHMENT

One file, ready to copy: `apps/web/site/assets/theme.css` from the
current site (the owner will attach it). Treat it as the brand law —
extend it via `social.css` (new blocks only); never redefine existing
tokens.
