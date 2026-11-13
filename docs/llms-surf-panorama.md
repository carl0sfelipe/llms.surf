# llms.surf — panorama for a newcomer

*A pitch and a map. Written for someone (human or agent) who has never
seen this project and wants to give useful advice about it.*

## The pitch in one paragraph

llms.surf is an open-source dispatcher that sends work to AI models and
then **judges the result mechanically**. You write a *spec*; a runner
(model + CLI) attempts it; an *oracle* — a script, a test suite, a
deterministic check — decides pass or fail; a failed attempt produces
structured feedback that goes back into the next attempt's spec. The
model proposes, the oracle disposes. The whole thing is bash plus a
small Rust core, with an incident corpus and a rule set that turn every
recurring failure into a mechanism. It exists because the expensive,
boring, high-leverage part of using an agent is not the generation — it
is the *loop* around it: knowing what failed, why, and what to change so
the next attempt does not fail the same way.

## The one sentence that matters

> **The mechanical oracle decides, not the model.**

Everything else follows. The model never marks a stage green. The
dispatcher never asks "do you think this is good?". If the oracle is
absent, the stage fails — there is no path where a confident model
overrules a missing check.

## How a run actually goes

```
spec.md ──► compose ──► runner (model + CLI) ──► artifacts ──► oracle
                 ▲                                                   │
                 │                                    fail ─────────┘
                 │                                     │
                 └── feedback block + ground truth ──┘   (next attempt, same stage)
```

- **spec** — the work, in prose, with an `## Oracle` section naming the
  command that proves it and the expected exit code.
- **compose** — the dispatcher builds the spec the runner actually
  receives: base spec + previous stage output + `## GROUND TRUTH` +
  accumulated `## GAUNTLET FEEDBACK` + the owner's message.
- **runner** — a CLI (Claude Code, Cursor, opencode, …) with tools, in a
  workdir it may roam.
- **oracle** — the check. A suite that must exit 0, a file that must
  exist, a schema that must validate.
- **feedback** — on failure, the oracle's own output (up to 4000 chars),
  the exit code, and "the single biggest remaining gap" are injected into
  the next attempt's spec.

Two runtimes implement this: `bin/dispatch-stages.sh` (multi-stage: map →
reduce → …, with the elevate/unlock tier) and `bin/dispatch-mode.sh`
(single-stage). Both honour the same mode grammar, the same gauntlet,
the same events, the same exit codes.

## The parts

| Part | Where | What it is |
|---|---|---|
| Hexagonal core | `kernel/dispatch-policy` (Rust), `kernel/laws/P1.md` | the typed policy core; its laws are sampled as universally quantified properties by proptest (`kernel/dispatch-policy/tests/laws.rs`) |
| Edge | `bin/*.sh`, `bin/*.py` | bash adapters: events, metrics, ledger, lock, gauntlet, rate limit, prompt template |
| Modes | `core/modes/*.yaml` (21) | the grammar of a workflow: stages, models, artifacts, oracle, retries |
| Adapters | `adapters/<cli>/` | per-CLI trajectory translators into one event stream |
| Events & ledger | `.dispatch/logs/events.jsonl`, `.dispatch/ledger/mode.jsonl` | what happened, and what it cost |
| Gauntlet | `bin/lib-oracfit-gauntlet.sh` | the feedback loop: attempts, feedback injection, ground truth |
| Incidents | `incidents/` (126 postmortems) | the corpus; each is a symptom, a cause, a correction |
| Rules | `fluxos/_comum/mapa-regras.md` (55; 27 of class `R`) | what became a mechanism (class C) and what still needs judgment (class R) |
| Panel | `panel/`, `bin/oracfit-panel*.sh` | live view of runs, events, ledger |
| Ring | `bin/oracfit-ring.sh` | the calibration loop: predicted owner score vs real owner score |

## The vocabulary

| Word | Meaning |
|---|---|
| **mode** | a whole workflow, YAML, with stages |
| **stage** | one step of a mode, with its own model, oracle and retries |
| **spec** | the prose task handed to a runner |
| **oracle** | the deterministic check that decides pass/fail |
| **attempt** | one run of one stage; the gauntlet allows several |
| **gauntlet** | the attempt loop + feedback injection + safety ceiling |
| **incident** | a postmortem with a symptom, a cause, a correction |
| **rule** | a numbered law of the repo; numbering is immutable |
| **mechanical mode** | `normal` (surf alias `paddle`) — cheap, oracle-driven |
| **elevate mode** | `unlock_plan` (surf alias `tow`) — buys the expensive tier before spending it |
| **custom modes** | `oracfit mode init/validate/lint/show/share/add`, `oracfit spec init` |

## The flywheel

The intended loop is not "call a model". It is:

```
local model → trajectory → incident → rule → mechanism → fewer wasted attempts
```

A model fails in a way nobody anticipated. That failure becomes an
incident. A recurring failure becomes a **mechanism** (a test, a gate, a
rule) — that is rule 16. The mechanism then prevents the failure class
from ever costing another attempt. The local model is the dev assistant:
it is dispatched like any other runner, it roams the workdir, and its
trajectory is the raw material of the loop.

## The three modes that matter right now

- **mechanical** (`normal` / `paddle`) — cheap models, oracles decide,
  retries are cheap. This is the workhorse.
- **elevate** (`unlock_plan` / `tow`) — spend the expensive unlock *once*,
  before burning tokens on a plan that has no grounding. The previous
  stage's output feeds the next stage (`input: prev_stage`); the
  elevate stage writes the artifact the plan stage needs
  (`artifacts:`); the plan stage declares its prompt
  (`prompt_template:`). Every one of those was, at some point, a field
  the loader accepted and no runtime consumed — the interesting failures
  in this repo are exactly that shape.
