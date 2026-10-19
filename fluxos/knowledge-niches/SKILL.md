# Knowledge Niches — turning a token budget into verified evergreen knowledge

**Goal:** when there is a large token budget that will be lost if unused (a subscription quota about to
reset, an idle fast model), convert it into assets that keep paying after the tokens are gone:
verified knowledge bases, reviewed educational posts, catalog corrections and lessons — instead of
backlog noise.

Mode: `core/modes/knowledge_niches.yaml`. Retrospective and business case:
`docs/modes/knowledge-niches-retrospective.md`. Role templates: `fluxos/knowledge-niches/templates/`.

## When to use

- A cheap or flat-rate fast model has hours of quota left and no high-value backlog.
- You own (or will own) a site, store or channel where evergreen educational content compounds.
- You can afford one frontier session as CTO for the whole run (it reads, decides, measures; it does not write bulk — rule 1).

Do not use it to produce volume for its own sake. In the first run, volume without review shipped
16.9% wrong numbers.

## Roles

| Role | Who | Does | Never does |
|---|---|---|---|
| CTO | frontier host (e.g. Claude Code) | niche design, specs, directives, measurement, budget pacing, reviews of code PRs, stop/start decisions | bulk writing; editing files another agent owns |
| Manager | orchestrator agent (e.g. autoclaw) | runs the loops, writes the harness code, opens PRs, reports state | production changes; merges |
| Junior | fast flat-rate model (e.g. Grok fast via Cursor) | one backlog item per fresh session, following a template | choosing its own scope |

The junior is paid by the hour whether it works or not: the CTO's job is to keep its hours on the
highest-value work, not to keep it busy.

## Workspace (`$KN_HOME`)

```
niches/
  LOOP.md  DIRECTIVE.md  LESSONS.md  STORE-ALERTS.md  LINT-REPORT.md
  nNN-<topic>/  SPEC.md BACKLOG.md KNOWLEDGE.md DONE.md loop.log posts/ .post/ .review/ .refine/ .lint/
  eNN-writer/ vNN-reviewer/ rNN-refiner/ m01-editor/ qNN-verifier/   (each: _template.md DONE.md loop.log .cycle/)
lint/          Vale config + one style per output language
bin/           niches.sh (loops, RAM guard, backoff) · panel.py · lint-posts.sh · fix-frontmatter.py · export-posts.py
```

Each agent has its own workdir because the dispatch lock is single-flight per workdir.
Shared files are edited by exactly one role; everything else communicates through marker files
(`.post/<id>/claim|done|blocked`, `.review/<slug>/ok|rejected`). Claims use `mkdir`, which is atomic.

## Steps

### 1. Design niches (CTO, ~30 min)
For each niche write a SPEC with: thesis, own products it can point to, affiliate programs to verify,
where to expand, out of scope, **a method that is specific to the niche** (e.g. "payback in months",
"regulation article in every post", "evidence in three layers") and **its own primary sources, in order**.
A niche without its own sources converges to the same generic web pages as every other niche.
Seed each BACKLOG with 4–9 questions and any angles already researched.

### 2. Volume phase (map)
Start one research loop per niche. Measure every 10–15 minutes: posts/hour, briefs/hour, backlog size,
RAM, quota %. Writers start when briefs exist; research agents stop writing posts once writers exist
(split by role, never by luck).

Switch to the quality phase when ANY of these holds:
- free briefs > what writers absorb in 1 hour;
- backlog grows more than 3× faster than it drains;
- a sample review finds more than 10% wrong numbers;
- budget pacing (step 5) says the remaining quota will not last.

### 3. Quality phase (reduce)
Stop most research loops (keep the niches that feed the business directly). Run reviewers on the oldest
posts first, then refiners, the lint loop (zero tokens) and one editor-in-chief that turns repeated errors
into `LESSONS.md`, read by every agent on every cycle. Store QA plus verifiers double-check own-catalog
facts with a second official source before a human applies them.

### 4. Export (human-gated)
Only posts with `.review/<slug>/ok` (ideally `.refine/<slug>/ok`) are exported, linted again and opened
as a PR against a dev branch. Production belongs to whoever owns production.

### 5. Budget pacing (CTO, every reading of the quota)
`rate = Δ% / Δminutes`; `minutes_to_100 = (100 − %) / rate`; compare with time to reset. Count every
consumer of the quota, including the manager itself. Cut the lowest-value consumers first:
research of niches far from revenue → extra writers → extra reviewers → refiners → store QA last.

## Guardrails (mechanism, not protocol)

- RAM guard in the loop: no new cycle below 3.5 GB available; writers back off first.
- Rate-limit backoff only on real error lines (`is_error: true`), never on page text — research about
  pricing mentions "quota" and "429".
- `check-spec.sh` must pass for every template before the first dispatch (preflight refuses otherwise).
- Atomic claims with `mkdir`; one owner per shared file.
- Front matter quoted by script before linting; posts with unresolved placeholders are refused at export.

## HALT

Before stopping: write the state (agents running, counts, open PRs, pending owner decisions) to
`$KN_HOME/STATE.md`, stop loops with `bin/niches.sh stop`, and leave no claim without a `done` or
`blocked` marker.

## Status of this flow

The reference implementation ran on 2026-10-19 under a Portuguese workspace (`nichos/`, `bin/nichos.sh`).
The role templates here are the English, gate-validated versions. Porting the scripts
(`niches.sh`, `panel.py`, `lint-posts.sh`, `seed-niches.py`, `export-posts.py`) into `fluxos/knowledge-niches/bin/`
is the next story; until then the mode's commands expect them under `$KN_HOME/bin/`.
