# Context Map — small, true context for future agents

**Goal:** every agent that touches a repo spends tokens to learn where things are and why. Give it a
short `CONTEXT.md` per area whose every factual line points at the code that proves it, check those
pointers with zero model tokens, and **delete** context the moment it stops being true.

Same idea as the claim manifest of `fluxos/knowledge-niches/` (a post's number points at the source
sentence); here a doc sentence points at a file, a symbol, the exact line and a test.

## Why delete, not just update

A line in `CONTEXT.md` is read on every future task. A wrong line costs more than a missing one: the
agent trusts it and builds on it (on 2026-10-19 a skill doc said 10–15 days while the code used 12–18,
and the contradiction shipped to 47 product pages). A missing line costs one search. So the default for
broken context is removal; rewriting is the exception, done by whoever changed the code.

## Format

```markdown
# <area> — what an agent must know before touching it

- Orders inherit the attribution of their cart.
  <!-- claim: path=apps/backend/src/subscribers/order.ts symbol=handleOrderPlaced
       quote="order.metadata.attribution = cart.metadata.attribution"
       test="order.test.ts::copies cart attribution" verified=2026-10-19 -->
- We keep the seed create-only; updates go through explicit scripts.
  <!-- claim: kind=decision -->
```

| key | meaning |
|---|---|
| `path` | file or directory, relative to the repo root (required unless `kind=decision`) |
| `symbol` | name that must still be defined there |
| `quote` | exact code text, matched by content (survives line moves, breaks when the logic changes) |
| `test` | `file::test name` that pins the behavior |
| `verified` | last date a person or agent confirmed the claim |
| `kind=decision` | the "why"; no anchor, never auto-checked or purged — keep these few |
| `stale` | written by the purge when the anchor broke; removed when the claim passes again |

Rules: at most 80 lines per `CONTEXT.md` (`--budget`); one claim per bullet; no prose that restates the code.

## Steps

1. **Write with the change.** Whoever changes code updates the claims of that area in the same PR.
   Specs cite claims (`see apps/backend/CONTEXT.md, claim "Orders inherit…"`) instead of pasting facts.
2. **Gate the PR.** `python3 fluxos/context-map/bin/check-context.py --root . [--coverage 'apps/backend/src/**/*.ts']`
   must exit 0: every pointer resolves, no file over budget, every covered file cited.
3. **Purge on a schedule** (weekly, or before a long agent run):
   `python3 fluxos/context-map/bin/purge-context.py --root .` (dry run, exit 1 if there is work), then `--apply`.
   - dead path → bullet removed now;
   - broken symbol / quote / test, or `verified` older than `--max-age` (180 days) → marked `stale=<date>`;
   - still broken after `--grace` (14 days) → removed;
   - duplicate claim in one file → removed;
   - every removal appended to `PURGE-LOG.md` (and recoverable through git).
4. **Read before exploring.** An agent starting a task reads the `CONTEXT.md` of the area first and only
   greps for what it does not answer. If `check-context.py` is green, the claims can be trusted.

## What stays out

Architecture rationale longer than one line goes to an ADR and is linked as a `kind=decision` claim.
Changelogs, plans and status reports do not belong in `CONTEXT.md`: they age by design.

## Tests

`bash tests/test-context-map.sh` — clean map passes; coverage; broken pointers flagged; dead removed;
stale marked, kept during grace, removed after it; fixed claim unmarked; dry run never writes.

## Limits

Matching is textual: a renamed variable breaks a quote even when behavior is unchanged (that is the
signal to re-verify, by design). It does not run the cited test; CI does. It cannot judge whether a
claim is the *important* thing to say — keeping the file short is what forces that choice.