- **custom modes** — the flywheel for other people: `mode init` from a
  template, `validate`/`lint`, `show`, `share`, `add`.

## What is being built right now: the decision supervisor

A supervisor that watches runs and helps the next attempt. The design
lives in `docs/decision-supervisor.md`; the short version:

- **Capture continuously, decide at three choke points.** The
  pre-flight (before attempt 1), the attempt boundary (after the oracle
  verdict), the post-loop (when the run ends). Not a continuous observer
  — a continuous observer poisons its context and replaces determinism
  with probability.
- **Four layers.** L0 deterministic state vector (this already exists:
  `bin/oracfit-behavior-scan.py`, tiers B1–B8, advisory only) → L1
  candidate retrieval (regex + CPU cross-encoder, **filters the gotcha
  bank, never decides**) → L2 calibrated arbitration (a decision model
  over typed options, with abstention, served by llama.cpp's
  `/v1/systemone`) → L3 safe execution (snapshot / scoped restore /
  `exit 7` + `owner_question`).
- **The unit of memory is a gotcha triad** — trigger, symptom,
  prescription. The corpus exists (126 incidents in prose); the *trigger*
  does not. That is the gap: prose cannot fire.
- **The API is already standardized.** llama.cpp merged
  `POST /v1/systemone` (PR #29818, 2026-10-02) for five decision models,
  from 0.17 GB to 3.03 GB on CPU; Eikos ships a TypeSafe-compatible
  server with the same shape. One adapter, two backends.
- **The ladder** is 12 rungs, each a dispatchable spec with an oracle:
  evidence on abnormal exit → tool-call arguments → the triad → the
  deterministic matcher → the safe reset → the telemetry fix → the
  semantic matcher → the question set → the supervisor adapter → the
  policy decision → the distiller → the dev assistant as a runner.

## The state of the world, with sources

| Fact | Value | Where |
|---|---|---|
| Version | 0.4.1 | `VERSION` |
| Incidents | 126 | `incidents/*.md` |
| Rules | 55, of which 27 class `R` | `fluxos/_comum/mapa-regras.md` |
| Modes | 21 | `core/modes/*.yaml` |
| Test suites | 53 | `tests/` |
| Models in the registry | 30 | `model-registry.json` |
| Host | 1× RTX 3090 (24 GB), Ryzen 5 3500X, 32 GB RAM | measured 2026-11-12 |

## The culture (this is the part that changes how advice is received)

- **All code is English** — names, identifiers, comments, log lines,
  CLI messages (`bin/check-english.py`). `incidents/` and `docs/stories/`
  are Portuguese on purpose.
- **A spec must declare its verified data and forbid invention**
  (`bin/check-spec.sh`). The clause exists because specs without it
  produce plausible numbers out of blank fields — measured on 14
  dispatches. A field that is not decided is marked `[A DEFINIR]`, never
  blank.
- **Rule 16** — a recurring failure becomes a mechanism (a test, a gate).
  A rule without a mechanism is debt.
- **Rule 32** — a claim points at a mechanism that exists. "The loader
  accepts the field" is not evidence that anyone reads it.
- **Rule 47** — the orchestrator's control files never live in the
  dispatched workdir (`core/protected-paths-default.txt`).
- **Rule 48** — never edit in place a script a live run is executing; it
  moves the bytes under the runner and kills it.
- **The public cut is gated** (`bin/check-publico.sh`): no phone numbers,
  no third-party e-mail, no personal machine paths in code.
- **Counts in README/site derive from the tree** (`bin/check-docs.sh`).
  Change the tree, change the numbers in the same commit.

## What is open, and what is not mine to decide

The owner's open decision (D1) is the serving topology: Eikos-27B on one
GPU and Qwen-27B on another card on the same board, versus serving the
decision model on **CPU** (llama.cpp + a small GGUF), which needs no
second card, no PSU measurement, and no RAM headroom. The measurement
that settles it is a single one: build llama.cpp for CPU and time one
`/v1/systemone` call on this 3500X at ~250/~750/~1500 tokens of state.

Everything else in the ladder above runs on bash and Python. Do not
pretend the model decision is on the critical path for the first eight
rungs — it is not.

## What kind of hint is useful here

Good:

- a mechanism that **already exists** in the tree, named by file and
  line — the previous critique was right that "the gauntlet feedback
  injection" *is* the interception channel, and that was worth a lot;
- a prior art with an identifier (arXiv id, PR number, HF repo) that
  can be checked;
- a correction of a **measurement** — "your snapshot recipe captures the
  index, not the working tree" was worth more than any amount of
  architecture, because it changes what gets built;
- a challenge to the **shape** of a design ("a reranker cannot abstain"
  changes the layer table).

Less useful, and rejected on arrival:

- thresholds and latencies that were not measured (`P ≥ 0.75`,
  `noul < 0.15`, "37 minutes") — the calibration loop
  (`bin/oracfit-ring.sh`, `owner_score_pred`) is where numbers come from;
- claims that a field or mechanism exists without naming it;
- architecture that assumes a continuous observer, a second GPU, or a
  model on the critical path of a decision that bash can make.

## Where to read, in order

1. `README.md` — the surface.
2. `SKILL.md` — the rules and the dispatch protocol.
3. `fluxos/dispatch/SKILL.md` — how a dispatch actually runs.
4. `docs/decision-supervisor.md` — the design currently in flight.
5. `incidents/` — the corpus; the most instructive files are the ones
   about a field that was accepted and never read.
6. `fluxos/_comum/mapa-regras.md` — which rule became code and which
   still needs judgment.
