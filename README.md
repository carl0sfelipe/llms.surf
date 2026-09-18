# llms.surf

*formerly Oracfit*

> **Your frontier plan thinks. Free models sweat.**
> **Nothing ships on a model's word — not even the judge's.**

**The problem:** frontier-model bills that grow like rent — and agents that
say "done" when the work isn't.

**The fix:** one local dispatcher that sends the 1% of tasks that need a
brain to your expensive model, the other 99% to free ones — and accepts no
result until a mechanical oracle proves it on your disk.

Orchestrate work across AI models from the CLIs you already have. Code — not trust — decides what ships.

- Your expensive plan does the 1% that needs a brain; free models do the other 99% for cents.
- Every task carries an **oracle**: a real command that only passes when the work exists.
- Every run shows where the money went — per-provider token accounting, local, yours.
- Every failure becomes an incident; every recurring incident becomes code that refuses. **111 postmortems in this cut.**
- Even the AI judge is watched: one write, and code kills it.

[![License](https://img.shields.io/badge/license-Proprietary-red.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-3.5.0-brightgreen.svg)](VERSION)
[![Incidents](https://img.shields.io/badge/incidents%E2%86%92mechanisms-111-orange.svg)](incidents/)

---

## Try it in 2 minutes — no API key

```bash
git clone https://github.com/carl0sfelipe/llms.surf.git
cd llms.surf
export ORACFIT_ROOT="$PWD" DISPATCH_RUNNER="$PWD/adapters/stub/runner.sh"

bin/llms-surf start     # watch the full loop run on a stub, $0 spent
bin/llms-surf gui       # http://127.0.0.1:8766/home.html — mission control
```

Plug in a real model by sourcing one adapter. Runs inside the CLIs you
already have — opencode, Claude Code, Cursor, Hermes, qwen-code, and more.
Local. Your logs stay yours.

---

## The one idea everything else follows from

```markdown
# Migrate function X to lib Y

## Oracle
grep -q "from lib_y import" src/service.py && pytest tests/test_service.py
```

The oracle **fails before the work exists and passes after**. That single line
turns "I think the agent did it" into an engineering loop: failure becomes
structured feedback for the next attempt, and victory is a green exit code —
never a model's opinion of itself.

Everything a machine can check never even reaches an LLM. AI judges only what
only AI can judge — and when it rejects, it must name the biggest gap or the
rejection doesn't count.

---

## Mechanism > protocol

Two nights made the law.

An AI critic, sent to review work *read-only*, committed the work itself and
hung the orchestrator for two hours. Another night, a dispatched model
touched its own orchestrator's STOP file and shut down the whole run at
07:54 — no human involved. Both are postmortems in this repo. So are 109
others: the framework's memory is `incidents/`, its immune system is `bin/`.

In July this repo had 35 written rules. Then we measured: **every recorded
violation was of a rule that had no code behind it.** In August, overnight
god-mode runs proved something worse — protection that lives in a prompt
degrades *in the very session that wrote it*. The conclusion is the
framework's spine: a rule without a mechanism is debt, not protection.

So every way a model has lied to us now has code that answers:

| A model tries | The code that refuses |
|---|---|
| says "done", exit 0, no work | gates read artifact **content** on disk, never the model's report |
| loops silently at 3am | watchdog kills real silence (zero new bytes); timeout kills the whole process tree |
| "read-only" critic writes | `critic-guard`: first write kills the dispatch, exit 5, incident filed automatically |
| judge approves a truncated verdict | canonical validator: truncated = *broken* (exit 2), never a pass |
| pads ~70 filler lines to beat a line-count oracle | oracles need per-section content greps; "X stays out of V1" needs a **negative** grep |
| edits the goalposts mid-run | the oracle is frozen by sha256 at ring open; changing it requires a declared, critic-approved exception |
| `git add -A` sweeps someone else's tree | close requires explicit pathspec; staging guard refuses foreign files |

Slow model? Not killed — it's writing to its log and the silence counter
resets. Only real silence dies.

---

## What exists today (all measured, nothing hand-waved)

- **Dispatch with fail-closed gates** — spec checks, oracle pre-checks,
  anti-invention scans, watchdog + timeout on every model call. One-shot,
  vertical escalation (flash → pro → opus), or batch with checkpoint+rollback.
- **God modes with rings** — long autonomous sessions where opening and
  closing a work ring is *not the model's decision*: preflight, frozen
  oracle, verdict validation, retest, visual gate, transactional ledger.
- **Perpetuity** — `llms-surf daemon` (double-fork + setsid + pidfile) and the
  prime-agent substrate keep the loop alive across session death; a gate
  holds termination until the ring actually closes green.
- **Human-in-the-loop calibration** — `llms-surf gui` is a local
  mission-control panel (rings, dispatches, live run, incidents, models);
  its calibration page asks you, in plain language, "what score do you give
  this ring, 0–10?" and records your delta against the AI critic in the
  ledger.
- **Usage hub** — token/quota tracking from local sources only, so the
  orchestrator picks the cheapest viable model per task.
- **The memory** — 111 incident postmortems in this cut, 27 models in the registry,
  20 modes, 8 adapters + stub, 37 test suites guarding the guards.

---

## The story so far

- **v1–v2** — dispatch + oracles + the anti-hang protocol. Founding incident:
  52 minutes lost to a silent hang a human had to break.
- **v3** — accountable judges, multi-stage pipelines, mechanical gates. Real
  rings are in `incidents/`. We do not reprint a pipeline-duration anecdote
  as a live metric on this page (see `docs/v4-plan.md`).
- **v3.5** — built-in usage hub; the orchestrator stops guessing quota.
- **v4 (now)** — the night shift. Nine god modes field-tested overnight, each
  with a postmortem; ~90 incidents converged into one spine of fail-closed
  mechanisms: `ring open|close`, canonical verdict validation, `critic-guard`,
  `daemon`, and prime-agent as perpetuity substrate. Full read:
  [docs/v4-plan.md](docs/v4-plan.md).

---

## Start for real

```bash
source adapters/opencode/env.sh        # or claude-code, cursor, hermes, …
bin/llms-surf run normal spec.md my-task # dispatch with oracle + watchdog
bin/llms-surf gui                        # watch it live, score it after
```

Adding your own pipeline is one YAML file (`llms-surf mode init <id>`).
Every failure you hit: `bin/incident.sh new` — that's how the 111 in this cut happened.

---

## Wall quotes

- Victory is a green oracle — not "I tried 8 times".
- Expensive models think; free models sweat.
- A rule without a mechanism is debt, not protection.
- The critic is read-only because code kills it on the first write — not because the prompt asked nicely.
- Rejected without naming the biggest gap? That's not rigor, that's a broken contract.
- Every failure becomes an incident; every incident becomes a mechanism. **111 in this cut.**

---

## Go deeper

| Doc | What's in it |
|---|---|
| [SKILL.md](SKILL.md) | The operating manual: rules that survived the purge, scripts, anti-hang protocol |
| [docs/v4-plan.md](docs/v4-plan.md) | v4: pipeline, swell roadmap, honesty tiers |
| [docs/SMOKE-WITH-FIRE.md](docs/SMOKE-WITH-FIRE.md) | After v1 is live: Fable smokes the site, then dispatches GLM |
| [site/](site/) | Public marketing pages |
| [incidents/](incidents/) | 111 failures that became permanent protections |

Proprietary — all rights reserved · **llms.surf — Carlos Felipe** · pattern: [gauntlet-loop](https://github.com/robonuggets/gauntlet-loop)
