# Knowledge Niches — retrospective of the 2026-10-19 run and the business case

Written by the CTO seat (Claude Code) of the run. The manager was the orchestrator agent (autoclaw);
the junior was Grok 4.6 Extra High Fast through Cursor, on a flat Ultra plan whose quota resets the
same day. Numbers below come from the run's own files (`loop.log`, review markers, verification ledger)
unless a source is linked.

## 1. What the run was

The Cursor quota was at ~2% use with hours left before reset, and the only consumer was a sequential
spec runner. Unused quota is lost at reset, so the question was not "should we spend it" but "what can
it turn into that is still worth something tomorrow".

| Metric | Value |
|---|---|
| Wall time | ~11:00–14:15 (plus loops still running to reset) |
| Agents at peak | 49 (23 niche researchers, 18 writers, reviewers, verifiers, QA) |
| Measured cycles | 571 (the first ~20 minutes were not metered) |
| Tokens metered | 76.4M input · 15.2M output · ~1.03B cache reads |
| Peak burn | ~73M input+output tokens/hour |
| Quota | 2% → 95% of the monthly included Cursor models |

## 2. What it turned into

| Asset | Count | Durable? |
|---|---|---|
| Niches with own SPEC, method and primary sources | 23 | yes, reusable for any store |
| Fact lines with URL and access date (KNOWLEDGE.md) | ~11,200 | yes, with decay (prices) |
| Posts written, passing the structural oracle | 184 | partly: only reviewed ones are trustworthy |
| Posts reviewed and approved | 89 | yes |
| Numbers checked by review | 3,820, of which **644 corrected (16.9%)** | — |
| Posts refined (lint, opening, links) | 13 | yes |
| Broken YAML front matter found and fixed by script | 81 of 184 (44%) | yes, 0 tokens |
| Store-catalog alerts found by content agents | 145 | yes |
| Catalog corrections verified with a second official source | 211: 195 confirmed (92%), 16 adjusted, 0 contested | yes, highest immediate value |
| Lessons distilled for all agents | 15 | yes |
| Code PRs to the store (to `dev`) | 4 (#30–#33) | yes |
| Specs for the next phase (attribution, facts, reward ledger, ads) | 4, gate-validated | yes |
| Open backlog items | 1,595 | raw material, not an asset yet |

The most valuable output was not the blog. Content agents researching their topics kept hitting the
store's own product pages and found that they were wrong: 65 of 94 early alerts were spec sheets that
did not match the manufacturer. That turned a content run into a catalog-quality run.

## 3. How the three seats actually worked

- **CTO (frontier host):** designed the 23 niches, wrote every template and directive, measured every
  10–15 minutes, decided every scale-up and cut, wrote the 4 next-phase specs and reviewed PRs.
- **Manager (autoclaw):** built the first harness (`nichos.sh`, specs generator), fixed it, later
  implemented and opened the code PRs and kept state.
- **Junior (Grok fast):** ran ~570 fresh-session cycles, one item each, from templates.

One seat violation happened and is recorded here on purpose: the CTO started applying catalog
corrections by hand (manager work) and the owner stopped it. The rule that came out of it: the CTO
writes the prompt and the review; the manager writes the code.

## 4. Timeline of decisions

| Time | Decision | Trigger |
|---|---|---|
| 10:55 | 9 parallel research specs | sequential runner had used 2% |
| 11:22 | 10 autonomous niche loops | research fiches were good and cheap |
| 11:36–12:00 | +13 niches (hardware, AI beyond LLMs, futurism, advanced AI, store QA) | quota still barely moving |
| 11:55 | global DIRECTIVE: post quota, question filter, depth cap | backlog 5× faster than drain, almost no post briefs |
| 12:08–12:27 | split roles: researchers stop writing; 6 → 10 → 18 writers | briefs piling up |
| 12:40 | **quality mode**: stop 10 writers, add 6 reviewers + 2 verifiers | 16–17% wrong numbers in first reviews |
| 12:44 | stop 14 research niches + 4 writers | burn too high for the owner's daily target |
| 13:16 | lint loop (Vale, 3 languages), 2 refiners, 1 editor-in-chief | wanted feedback loops, not more volume |
| 13:31–14:05 | down to 5, then 3 agents | quota pacing: 100% before reset otherwise |

## 5. What worked (keep)

1. **Fresh session per item.** No context growth, cache reuse of the shared prefix (~1.7M cache tokens
   per cycle), and a crash loses one item, never the run.
2. **Templates that pass the anti-invention gate before dispatch.** The preflight refused the first
   writer template; after adding verified-data and verification clauses, the junior marked "not
   confirmed" instead of inventing, in all 39 posts of the first sample.
3. **Per-niche method and primary sources.** The niches that found the most store errors (cauda longa,
   NPU, on-device AI, processors) were the ones whose sources were manufacturer spec pages.
4. **Role split with file markers.** `mkdir` claims, one owner per shared file: zero duplicated posts
   and zero lost claims across 18 writers.
5. **Review as the unit of quality.** 7 fixes per post on average; the dominant error was a real number
   cited to a page that does not say it, which no structural oracle can catch.
6. **Second-source verification before any human touches production.** 8% of first-pass catalog
   corrections needed adjustment.
7. **Zero-token mechanisms in the loop:** front-matter fixer, Vale lint loop, RAM guard, local panel.
8. **Measuring before every scale decision.** Every cut and every scale-up was a number, not a feeling.

## 6. What failed or cost us (and the fix)

| Problem | Cost | Fix | Mechanism? |
|---|---|---|---|
| Backoff fired on the word "quota" inside research text | a loop slept 5 min per cycle | grep only error lines | yes (in loop) |
| Panel read one `events.jsonl`, each niche writes its own | owner saw nothing | new multi-agent panel | yes |
| Volume before review | 16.9% wrong numbers shipped to drafts | quality phase triggers in SKILL step 2 | protocol |
| Agents generated questions, not briefs | posts stalled after seed angles ran out | post quota + role split | directive |
| Questions drifted into certificate numbers and CNPJs | tokens with no reader value | question filter + depth cap | directive |
| 44% of posts with invalid YAML front matter | would break the site build | `fix-frontmatter.py` before lint | yes |
| Every approved post carries `{{AFILIADO: x}}` (affiliate placeholder) with no affiliate module | 89 reviewed posts unpublishable | define monetization primitives before writing | **no — next run must start with it** |
| `check-spec.sh` only understands Portuguese gate lines | English templates need `english-ok` blocks | make the gate bilingual | debt |
| Quota pacing ignored the manager's own consumption | under-estimated burn by ~40% | count every consumer | protocol |
| Starting loops with `timeout` cut the first cycle's log line | wrong counts in status | start supervisors with `nohup`, never `timeout` | protocol |
| Store fixes were applied in a script that did not compile (`PRODUCTS` not exported) | review cycle | typecheck in the oracle, or say why it could not run | protocol |

## 7. Distribution thesis: write what the next models will learn from

Hypothesis, not a promise: models are trained on and retrieve from the open web, and generative search
engines cite sources. Pages that are dated, cite primary sources, carry concrete numbers and quotations,
and use stable entity names are more likely to be used and cited.

Evidence: the GEO paper (Aggarwal et al., KDD 2024) reports that optimization methods can raise source
visibility in generative-engine answers by up to 40%, and by up to 37% on a deployed engine (Perplexity);
summaries of the paper attribute the largest gains to adding citations, quotations and statistics
([arXiv 2311.09735](https://arxiv.org/abs/2311.09735v3)). "Up to" is a best case, not an average.

What the mode already does that matches this: every claim with a URL and a date, "not confirmed"
instead of guesses, one number per fact everywhere, per-niche primary sources.
What to add:
- topic selection by **durability × future demand**: concepts that will be asked about for years
  (AI history and concepts, on-device AI, memory for local models, regulation, energy), not news;
- an `llms.txt` and a machine-readable facts endpoint per site;
- the same post in pt-BR, es and en (the lint styles already exist), because training and retrieval are multilingual;
- proxy metrics, measured monthly: citations in AI answers for 20 tracked queries, referral traffic from AI engines, backlinks.

## 8. Ways to earn from it (ordered by dependency)

| # | Channel | Needs first | Metric |
|---|---|---|---|
| 1 | Own store funnel (posts → product pages) | attribution with `content_id` (spec 01) | assisted revenue per post |
| 2 | Catalog quality as a service | the QA + verifier loop already proven | corrections confirmed per product; returns avoided |
| 3 | Email list (one lead magnet per niche: price tracker, checklist, weekly verified digest) | double opt-in and LGPD consent, ESP integration | subscribers per 1k sessions; open rate |
| 4 | Affiliate links, only for programs verified on the official page | affiliate module and disclosure policy (the run's blocker) | EPC per post |
| 5 | Newsletter sponsorship | list above ~5k engaged readers (assumption to validate) | CPM sold |
| 6 | Short video from the 60–90 s scripts the futurism and advanced-AI niches already end with | a video pipeline; channel | views → site sessions |
| 7 | Data products: verified spec and price database, `/facts` API, price-drop alerts | spec 02 (facts with provenance) | paying API users |
| 8 | The harness itself as a product: "content and catalog QA" bundled with the 30-minute store on now.services | porting scripts into this repo; per-store SPEC generator | stores onboarded |
| 9 | Licensing a verified, dated corpus to dataset buyers | legal review; corpus big enough; exclusivity terms | contracts |

Rules for every channel: no unverified claim in an ad or email, disclosure on every affiliate link,
human approval for any spend, production owned by the production agent.

## 9. Next run checklist

1. Monetization primitives exist before writing (affiliate module or no placeholder at all; email capture block).
2. Niches chosen by durability × demand × closeness to revenue; each with method and primary sources.
3. Lint, front-matter fixer, export validator and the claim manifest (`check-claims.py`) run from minute one.
   Keep the workspace outside any git repository (one dispatch lock per git root).
4. Writers and reviewers from the start at a 1:1 ratio; review the oldest first.
5. Pacing table updated at every quota reading, counting every consumer.
6. Store QA niche on from the start: it paid for itself in one afternoon.
7. Close with STATE.md and a report like this one.
