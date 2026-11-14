# Decision supervisor — the software factory design

> Status: **design note**. Nothing here is implemented. Every number was
> measured in this tree on 2026-11-12 (tree `main` = `26c9204`, `VERSION`
> 0.0.1); the appendix has the command that reproduces each one.
>
> One decision is deliberately **open**: the local serving topology for
> Eikos-27B and the Qwen-27B dev assistant (section 9, D1). It is written
> down with its constraints, not answered.

## 1. The question

The dispatcher already does one thing well: it sends work to a model and
accepts the result only when a mechanical oracle — a real command, run on
disk — exits 0. The oracle decides, not the model.

What it does not do is **watch the run while it happens**. When a run
misbehaves, the evidence that would explain *why* is scattered across
`events.jsonl`, the ledger, `incidents/uso/` and the rules map, and nobody
reads them together. The proposal is a layer that does exactly that: a
**decision-model supervisor** that sees each action and each reasoning step,
and suggests the *order of tool calls* based on the incident history the
tree already carries.

The design below is architecture-first. Models are mentioned only where the
architecture constrains them.

## 2. What is already in the tree

Three hard pieces exist today. They are the reason this is a build, not a
rewrite.

| Piece | Where | What it already does |
|---|---|---|
| Trajectory capture | `events.jsonl` (`thinking`, `tool_call`), written by `bin/oracfit-thinking-tee.py` and by each adapter's stream translator | records the model's reasoning and which tool it called |
| Deterministic behavior scan | `bin/oracfit-behavior-scan.py` (tiers B1–B8: restore loop, identical failing call ≥3, write without validate, empty biggest-gap streak, stuck pair, log >5 MB, pass with no write, transport-failure streak) | the Tier-0 cousin of the supervisor: a static scanner over the same trajectory |
| Incident + rule corpus | `incidents/` (126 postmortems) + `fluxos/_comum/mapa-regras.md` (55 rules, 27 of them class `R` — "needs judgment, no mechanism possible today") | the evidence a supervisor would learn from |

**The deterministic scan is currently running on one leg.** B1 (restore
loop), B2 (identical failing call) and B3 (write without validate) all
read the `input` field of a `tool_call` event — `_tool_input_hash()`
(`bin/oracfit-behavior-scan.py:67`) hashes `tool` + the JSON of `input`,
and `_extract_write_paths()` (line 78) takes the path from `input` keys
(`filePath`, `path`, `file`, `target`, …). The cursor adapter emits
`tool_call` events with **no `input`** — 273 of them in this tree's
`events.jsonl`, none carrying it. So on cursor runs the hash of a call
collapses to the tool name alone: two failing `bash` calls with different
commands hash identically, and B2 reads every repeated failing tool of
the same name as "the same call". That is rung B (§10), and it is why
the tool arguments are a precondition for the deterministic layer rather
than a nicety for the supervisor.

The class-`R` rules are the natural question set for a supervisor: each one
is a situation the tree decided to handle by judgment rather than by code.
Their numbers are 1, 10, 12, 13, 14, 16, 23, 25, 26, 32, 36, 38, 40, and
42–55.

## 3. The target: three layers

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 3 — executors                                        │
│   local GPU dev assistant (Qwen 27B class) — free roaming   │
│   Opus 5.5 via the patched v4 runtime — debt-free modules   │
├─────────────────────────────────────────────────────────────┤
│ Layer 2 — decision-model supervisor                        │
│   typed questions (noul / choice / score)                   │
│   abstention + escalation, calibrated against owner scores  │
├─────────────────────────────────────────────────────────────┤
│ Layer 1 — hand-written hexagonal core                      │
│   bash = adapters/edge;  kernel/dispatch-policy (Rust) = core│
│   laws in kernel/laws/P1.md, sampled by proptest              │
│   the oracle lives here — it decides, not the model        │
└─────────────────────────────────────────────────────────────┘
```

The dispatcher stays the *mechanical* layer. The supervisor never overrides
the oracle; it proposes an order of tool calls and can escalate. The
mechanical oracle remains the only thing that can mark a stage green.

## 4. The rule of technical debt

**Hand-written:** the core, the dispatcher runtime, the policy kernel, the
decision layer's contract, and every module where a defect would be
silent.

**Dispatchable** (to Opus 5.5 through the patched v4 runtime): peripherals
that cannot carry technical debt — adapters' glue, one-off scripts, docs,
UI text. A dispatched module is reviewed by the oracle, not by a model.

**Never dispatched:** anything that decides whether a run passed.

The local GPU model is the dev assistant: it is dispatched through
llms.surf like any other runner, it roams the workdir, and its trajectory
becomes supervisor training data. That is the flywheel: local model →
trajectory → incident → rule → supervisor suggestion → fewer wasted
attempts.

## 5. The supervisor contract

### 5.0 Where it acts: capture continuously, decide at choke points

The supervisor is **not** an observer that reads every action and every
reasoning step in real time. That framing is a trap: a continuous reader
of the trajectory poisons its own context, trades determinism for
probability, and drowns in telemetry noise. The right shape is: **capture
continuously, decide only where the run actually forks.**

There are three such choke points, and all three are already code in this
tree — that is why this design is a reorganization, not a new machine:

| Checkpoint | The code that owns it today | What it decides |
|---|---|---|
| **Pre-flight** | `oracfit_gauntlet_compose_spec()` (`bin/lib-oracfit-gauntlet.sh`) composes the spec the runner will read | which prescriptions get injected into that spec |
| **Attempt boundary** | the gauntlet feedback block written by `oracfit_gauntlet_append_feedback()`, consumed at `bin/dispatch-mode.sh:681` | CONTINUE / INJECT_HINT / RESET / ESCALATE for the next attempt |
| **Post-loop** | after the run ends, when the ledger row and the incident file are written | what gets compiled into a gotcha triad |

Between those points the supervisor **reads** — the events stream, the
behavior scan — and does not speak. A run that is on track is untouched.
The cost of a decision is paid three times per run, not once per action.

The supervisor does not answer free-form questions. It answers **typed
questions**, in the System-One family:

- `noul` — is there an answer at all (abstain)
- `choice` — which of the enumerated options
- `score` — a graded judgement, plus a probability

Rules the contract must hold:

1. **Abstention is a first-class answer.** Below a calibrated threshold the
   supervisor says "no opinion" and the run proceeds by the mechanical
   path. It never guesses to look useful.
2. **Calibration is measured, not claimed.** The mechanism already exists
   in `bin/oracfit-ring.sh`: the ring records `owner_score_pred` (line 523)
   and prints `{"real":…, "pred":…, "delta":…}` with a
   `CALIBRAÇÃO <ring> previsto=… real=… delta=…` log line. The supervisor
   reuses that loop; it does not invent a second one.
3. **The question set is typed and versioned.** Each question names the
   rule it comes from (the 27 class-`R` rules), the evidence it reads, and
   the cost of asking it. A question with no incident history behind it is
   not asked.
4. **A suggestion is an order, not a verdict.** The supervisor proposes
   the sequence of tool calls for the next attempt; the oracle still
   decides.

### 5.1 The question API is already standardized

The supervisor does not need a bespoke protocol. The System-One shape
`POST /v1/systemone` already exists in two independent servers, with the
same request and the same response:

```jsonc
// request
{ "state": "<the state of the run>",
  "questions": {
    "route":   { "type": "choice", "instructions": "...", "criteria": {"a": "...", "b": "..."} },
    "urgency": { "type": "score",  "instructions": "...", "criteria": ["can wait", "today"] },
    "angry":   { "type": "noul",   "instructions": "..." }
  } }

// response
{ "answers": {
    "route":   { "type": "choice", "probabilities": {"a": 0.71, "b": 0.29}, "choice": "a", "confidence": 0.71 },
    "urgency": { "type": "score",  "probabilities": {"0": 0.1, "1": 0.9}, "score": 1.0, "legend": {...} },
    "angry":   { "type": "noul",   "noul": 0.83 }
  },
  "usage": { "input_tokens": 412, "output_tokens": 0 } }
```

- **llama.cpp** merged the endpoint for five decision models — laya,
  julia-1, lev, openjev (+vision), kev — in PR `ggml-org/llama.cpp#29818`
  (merged 2026-10-02). The server decides from the model's metadata
  (`{arch}.decision.type`), so a decision GGUF is served with a plain
  `llama-server`.
- **Eikos** ships `serve.py`, a TypeSafe-compatible server with the same
  `/v1/systemone` (plus `/v1/evaluate` and sessions).

**The abstention mass is a separate question, not a field of the choice.**
Read the response shape above: a `choice` answer carries `probabilities`,
`choice` and `confidence`; `noul` is the answer of a question *typed*
`noul`. So "which gotcha" and "is this a known failure at all" are **two
questions**, and the supervisor asks both:

- `known_failure` — type `noul`: *"is the state in front of me a known
  failure?"* → the answer is the abstention mass.
- `which_gotcha` — type `choice`, criteria = the top-k candidates from
  the retrieval layer (§5.3) → the answer is a distribution over them.

There is no single call that returns "P(gotcha_i) and also how sure you
are that any gotcha applies". Designing against that assumption is the
easy way to end up with a supervisor that either never speaks or always
speaks.

One adapter, two backends: the same client code can talk to a CPU
llama.cpp today and to Eikos on a GPU later. That is why the supervisor
question set is written against the **API**, not against a model — the
brain is swappable (see §9, D1).

### 5.2 The unit of memory: a gotcha triad

An incident in `incidents/` is prose. Prose does not fire. The unit a
supervisor can act on is a triad:

- **trigger** — the observable condition that says "this is the same scar"
- **symptom** — what it looked like when it happened
- **prescription** — what to do instead

Mapping onto this tree:

| Triad part | Where it lives today |
|---|---|
| symptom | the `## Sintoma` section of an incident file in `incidents/` (101 of the 126 files, plus two heading variants) |
| prescription | the `## Correção aplicada` section — the mechanism that was added (69 of the 126 files; `## Prevenção` and `## Proteção` are the other spellings) |
| trigger | **does not exist** — this is the gap |

The trigger is the missing piece: a predicate over the events stream, a
stderr pattern, a tool-call shape, a file path. Without it the scar is a
story; with it, the scar is a rule that fires.

Two properties are not negotiable:

1. **A trigger must be falsifiable.** It has to be shown to fire on the
   recorded trajectory and *not* fire on a healthy one. That is what a
   canary is: a fixture that still trips the trigger after the mechanism
   that replaced it landed.
2. **A trigger must be able to rot.** Code changes; a trigger written
   against a log format that later changed stops matching, and stops
   silently. The canary is what makes the rot visible, the same way
   `bin/check-docs.sh` makes tree-derived counts visible.

The tree already has the *policy* half of this — rule 16 (a recurring
failure becomes a mechanism) and the 126 incident files. It does not have
the *trigger* half: there is no `gotchas/` directory, no schema, and
`grep -rli gotcha` over the tree returns nothing. `lessons/` is declared
private in `bin/check-publico.sh` but does not exist on disk.

**Triggers come in two classes, and the class decides the path.** This is
the difference between a mechanism and a model in the loop:

| Class | The trigger is | Where it is evaluated | Cost |
|---|---|---|---|
| **deterministic** | an exact predicate over signals the tree already has — the oracle's exit code, a regex over the oracle's stderr, a specific flag from `bin/oracfit-behavior-scan.py` (B1–B8), a path | **L0**, at the attempt boundary | zero: no model is called, and L1 and L2 are never reached |
| **diffuse** | a semantic resemblance — the state looks like a known scar | L1 filters the bank into top-k, L2 arbitrates | a reranker call plus a decision call |

A deterministic trigger that closes **at L0** is the whole point of rule 16
applied to the supervisor: the failure class was already mechanized, and
routing it through a cross-encoder and a decision model would be an
unjustified tax on a decision bash can make.

**And L2 is a triage chamber, not a destination.** A gotcha that keeps
firing in L2 under the same signature — the same B-flag set, the same
stderr shape, the same oracle exit — is a failure class that rule 16
wants to promote into L0: it becomes a deterministic trigger, or a rule.
The evidence for the promotion is the calibration loop
(`bin/oracfit-ring.sh`): if the ring shows the same signature recurring,
the promotion is justified by measurement. Without that evidence, a
promotion is a guess, and the gotcha stays diffuse.

So the bank has two directions of travel: incidents become triads (post-
loop, rung J), and triads that prove themselves get *demoted* into
mechanisms (the L2 → L0 promotion). Both directions are rule 16.

### 5.3 The four layers, and the name trap

One "decision model" does not cover this job, and the vocabulary tends to
hide that. The layers, by responsibility:

| Layer | Component | Its exact job in the loop | Output |
|---|---|---|---|
| **L0 — telemetry & guardrails** | shell, git plumbing, hashes | extract the state vector of the round: the stderr hash, the error-count delta, the files touched, the repeated diff | deterministic features, no model |
| **L1 — candidate retrieval** | regex + cross-encoder reranker | **filter the gotcha bank only** — reduce the bank to the top-k semantically close candidates | a candidate list with raw scores |
| **L2 — calibrated arbitration** | decision model (`/v1/systemone`) | given the state and the top-k candidates, distribute probability over the typed actions and over `noul` | calibrated `P(options)` + abstention |
| **L3 — safe execution** | llms.surf primitives | apply the chosen action respecting rule 48 (immutable snapshot via plumbing) or exit `7` (`owner_question`) | a safe state change, or an exit code |

Two traps live in this table.

**The reranker is not a decision model.** `bge-reranker-v2-m3` and its
siblings answer "how relevant is this passage to this query" with a
single uncalibrated score; they do not produce `probabilities` over
`noul`/`choice`/`score`, and they cannot abstain. The decision model
can. Collapsing the two into one bucket is what makes this class of
design sound simpler than it is.

**And a reranker must never trigger an intervention by itself.** It lives
in the closed-world problem: five gotchas with nothing to do with the
current bug, one of them sharing vocabulary (`vitest`, `tsconfig`,
`mock`), and the reranker still returns a high score — it has nowhere to
put epistemic uncertainty. A similarity threshold is therefore not a
policy; it is a coin flip with a decimal point. L1 only produces
*candidates*; **only L2 may decide**, and L2 may abstain.

What L0 already is in this tree: `bin/oracfit-behavior-scan.py` (tiers
B1–B8) computes exactly that state vector — restore loops, identical
failing calls, writes without validation, an empty biggest-gap streak,
stuck pairs, log size, a pass with no write, transport-failure streaks.
It is **advisory**: it never changes an exit code. It is L0 waiting to be
read.

The order it runs in:

1. **Deterministic first** — a *deterministic* trigger (§5.2) matches →
   the answer is known, no model runs, and L1 and L2 are never called. The
   cheap, certain path — and the one rule 16 exists to reach.
2. **Semantic match** — no deterministic trigger matched → a cross-encoder
   reduces the bank to top-k candidates. A high score means "a known
   scar is close"; a low score means "no opinion". L1 never decides.
3. **Calibrated policy** — candidates exist → the decision model picks
   among CONTINUE / INJECT_HINT / RESET / ESCALATE, and abstains (`noul`)
   when its confidence is below the calibrated threshold. A gotcha that
   survives here repeatedly is a candidate for promotion back to L0.

The four policy options, and what they mean here:

- **CONTINUE** — the run is fine; do nothing. This is also what a high
  abstention mass means: the state is unfamiliar, the supervisor keeps
  its mouth shut and lets the agent try one more cycle.
- **INJECT_HINT** — put the prescription where the agent will read it:
  into the spec the next attempt receives. The mechanism already exists
  (`oracfit_gauntlet_append_feedback()` writes a feedback block into the
  composed spec); the change is that the hint becomes a *named gotcha's
  prescription* instead of a generic "biggest remaining gap".
- **RESET** — and the word needs care: never a destructive
  `git reset --hard` over the agent's work. This repo's own history is
  the argument — rule 48 exists because editing a script in place while a
  live run executed it killed that run with exit 127. §5.5 has the
  non-destructive version.
- **ESCALATE** — and the channel already exists: the `owner_question`
  path (exit 7, `owner-question.md`) is how a run hands a decision back
  to a human. A supervisor escalation is that path, plus the trace the
  owner needs to answer it.

That last mapping is not a proposal; it is the tree's behaviour seen from
the other side. And the escalation question is **already structured**:
the contract in `bin/dispatch-stages.sh` (line 445) demands one
`pergunta:` line plus **at least two** `se <resposta> -> <o que você
faz>` consequence lines, and the answer is injected back into the spec
when the run resumes. "A structured question with a fork of consequences"
is not something to design; it is already the format.

**On thresholds.** A policy like "inject only if `P(gotcha_i) ≥ 0.75` and
`noul < 0.15`" is the right *shape* and a wrong *number*: those constants
come from nowhere but a plausible-looking number, which is exactly what
this repo's `bin/check-spec.sh` exists to catch in specs. The thresholds
have to come from the calibration loop that already exists —
`bin/oracfit-ring.sh` records `owner_score_pred` against the real owner
score and prints `CALIBRAÇÃO <ring> previsto=… real=… delta=…`. Until
that loop has run on the workload, the numbers are placeholders and the
policy stays advisory.

The CPU latency measurement (§9, "The supervisor does not need a GPU")
reinforces the choke-point shape rather than fighting it: a CPU decision
model can answer against a compact state summary in seconds, but not
against a whole trajectory. At the attempt boundary the state *is* a
compact summary.

### 5.4 The pre-flight injection

The cheapest injection point is before the agent has done anything: the
spec it receives. The gauntlet already injects there — the composed spec
carries `## GROUND TRUTH (Oracfit inject — authoritative for this run)`
and the accumulated feedback block. Adding the gotcha bank to that same
channel costs nothing structurally: score the task against the bank, and
a match appends the triad's prescription to the spec.

The ordering matters: the prescription arrives **before** the first tool
call, so the agent never has to be interrupted, and the run never enters
the state where a hint is needed but ignored. The intervention that
saves the most attempts is the one that arrives earliest.

### 5.5 RESET that keeps the evidence

The instinct is right: a reset that throws the agent's mess away also
throws away the thing that would become the next gotcha. What the tree
needs is a snapshot that is immutable, does not move HEAD, does not touch
the working tree, and captures what the agent **actually did**.

**The recipe that does not work.** `git write-tree` writes the **index**,
not the working tree. Measured in a scratch repo: after editing a tracked
file and creating an untracked one, `git write-tree` produced a tree
holding only the *committed* content of the tracked file — the dirty edit
and the new file were both missing. A snapshot built that way captures
the state *before* the derailment, which is the opposite of its purpose.
`git stash create` is no better here: it captures the tracked
modifications but **not untracked files**, and the agent's new files are
exactly the derailment. `git stash push` would capture them but mutates
the working tree — the thing rule 48 forbids.

**The recipe that works** — a scratch index outside the working tree:

```bash
idx="$(mktemp /tmp/oracfit-wip.XXXXXX.idx)"; rm -f "$idx"
GIT_INDEX_FILE="$idx" git read-tree HEAD      # empty tree if the repo has no commit
GIT_INDEX_FILE="$idx" git add -A              # tracked edits AND untracked files
tree="$(GIT_INDEX_FILE="$idx" git write-tree)"
rm -f "$idx"
commit="$(git -c user.email=llms.surf@localhost -c user.name=llms.surf \
            commit-tree "$tree" -p HEAD \
            -m "llms.surf: wip run=$RUN_ID iter=$ITER")"
git update-ref "refs/llms-surf/wip/$RUN_ID/iter-$ITER" "$commit"
```

Verified in a scratch repo: the resulting tree holds the dirty content of
the tracked file **and** the untracked file; the real index and the
working tree are untouched; the ref lives outside `refs/heads/`, so HEAD
does not move. Two details are not optional:

- the scratch index must live **outside** the worktree — if it lives
  inside, `git add -A` picks the index file itself up as a new file
  (measured);
- `git commit-tree` needs an identity — without one it fails with
  `Author identity unknown` (measured), so the identity is passed
  explicitly rather than assumed from the user's config.

**Where the scratch index may live is not a style question — it is
measured behaviour, and it cuts both ways.** Placing it inside the
workdir (say, `<workdir>/.dispatch/snapshot.index.$$`) works *only* when
the target repository ignores that path. Measured, in a scratch repo:

- with the directory **ignored** by `.gitignore` and a fresh copy of the
  index → the scratch index is **not** in the tree (the tree held only
  the committed files);
- with the directory **not** ignored → the tree holds the scratch index
  **and** its `.lock` file, because both are real files in the worktree
  while `git add -A` runs;
- and once a path is staged, `.gitignore` does not unstage it — a
  scratch index that got in stays in.

`.dispatch/` is ignored **in this repo** (`.gitignore`), so the
convenient placement happens to be safe here. It is not safe in a
dispatched target project, whose `.gitignore` is not ours to assume.
The scratch index goes outside the workdir, unconditionally.

One more precision about the "nothing changed" guarantee: the real index
and the working tree are byte-identical before and after — but the
object database gains unreferenced objects (the new blobs and the tree),
and the ref namespace gains one ref. That is additive and harmless; it
is not "nothing was written".

**The restore is scoped, and rule 47 decides the scope.** The tree already
has the list: `core/protected-paths-default.txt` (globs relative to the
workdir root — `AGENTS.md`, `VERSION`, `model-registry.json`, `core/*`,
`fluxos/*`, `bin/*`, `adapters/*`, `incidents/*`, `.oracfit-protected`),
consumed by `bin/dispatch-mode.sh` (line 449) when the workdir *is* this
checkout, emitting a `protected_paths_alert` event — an alert, never a
block. A scoped restore must skip exactly those globs: restoring `bin/*`
inside this checkout is literally the death of run `951f5899` (rule 48),
and the alert mechanism already knows which paths are dangerous.

**When the restore happens matters more than what it restores.** The
dangerous moment is mutating the tree while a runner is executing a
script from it. A reset decided at the attempt boundary — no runner alive
— is safe; the same reset in the middle of an attempt is the incident.
And the restore must never touch the orchestrator's own control files:
they live in `ORACFIT_ROOT`, outside the dispatched workdir (rule 47).

**The scar reaches the agent through the spec, not through stderr.** The
agent reads the spec it was handed; stderr is the oracle's and the
human's channel. The line that says *"your attempt N degraded the tree
without reducing the errors, it was saved in
`refs/llms-surf/wip/<run>/iter-N`, the out-of-scope files were restored,
do not repeat approach X"* belongs in the composed spec of the next
attempt — the channel the gauntlet feedback already uses
(`oracfit_gauntlet_append_feedback()`). Injecting it in stderr would put
the scar where nobody reads it.

### 5.6 The diff is evidence, not a trigger

The WIP snapshot and the final good HEAD give the **exact difference
between the hole the agent fell into and the state that passed** — the
best evidence a gotcha will ever have. But it is evidence, not a
trigger: the diff describes *what the agent did*, while the trigger is a
predicate over the state *before* it did it. Those are different objects,
and the trigger is the hard one.

So sup-03's rule stands: the compiler copies the symptom and the
prescription from the incident and **leaves the trigger empty**; a human
(or a later rung) writes the predicate and the canary. What the
WIP↔HEAD diff buys is a far better symptom and prescription — the
symptom can quote the actual diff instead of a remembered description.

And the extraction has a trigger of its own, which is a fact rather than
an inference: a run that left a `refs/llms-surf/wip/<run>/iter-*` ref
**is** a derailed run — the WIP ref exists precisely because the
supervisor decided to reset. So "a WIP ref exists, or the run ended with
high abstention over several iterations" is readable from the refs and
the events, not guessed.

## 6. Three honest facts about the data

These are the constraints that decide what is buildable. All three were
measured in this tree while writing this note.

**Fact 1 — the trajectories carry no tool arguments.** In this tree's
`events.jsonl` there are **273 `tool_call` events and 0 of them carry
`input`**. The opencode side does carry it (`bin/oracfit-thinking-tee.py`
emits `input` as a native object, plus a 300-char `preview`); the cursor
adapter (`adapters/cursor/stream-events.py`) emits only `tool` and
`preview`. A supervisor that cannot see *what* was called cannot learn what
to call next. Fixing this is spec `specs/sup-02-argumentos-das-tool-calls.md`.

**Fact 2 — the labelled corpus is not in this repo.** The calibration loop
lives in the ring, and the ring is created **in the target project**
(`bin/oracfit-ring.sh`, `RING_DIR="$TARGET/$RING_DIR_NAME"`), not here.
So the supervisor's labels are collected where the work happens. What
exists here is the raw material: 1048 auto-telemetry files in
`incidents/uso/` (937 `success`, 63 `failed`, 48 `already-passing`, counted
on 2026-11-13 — the directory grows with every dispatch) and 126
postmortems.

**Fact 3 — the telemetry base had rows that were not machine-readable.**
`bin/dispatch-escalate.sh` built the `extra` payload with
`local extra="${3:-{}}"`: the `${...}` expansion ends at the first `}`, so
the payload the caller wrote arrived with **one extra closing brace** and
the whole usage row failed to parse. Measured on 2026-11-13: **46 of 1010**
rows in `.dispatch/usage/usage.jsonl` were broken — every one of them from
`source` `escalate`, every one of them with the same shape — while the
other 964 parsed. Rung **E** fixed the origin and hardened the writer
(`specs/sup-06-usage-jsonl-legivel.md`): `extra` is always an object,
`mode` and `exit_code` are never raw caller text, a row that does not
parse is rejected instead of appended, and
`bin/oracfit-usage-json.py repair` recovers the rows already written
without dropping any of them. The local base was repaired on the same day
(`repair --in-place`, 46 recovered, 0 quarantined): it now parses **100%**
— 1048 rows, 0 broken — with the original kept in `usage.jsonl.bak`.

**Fact 3b — the `log_tail` of the telemetry was always empty on Linux.**
`bin/emit-usage-feedback.sh` read the mtime of the newest task log with
`stat -f %m "$f"`, chained to `stat -c %Y "$f"` by `||`. On GNU coreutils
`stat -f` means *filesystem status*: it prints a multi-line blob to stdout
and **exits 1** (measured on this machine, 2026-11-13 — the earlier
version of this note said it exits 0, which is wrong). The fallback
therefore *does* run, but the blob of the first form is already inside the
captured value: the value is the blob **plus** the integer, the comparison
`-ge` fails with `integer expected`, the newest log is never picked and
`log_tail` is written empty. Measured, not inferred: a usage row written
with a 4 KB task log present carried `"log_tail":""`. The log *index*
(path and size) was unaffected.

Fixed by rung **12** (`specs/sup-12-telemetria-log-tail.md`): the `stat`
form is detected **once**, before the loop, with its own output discarded;
the capture holds only the integer; a log whose mtime cannot be read stays
in the index with its size and is never chosen as the newest. Filling the
tail exposed a second latent defect — GNU `tr` replaces a newline with a
single byte, so the `↵` marker was written as a lone `0xe2` and the row
stopped parsing; the marker is now expanded in the shell, keeping the row
valid UTF-8 JSON.

There is a fourth, smaller fact: the multi-stage runtime and the
single-stage runtime are not symmetric. `bin/dispatch-stages.sh` has an
emergency epilogue (`oracfit_stages_emergency_epilogue`, lines 164–193,
with `EXIT`/`TERM`/`INT` traps at 194–196); `bin/dispatch-mode.sh` has
only `trap 'oracfit_run_lock_release' EXIT` (line 125) and no
`behavior_scan` call. **A mid-flight death in the single-stage runtime
loses the `run_finished` event, the ledger row and the usage row** — that
is precisely the evidence the supervisor would need. Fixing this is spec
`specs/sup-01-evidencia-quando-o-run-morre.md`.

## 7. The assembly line

```
                     ┌── pre-flight ──────────────────────────────┐
                     │  spec = base + GROUND TRUTH + gotcha        │
                     │  prescriptions (injected before attempt 1)  │
                     └───────────────────┬────────────────────────┘
                                         ▼
incident (126) ─┐                      executor
rules (27 class R) ─┼─► gotcha bank ◄─── local GPU dev assistant
telemetry (632) ─┘   (triggers +         |  Opus 5.5 (v4 runtime)
                     prescriptions)            │
                                              ▼
                     ┌── attempt boundary ────────────────────────┐
                     │  oracle verdict → CONTINUE | INJECT_HINT  │
                     │               → RESET      | ESCALATE     │
                     └───────────────────┬────────────────────────┘
                                         ▼
                     ┌── post-loop ───────────────────────────────┐
                     │  ledger row + incident → gotcha triad      │
                     │  (trigger, symptom, prescription) + canary │
                     └────────────────────────────────────────────┘

the same round, by layer (§5.3):

  L0  state vector ─────────────► L1  top-k candidates ──► L2  calibrated
  (stderr hash, error delta,       (reranker filters the      P(action) +
   touched files, repeated diff)    bank; never decides)       abstention
        │                                                      │
        │                                                      ▼
        │                                        L3  safe execution
        │                                        ├─ snapshot  → refs/llms-surf/wip/…
        │                                        ├─ restore   → scoped, rule 47
        │                                        └─ escalate  → exit 7 + owner_question
        ▼
  the WIP ref and the final HEAD are the evidence
  the next gotcha is compiled from (evidence, not trigger — §5.6)
```

Capture is continuous (the events stream, the behavior scan); the three
decisions above are the only moments the supervisor speaks. Between them
the run is untouched.

Nothing in this loop may replace the oracle. The supervisor's value is
measured by wasted attempts avoided, not by pass rates it fabricates.

## 8. Prior art, and the gap

Searched publicly (2026-11-12) across arXiv and vendor engineering blogs.
The halves exist:

| Half | Where |
|---|---|
| Calibrated decision model exposed as a service | **Clef** (Cloudflare, Apache-2.0, `/v1/systemone`, Brier loss + RLCD, 209 ms median / 38.8 ms flash), **Jev** (TypeSafe, `/v1/systemone`, types Noul/Choice/Score/Box — it explicitly leaves *ordering* to the application), **Eikos** (MIT, letter-logit readout, ECE 0.021–0.043, EN+PT), **OpenAI Decisions API** (`POST /v1/decisions`, types predicate/choice/score) |
| The same API, served **on CPU** | **llama.cpp** merged `/v1/systemone` for five decision models (PR #29818, merged 2026-10-02): `ggml-org/Julia-1-GGUF` (Q8_0 **0.17 GB**), `ggml-org/Laya-GGUF` (0.45 GB), `ggml-org/Kev-0.8B-GGUF` (0.81 GB), `ggml-org/Kev-4B-GGUF` (Q4_K_M **3.03 GB**), `ggml-org/lev-GGUF` (3.03 GB), `ggml-org/OpenJev-GGUF` (Q4_K_M 19.4 GB). **SemIf** (TheoLeeCJ) and its CPU port **JEV-CPU** (MIT, `Meanblock/JEV-CPU`, Qwen3-0.6B fp32 ≈ 2.4 GB, ~1 s per decision on a laptop CPU, with a web UI) |
| The open Jev-line checkpoints | **Kev** (`jaredpalmer/kev-0.8b` / `kev-4b` / `kev-27b`, Apache-2.0): a LoRA + pointer head on Qwen3.5-4B-Base, calibrated distribution over the options in one forward pass, no text generated; Kev-4B reports accuracy 0.838 / Brier 0.224 on its locked out-of-domain test. The GGUF builds are the ones llama.cpp serves |
| A decision gate before action | **JevAct** (IBM SIL, arXiv:2610.38620) — uses a decision model (Kev) as a gate before acting; it warns that its probabilities are not guaranteed calibrated |
| Choosing the model/executor per step | **RouteLLM** (2406.18665), **Router-R1** (2506.09033), **AgentRouter** (2609.22951), **SWE-Router** (2607.00053), **RSI-Router** (2609.34712), **Planner-as-Router** (2609.32917), benchmarked by **TwinRouterBench** (2605.18859) |
| Learning guards from incidents | **AIR** (2602.11749, ICML 2026) synthesizes guardrails from incidents; **Trajectory Graph Copilot** (2607.27443) builds a GNN over trajectories; **Near-Miss** (2603.29665), **Metis** (2608.25322), **FiF**, **Reflexion**, **SEAL**, **Agent Lightning**, **ToolRL**, **ADAS** |
| Monitoring an agent while it runs | **GuardAgent** (2406.09187, ICML 2025), **PolicyGuide** (2608.19861), **ToolGuard** (IBM), commercial allow/deny gateways |
| Matching a live state to a known past failure | **rerankers / cross-encoders** — `BAAI/bge-reranker-v2-m3`, `BAAI/bge-reranker-base` (both with ONNX tags), `jinaai/jina-reranker-v2-base-multilingual`, `cross-encoder/ms-marco-MiniLM-L6-v2` (60.6M downloads). A relevance score over passages, not a calibrated policy over options — see §5.3 |

Note the "monitoring while it runs" row: this design **deliberately does not
intervene continuously**. It monitors continuously and intervenes at three
choke points (§5.0). The published monitoring work is the prior art for
the *capture*, not for the *intervention*.

**The gap:** no published work combines all five of — (a) a *calibrated*
decision-model supervisor, (b) the supervisor deciding the **order of tool
calls** (not just the model, not just allow/deny), (c) **online learning
from incident history**, (d) **calibrated abstention/escalation**, and (e)
a **machine-actionable memory of past failures** — a gotcha triad whose
trigger fires on a live state and whose prescription is injected where the
agent reads it. The closest pieces each own one or two of the five. AIR
(2602.11749) is the nearest on (c) and (e), but it synthesizes guardrails
for a policy engine, not a triad with a falsifiable trigger and a canary
that proves the trigger still fires.

Two caveats that belong in the same breath as the gap:

- **Scale AI's Monitor Red Teaming** (arXiv:2508.19461) reports that
  *scaffolding* matters more than the monitor model, and that a weak
  monitor in front of a strong agent is unstable. A weak supervisor is a
  risk, not a feature — the scaffolding has to be measured, not assumed.
- **JevAct** itself warns that the probabilities it consumes are not
  guaranteed calibrated. Calibration is the supervisor's own obligation,
  not the model's.

One paper in this area (arXiv:2511.15755, runbooks from postmortems) was
**withdrawn by its author** and is deliberately not cited here.

## 9. Open decisions

### D1 — local serving topology: Eikos-27B on one card, Qwen-27B on another

**This decision is deferred on purpose.** What is known is written here so
the decision can be made on facts, not on a guess. (The framing below is
the original one; the section that follows shows the supervisor may not
need a card at all.)

Measured on this host (2026-11-12):

| Fact | Value |
|---|---|
| GPUs installed | **1 × RTX 3090** (GA102, 24576 MiB, 250 W limit, PCIe gen 3 ×16) |
| GPU in use right now | ~0.75 GB (desktop only); no model process listening |
| Board | MSI, AMD 400-series chipset; Ryzen 5 3500X (Matisse) |
| PCIe topology | GPU at `00:03.1 → [26]` (CPU root port, x16); NVMe at `00:01.1 → [01]`; the 400-series chipset hangs off `00:01.3 → [03-25]` and `00:00.2 → [20-25]` (USB, SATA, Ethernet). The only other CPU-attached port, `00:07.1 → [27]`, is a **Matisse dummy function**, not a device |
| Host RAM | 32008 MiB total, 22150 used, **9858 available**; zram 31.3 GB with 10.6 GB in use; swapfile 31.2 GB unused |
| Local Qwen today | `Qwen3.8-27B-EXL3-3.5bpw` + DFlash2 drafter (5.0 bpw), configured to serve on `127.0.0.1:8888` (not running at the time of measurement), budget `GPU_MEM_GB=22`, `CONTEXT_SIZE=225280`, `CACHE_QUANT=4` (a 3090 cannot compile the fp8/nvfp4 Triton kernels — they need sm ≥ 8.9) |

Eikos build sizes (from the model's own repository tree):

| Build | Size | Fits one 24 GB card? |
|---|---|---|
| `Eikos-27B-INT4` | 19.42 GB | yes, with a small KV margin |
| `Eikos-27B-FP8` | 31.22 GB | **no** |
| `Eikos-27B` bf16 | ~55.6 GB | no |
| `Eikos-4B-INT4` | 4.0 GB | yes, easily |

Serving constraints on the Eikos side (from the Eikos repository, not from
this tree): its own `serve_vllm.sh` requires **vLLM ≥ 0.30** (0.11 returns
wrong answers when batched), and its flags (`--mamba-cache-mode align --logprobs-mode processed_logprobs
--max-logprobs 600 --max-num-seqs 64 --max-model-len 16384`) are sized for
80–96 GB GPUs. On a 24 GB card `--max-num-seqs` and the KV budget have to
be retuned, and the 27B is only viable in the INT4 build.

### The supervisor does not need a GPU

The original framing of this decision was "Eikos-27B on one card, the Qwen
27B on another". But the decision-model family has a **CPU** half, and it
speaks the same API (§5.1), so the second card may not be needed at all:

| Model (llama.cpp GGUF) | Size | Notes |
|---|---|---|
| `ggml-org/Julia-1-GGUF` (Q8_0) | 0.17 GB | the smallest decision model llama.cpp serves |
| `ggml-org/Laya-GGUF` (Q8_0) | 0.45 GB | |
| `ggml-org/Kev-0.8B-GGUF` (Q8_0) | 0.81 GB | |
| `ggml-org/Kev-4B-GGUF` (Q4_K_M) | **3.03 GB** | Kev-4B: LoRA + pointer head on Qwen3.5-4B-Base |
| `ggml-org/lev-GGUF` (Q4_K_M) | 3.03 GB | |
| `ggml-org/OpenJev-GGUF` (Q4_K_M) | 19.4 GB | the 27B-class one |

A CPU decision model is `llama-server -hf ggml-org/Kev-4B-GGUF` exposing
`POST /v1/systemone`. It needs no CUDA, no vLLM, and about 3–4 GB of RAM
(with context) — a slice of the ~9.8 GB this box has available.

**The cost is latency, and it is measured.** JEV-CPU (the SemIf CPU port)
published its own prefill scaling on an 8 GB CPU box, Qwen3-0.6B fp32:
254 tokens → 2.5 s, 731 → 5.6 s, 1 363 → 11.9 s, 2 629 → 26 s, 5 165 →
66 s, 7 697 → 117 s. RAM stayed flat at ~3.5 GB; the ceiling was prefill
latency, growing roughly with the square of the input. Our Ryzen 5 3500X
(6 cores, Zen 2 — no AVX-512 BF16, no AMX) is in the same class as that
box, so the same order of magnitude is the right expectation.

That is a **design constraint, not just a number**: a CPU supervisor can
answer "which of these three tool calls should be tried next?" against a
compact state summary in seconds; it cannot re-read a whole trajectory on
every attempt. So the split that pays is:

- **CPU** — the frequent, short-state questions (order of tool calls,
  "is this retryable?", "does this evidence support escalation?").
- **GPU** — the dev assistant (Qwen 27B, already served on the 3090) and,
  later, the heavy whole-trajectory questions — where Eikos-27B earns its
  second card.

**Caveats that stay on the table:** (i) llama.cpp is **not installed on
this box** — the local Qwen kit uses exllamav3, which is CUDA-only, so
this path needs a CPU build of llama.cpp (the endpoint itself is upstream
and merged); (ii) Kev's probabilities are *not* guaranteed calibrated
(JevAct's own warning) and the ECE table of Eikos does not transfer to it
— calibrating on our workload is our job, and the ring loop
(`owner_score_pred`) is where it happens; (iii) a 3 GB model plus context
on a box with ~9.8 GB free is affordable but not free.

Candidate topologies, with what blocks each one:

| # | Topology | Blocked by |
|---|---|---|
| **C** | **Qwen 27B on the 3090 (as today) + supervisor on CPU** (llama.cpp + `Kev-4B-GGUF` or `Julia-1-GGUF`) | only the llama.cpp CPU build; latency in seconds, so the question set has to stay short-state |
| A | Second 3090 on the same board: Eikos-27B-INT4 on card 2, Qwen 27B on card 1 | (i) **an empty slot does not appear in the PCIe tree**, so the measurement cannot say whether a second slot exists or how wide it is — on a board of this class the slots below the chipset are x1, and a 3090 wired at PCIe 3.0 x1 loads its ~19.4 GB of weights very slowly and has almost no host↔device bandwidth to spare; (ii) the PSU (two 250 W-limit cards ≈ 500 W of GPU alone) is unmeasured; (iii) host RAM: loading 19.4 GB of safetensors while ~22 GB of RAM is already used pushes the page cache into zram and slows the whole workstation — this machine is the only PC and must not be brought down |
| E | Same as A, but the second card serves Eikos-27B as the *heavy* supervisor while the CPU model handles the frequent questions | same as A, plus the GPU contention with the four production jobs already on `:8888` |
| B | One card, two models: Eikos-4B-INT4 (4.0 GB) + the Qwen 27B with a reduced context | the Qwen kit is budgeted at 22 GB for a 225k context; the 27B decision model would have to go, or the Qwen context has to shrink a lot. The exact split has to be measured, not assumed |
| D | Supervisor on another host | no local hardware risk; needs a network dependency and an always-on peer |

What would settle D1, in order:

1. Build llama.cpp (CPU) and measure the real latency of one
   `/v1/systemone` call on this 3500X with `Kev-4B-GGUF` (Q4_K_M): the
   load time, the per-decision latency at ~250, ~750 and ~1500 tokens of
   state, and the RSS with a realistic context. This single measurement
   decides whether C is viable — and it costs no hardware. **Measure it
   the way the loop will use it** — the protocol is below.
2. Read the board: does it have a second slot, and is it x16 or x1? (The
   PCIe tree cannot answer this — an empty slot is invisible in it. The
   silkscreen and the board manual can.)
3. Measure the PSU: model and wattage.
4. Measure the RAM headroom a second GPU-resident model would need, and
   whether raising RAM to 64 GB is on the table (this machine is the only
   PC).
5. Only then: retune the Eikos serving flags for a 24 GB card and measure
   the decision latency that the supervisor's budget depends on.

#### How to measure it so it reflects the loop

A benchmark of the model on an idle box measures the wrong thing twice
over. Two physical facts decide whether the CPU path is viable, and both
are properties of the *harness*, not of the model.

**1. The call is prefill-dominated, so the prompt's shape decides the
cost.** A `/v1/systemone` call evaluates a prompt and returns a
distribution — it does not generate token by token. So it is dominated by
prompt evaluation, which is compute-bound (AVX2 matrix multiplies on 6
cores / 6 threads; the 3500X has no SMT and no AVX-512). Two
consequences:

- If the **variable** part of the prompt comes first, every attempt
  invalidates the cached prefix and the whole prompt is recomputed at
  each attempt boundary.
- If the **invariant** part comes first — the instructions and the typed
  options of the question set, which are versioned (§5, rule 3) and
  therefore identical across attempts — the server only processes the
  delta: the B1–B8 vector, the oracle's tail, and the L1 candidates.

That is a design constraint on the question set, not a tuning knob: the
invariant prefix must be *literally* the same bytes across attempts, or
the cache never hits. llama-server does the reuse by default —
`--cache-prompt` is "whether to enable prompt caching (default:
enabled)", and the request parameter `cache_prompt` (default `true`)
re-uses the KV cache from a previous request "if possible … only the
suffix that differs between the requests".

Measure **two regimes** at each size (~250 / ~750 / ~1500 tokens):
cold (first call, nothing cached) and warm (same invariant prefix,
different suffix). And measure the hit rather than infer it: the
response's `timings` object reports `cache_n` ("number of prompt tokens
reused from cache"), `prompt_n` ("number of prompt tokens being
processed"), `prompt_ms` and `prompt_per_token_ms`.

**One caveat that is a calibration hazard, not a footnote.** The server's
own documentation warns that with prompt caching enabled "the logits are
**not** guaranteed to be bit-for-bit identical for different batch sizes
(prompt processing vs. token generation)" and that enabling it "can
cause nondeterministic results". For a chat model that is a footnote; for
a **decision model whose output is a calibrated probability** it is a
property of the measurement instrument itself. The calibration loop
(`owner_score_pred`) has to be run against the same server configuration
that will serve the decisions, or the calibration is of a different
system than the one that acts.

**2. The measurement must survive the runner.** With 32 GB of RAM and a
runner compiling code or running suites, the kernel reclaims pages, and
the GGUF's mapped pages get evicted — so the decision call at the
attempt boundary pays page faults reading the weights back from disk.
Measuring on an idle box measures the un-evicted case, which is not the
case that matters. The fix is to pin the model in RAM: llama-server's
current flag is `-lm, --load-mode MODE` with the values `mmap`,
`mlock`, `mmap+mlock`, `none` ("force system to keep model in RAM
rather than swapping or compressing"), and the environment equivalent is
`LLAMA_ARG_LOAD_MODE=mmap+mlock`. There is **no** `--mlock` flag and no
`--no-mmap` flag in the current server — `--load-mode none` replaces the
latter. Run the server with `mmap+mlock` and measure how much of the
32 GB is still free for the workdir and the oracle; if the pinned model
plus its KV cache does not fit alongside the runner, that is the finding,
and it belongs in D1.

My recommendation, for the record: **C first** — it needs no hardware, no
second card, no PSU, and it leaves the 3090 entirely to the dev
assistant. **A/E only if 2–4 come out clean**, as the upgrade path for
the heavy questions. The architecture above does not depend on which wins:
the supervisor is an adapter against `/v1/systemone`, so the brain behind
it can be swapped without touching the question set. Only the latency
budget moves.

### D2 — reorder or alert-only

Does the supervisor **change** the order of tool calls (reorder) or only
**flag** what it sees (alert)? Reordering is worth more and risks more.
Recommendation: ship alert-only first; the first reorder that is not
provably neutral is a bug report against the supervisor.

### D3 — the dev assistant as an official runner or a side process

If the local Qwen is a first-class runner in `model-registry.json`
(it already has entries: `qwen38-27b-exl3-3090`,
`qwen38-27b-q5km-gguf-3090`), its trajectory is captured for free. If it
is a side process, the trajectory has to be piped in by hand. The first is
cheaper and already half-done.

### D4 — the decision budget

How many supervisor questions per attempt, and what is the maximum latency
the run may pay for them? Without a budget the supervisor becomes a
latency tax; with one, "abstain" is a budgeted answer.

## 10. The PR ladder

Each rung is a small, dispatchable spec with an oracle. The order matters:
the mechanism comes before the model, and the evidence comes before
everything.

| Rung | What it delivers | Unblocks |
|---|---|---|
| **A** | `specs/sup-01-evidencia-quando-o-run-morre.md` — the single-stage runtime closes its own evidence on an abnormal exit (epilogue parity with `dispatch-stages.sh`) | the supervisor has a complete trajectory to read |
| **B** | `specs/sup-02-argumentos-das-tool-calls.md` — the cursor adapter's `tool_call` events carry the tool arguments | the supervisor sees *what* was called, not only *which* tool — and a deterministic trigger over a repeated call needs the arguments to be a trigger at all |
| **C** | the gotcha triad: a schema, a compiler from an incident file to a triad (trigger / symptom / prescription), a validator, and a canary that proves each trigger still fires — `specs/sup-03-gotcha-compilado.md` | the bank the supervisor matches against exists, and its triggers are falsifiable |
| **D** | the deterministic matcher: a trigger that fires injects its triad's prescription into the spec the agent reads, through the existing gauntlet feedback channel — `specs/sup-05-matcher-determinista.md` | the first real intervention, with no model in the loop at all |
| **D2** | the safe reset: the WIP snapshot via git plumbing (`refs/llms-surf/wip/<run>/iter-N`), the scoped restore that honors `core/protected-paths-default.txt`, and the scar line in the next attempt's spec — `specs/sup-04-reset-sem-destruir-evidencia.md` | RESET becomes a policy option that does not destroy the evidence |
| **E** | the malformed `usage.jsonl` rows are fixed and the writer is hardened: the stray brace at the origin, an `extra` that is always an object, a row that does not parse is rejected instead of appended, and a repair for the base already written — `specs/sup-06-usage-jsonl-legivel.md` | the telemetry base is machine-readable again |
| **F** | the semantic matcher: a CPU cross-encoder reduces the gotcha bank to top-k candidates — advisory, it never decides and never triggers | a scar that has no deterministic trigger is still found |
| **G** | the question set: the 27 class-`R` rules written as typed questions with their evidence and cost — `specs/sup-07-perguntas-tipadas.md` (delivered: `core/supervisor/questions.json`, 26 asked, 1 withheld) | the supervisor has something to ask |
| **H** | the supervisor adapter: a client of `POST /v1/systemone` (llama.cpp on CPU today, Eikos on a GPU later), with abstention and a calibration log wired to `owner_score_pred` — `specs/sup-09-cliente-systemone.md` (delivered: `bin/oracfit-systemone.py`, which asks and brings the raw answers; the decision stays in rung I) | the decision layer exists at all |
| **I** | the policy decision: CONTINUE / INJECT_HINT / RESET / ESCALATE, with RESET meaning a snapshot or WIP commit and ESCALATE meaning the existing `owner_question` path (exit 7, with its `pergunta:` + fork contract) — `specs/sup-11-politica-do-supervisor.md` (delivered: `bin/oracfit-policy.py`, which reads the typed answers and writes **one order**; the shipped `core/supervisor/policy.json` is **not calibrated**, so it always answers CONTINUE) | the supervisor acts, at the attempt boundary, under a calibrated threshold |
| **J** | the post-loop distiller: a finished run compiles into a new triad — the WIP↔HEAD diff as the *symptom*, the trigger still written by hand — and its canary joins the suite — `specs/sup-10-destilador-pos-loop.md` (delivered: `bin/oracfit-distill.py`, which turns a usage report into a **draft** triad; the trigger and the prescription stay written by hand) | the bank grows from the corpus instead of by hand |
| **K** | the local dev assistant registered as a first-class runner, its trajectory feeding the ring | the flywheel closes |
| **12** | the telemetry defect (Fact 3b): the `log_tail` of the usage row was **always** empty on Linux, because the two `stat` forms were chained inside a value capture and the failing form's output poisoned the value — `specs/sup-12-telemetria-log-tail.md` (delivered: the working form is detected **once**, with its own output discarded; filling the tail then exposed a second latent defect — GNU `tr` wrote the `↵` marker as a single byte, and the row stopped parsing) | the telemetry finally carries what happened in the round |
| **13** | the runtime **executes** the order: at the attempt boundary — after the gauntlet feedback, before the next attempt composes the spec — the single-stage runtime reads the decision record and applies it — `specs/sup-13-runtime-executa-a-ordem.md` (delivered: `bin/lib-oracfit-supervisor.sh`; **INJECT_HINT** is executed and **CONTINUE** is a no-op; **RESET** and **ESCALATE** were refused at that rung and became executable in rungs 14 and 15) | the supervisor stops only writing orders and starts acting |
| **14** | the **RESET** becomes executable: the dirty tree is snapshotted into a commit under `refs/llms-surf/wip/<run>/iter-N` *before* anything moves, the changed tracked files are restored from **HEAD** (never from the snapshot — that would undo the undo), protected globs are skipped, untracked files are never deleted, and the scar plus the hint travel to the next attempt's spec — `specs/sup-14-reset-executavel.md` | a derailed attempt is undone without losing the evidence of what it did |
| **15** | the **ESCALATE** becomes executable: the order's `pergunta` and its `se ... -> ...` fork are validated (an order without the fork is refused), the question lands in the workdir inbox, the run leaves the attempt loop with status `owner_question` and exit **7**, and the final oracle recheck is skipped so a paused run is never flipped to `pass` — `specs/sup-15-escalate-pausa-a-run.md` | a question nobody in the system can answer reaches the owner on the channel that already exists |
| **16** | the runtime **asks**: the three pieces that were never joined — the typed question set (rung G), the System-One client (rung H) and the policy engine (rung I) — become one command, and the single-stage runtime calls it at the attempt boundary when no hand-placed decision file exists — `specs/sup-16-o-runtime-pergunta.md` (delivered: `bin/oracfit-supervisor-ask.sh`, which exports the question set, asks, and hands the answers to the engine; the endpoint has **no default** — it is the owner's, so the whole path stays dormant until D1 and a calibration exist) | the order stops being a file someone writes by hand and becomes the answer to a question the system asked |
| **17** | the **calibration becomes a file**: the ring stores the measured calibration line on its own score event (the English `CALIBRATION` line it prints), and a new command copies that line into a *derived* policy — `specs/sup-17-a-calibracao-e-registrada.md` (delivered: `bin/oracfit-calibrate.py`; it refuses without a scored ring, it never writes the source policy, and the **threshold is the owner's number**, not a measurement) | the shipped policy stops being permanently `not calibrated` the moment the owner scores one ring |
| **18** | the **multi-stage runtime asks too**: the same chain, at the stage attempt boundary — `specs/sup-18-o-multi-stage-tambem-pergunta.md` (delivered: `bin/dispatch-stages.sh` consults the supervisor and applies `CONTINUE` and `INJECT_HINT`; it **refuses** `RESET` — the tree is shared across stages and HEAD is not a multi-stage checkpoint — and **refuses** `ESCALATE`, whose pause belongs to the stage's own owner-question channel) | the long runs, the ones with stages and gauntlet, stop degrading alone |
| **19** | the **ESCALATE reaches the owner in the multi-stage**: the stage's own pause close becomes one function, used by both the stage artifact and an applied ESCALATE — same inbox file, same status `owner_question`, same exit **7**, one question per run — `specs/sup-19-o-escalate-no-multi-stage.md` (delivered: `bin/dispatch-stages.sh`; `RESET` stays refused there) | when the supervisor judges that nobody in the system knows the answer, the main path can ask the owner instead of burning attempts |
| **20** | the **RESET in the multi-stage restores from the stage checkpoint**: the runtime takes a checkpoint at the run start and at the end of each stage (a side ref, a scratch index, tracked files only, HEAD and the real index untouched), and the reset restores from that checkpoint instead of HEAD — `specs/sup-20-o-reset-no-multi-stage.md` (delivered: `bin/lib-oracfit-checkpoint.sh` and a restore origin in `bin/lib-oracfit-supervisor.sh`; unset, the origin is still HEAD, so the single-stage is unchanged) | a derailed stage is undone without undoing the stages that came before it |
| **21** | the **ask lives in one place and asks only what the policy maps**: the ask block that the single-stage (rung 16) and the multi-stage (rung 18) each carried becomes one function — `bin/lib-oracfit-supervisor-ask.sh` — and the question goes out with **only the ids the policy's `rules` map**, so a policy with no rules asks nobody and no network call is made — `specs/sup-21-a-pergunta-mora-num-lugar-so.md` (delivered: the shared function plus an `--ids` pass-through in the ask chain; the shipped policy has empty `rules`, so the default behaviour is unchanged — nobody is asked) | the supervisor asks one or two questions instead of the whole set of 27, and the two runtimes cannot drift apart again |
| **22** | the **rehearsal**: the owner's mapping of questions to actions stops being a blind edit — a command shows, with no endpoint and no network, what the supervisor will ask and what it will do (the calibration, the threshold, how many of the 27 questions are mapped, and for each one the typed question, the criteria, the evidence, the cost, the action, and the hint or the owner-question forks), and refuses what is wrong (an id outside the question set, an invalid action, a hint-less INJECT_HINT or RESET, an ESCALATE without its fork) — `specs/sup-22-o-ensaio-da-politica.md` (delivered: a `validate` subcommand in the policy engine, which owns the grammar, and `bin/oracfit-supervisor-plan.py`, which calls it and only reports; the engine also exposes the calibration verdict, so the rehearsal never carries its own copy of the rule — an uncalibrated policy is a warning, not a refusal) | the owner can map the questions and see the whole plan before D1 turns the supervisor on |
| **23** | the **withheld question never reaches the wire**: the question set's own contract says a withheld question (one with no incident history behind it) must not be asked, and the mechanism to drop it existed but nobody used it — the ask chain now exports only the questions that are asked, and the rehearsal **refuses** a policy that maps a withheld one, quoting the reason the question gives about itself — `specs/sup-23-a-pergunta-retida-nao-vai-a-cabo.md` (delivered: the `--asked-only` export in `bin/oracfit-supervisor-ask.sh` and the refusal in the rehearsal; a run that maps one fails the ask before the network and continues without an order) | the contract stops being a sentence in a README and becomes something the code enforces |
| **24** | the **`json_schema` reaches the model**: the fifth field the loader accepted without a consumer — after `input: prev_stage`, `artifacts:`, `rate_limit_s` and `prompt_template` — now arrives: the runtime resolves the file the stage names, hands it to the model as the shape of the answer, and a declared schema whose file is missing fails the stage **before any model call** (`JSON SCHEMA NOT FOUND`), the same broken-promise rule as the prompt template — `specs/sup-24-o-json-schema-chega-ao-modelo.md` (delivered: `bin/lib-oracfit-json-schema.sh` (the sister of the prompt-template lib, not a copy of it), both runtimes honoring the field, the loader refusing an empty or non-string value, and the **four schemas the two shipped modes already declared** — written down, each one transcribing the shape its own stage's prompt already listed) | the answer shape stops being a promise in a YAML file and becomes something the model is actually told to answer |
| **25** | the **cursor dispatch closes the ledger**: the finalizer demanded `DB_PATH` and aborted before writing anything — so every dispatch through the cursor adapter (a CLI with no session store: the facts arrive in the stream) left no ledger line, no usage line and no session id, and the owner's panel showed nothing at all — `specs/sup-25-o-dispatch-cursor-fecha-o-ledger.md` (delivered: `DB_PATH` is optional now, and when the database yields nothing the finalizer reads the session id and the four token counters from the run's own log — the `result` event the CLI had already streamed; the database stays the primary source when it exists, and no runner was touched) | the cursor runs become visible, with the session id and the tokens that were always in the run |
| **26** | the **simple dispatch announces itself while it works**: the mode runtime emits `run_started` and `run_finished`, but the simple dispatch emitted nothing — so the owner's panel could only show a run *after* the fact, in the dispatches tab, and a run in flight looked like no run at all — `specs/sup-26-o-dispatch-aparece-no-painel.md` (delivered: the dispatch exports the run id and emits `run_started` before the runner starts, the finalizer closes it with one `run_finished` — `pass`, `fail` with a one-word reason — and the same run id makes the cursor runner write its trajectory to the same events file; the emit is best effort and never breaks the run) | the owner sees the run he started while it is still running, in the same panel |
| **27** | the **guard of the throttle stops lying about the throttle**: the suite that proves the runtime waits what the mode declares compared two runs measured in whole seconds and demanded one to be a full second longer than the other — under load both landed on the same second and the suite failed on a wait that had happened (`the declared throttle was ignored (3s vs 3s)`) — `specs/sup-27-o-suite-do-rate-limit-sem-flake.md` (delivered: the measurement is in milliseconds, the throttled run has to have lasted at least the throttle the fixture declares (minus a 150ms timer tolerance), the control became **behavioural** (a run without a throttle announces no wait), and the interrupt case is bounded generously instead of by a stopwatch; the runtimes were not touched — the runtime was right, the measurement was wrong) | a green suite means what it says, and the flaky gate stops eating trust |
| **28** | the **first real triad in the bank**: the whole supervisor mechanism existed (the compiler, the validator, the canary, the deterministic matcher, the injection at the attempt boundary) and the bank was **empty** — 126 incidents, zero triads, so the supervisor matched against nothing — `specs/sup-28-o-primeiro-trio-real.md` (delivered: one triad compiled from a real incident, its trigger written by hand and *narrow* (the round failed **and** the defect's own shape is still in the tree), the fire fixture pointing at versioned paths with a citation per value, a negative control that proves the trigger does not fire on any failed round, and the class `diffuse` — it names candidates, it never decides) | the bank stops being a schema and becomes memory with evidence in it |
| **29** | the **custom-mode tools refuse a broken promise**: a mode may declare `prompt_template` or `json_schema`; the runtime honours the promise (it dies with `PROMPT TEMPLATE NOT FOUND` / `JSON SCHEMA NOT FOUND` before any model call) but the tools that *create* the mode checked nothing — the broken promise only surfaced after the whole preparation, at the first stage — `specs/sup-29-o-tools-de-custom-mode-recusam-promessa.md` (delivered: the loader gained a `promises` subcommand that only **declares** the names (JSON), a new `bin/lib-oracfit-mode-promises.sh` **resolves** them by calling the two libs the runtime already uses (no second copy of "where the file lives"), and `mode validate`, `mode add` and `mode init` all refuse a broken promise at creation time, naming the promise that broke) | a mode that promises a missing file is refused where it is written, not where it dies |
| **30** | the **distiller reads the postmortem**: the distiller turned a *usage report* into a triad draft, but the corpus the owner actually has is 126 human **postmortems** — and the distiller refused them (no `task` in the frontmatter), so the bank could only grow one finished run at a time — `specs/sup-30-o-destilador-aceita-o-postmortem.md` (delivered: the distiller recognises the postmortem by the file itself and writes the draft with the incident's `## Sintoma` as the symptom and the incident's id as the triad's id, plus a **fire-fixture skeleton** next to the draft whose citations are the literal backticked strings of the incident — every one of them a literal substring of it; the trigger, the prescription and the skeleton's signals stay empty, because the hand writes the trigger) | growing the bank becomes a pipeline over the corpus, not a chore per incident |

A through E are independent of every open decision above: they are about
the evidence and the mechanism, not about the models. F onward needs the
serving decision (D1) — but only F, H and I do; C, D, E, G and J run on
nothing but bash and Python.

## Appendix A — reproducing every number in this note

```bash
cat VERSION                                   # 0.0.1
find incidents -maxdepth 1 -name '*.md' ! -name README.md | wc -l   # 126
ls incidents/uso/*.md | wc -l                 # 1048 (grows with every dispatch)
grep -h '^result:' incidents/uso/*.md | sort | uniq -c             # 937 / 63 / 48
ls core/modes/*.yaml | wc -l                  # 21
ls tests/test-*.sh | wc -l                    # 77
python3 -c "import json;print(len(json.load(open('model-registry.json'))['models']))"   # 31

# class-R rules out of the rules map (the legend line does not count: the
# rule rows are the ones whose FIRST cell is the rule number)
python3 -c "import re;print(sum(1 for l in open('fluxos/_comum/mapa-regras.md') if re.match(r'^\|\s*\d+\s*\|',l) and '**R**' in l))"   # 27

# trajectories: tool_call events, and how many carry arguments
python3 - <<'PY'
import json
n = with_input = 0
for line in open('.dispatch/logs/events.jsonl'):
    line = line.strip()
    if not line:
        continue
    o = json.loads(line)
    if o.get('type') == 'tool_call':
        n += 1
        with_input += 1 if o.get('input') else 0
print(n, with_input)                          # 273 0
PY

# usage rows that do not parse
python3 - <<'PY'
import json
bad = 0
for line in open('.dispatch/usage/usage.jsonl'):
    line = line.strip()
    if not line:
        continue
    try:
        json.loads(line)
    except ValueError:
        bad += 1
print(bad)                                     # 0 after the rung E repair (46 before it, of 1010)

# the repair that recovers those rows (keeps every row; quarantines the rest)
python3 bin/oracfit-usage-json.py repair .dispatch/usage/usage.jsonl --in-place
PY

# the runtime asymmetry
grep -n 'trap ' bin/dispatch-mode.sh          # one trap: lock release only
grep -n 'trap ' bin/dispatch-stages.sh        # EXIT / TERM / INT + emergency epilogue

# the local GPU and the board
nvidia-smi --query-gpu=name,memory.total,power.limit --format=csv
lspci -tv
free -m
```

And the decision-model menu (the sizes in §9):

```bash
curl -s "https://huggingface.co/api/models/ggml-org/Kev-4B-GGUF?blobs=true" \
  | python3 -c "import json,sys;[print(f['rfilename'], round((f.get('size') or 0)/1e9,2),'GB') for f in json.load(sys.stdin)['siblings'] if f['rfilename'].endswith('.gguf')]"
# Kev-4B-BF16.gguf 8.43 GB / Kev-4B-Q4_K_M.gguf 3.03 GB / Kev-4B-Q8_0.gguf 4.48 GB

# the endpoint llama.cpp serves (PR #29818, merged 2026-10-02)
curl -s https://api.github.com/repos/ggml-org/llama.cpp/pulls/29818 \
  | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['title'],d['merged_at'])"
# llama, server: add /v1/systemone API (models: laya, julia-1, lev, openjev, kev)
```

And the gotcha corpus (§5.2, and the numbers quoted in
`specs/sup-03-gotcha-compilado.md`):

```bash
find incidents -maxdepth 1 -name '*.md' ! -name README.md | wc -l   # 126
grep -h '^## Sintoma' incidents/*.md | wc -l                        # 103 occurrences
grep -h '^## Sintoma' incidents/*.md | sort | uniq -c               # the 3 heading variants
grep -h '^## Correção aplicada' incidents/*.md | wc -l              # 62 occurrences
grep -l '^## Correção aplicada' incidents/*.md | wc -l              # 69 files
grep -h '^regra:' incidents/*.md | sort | uniq -c | sort -rn        # free text, not only numbers
grep -rli gotcha . --include='*.md' --include='*.py' --include='*.sh'
# only docs/decision-supervisor.md — no gotcha mechanism exists in the tree
ls -d gotchas lessons 2>/dev/null                                   # neither exists
```

And the git-plumbing facts in §5.5 (reproducible in a scratch repo):

```bash
d="$(mktemp -d)"; cd "$d"; git init -q .; git config user.email t@t; git config user.name t
printf 'a\n' > f.txt; git add f.txt; git commit -qm init
printf 'dirty\n' > f.txt; printf 'new\n' > g.txt

# (1) write-tree captures the INDEX, not the working tree
git ls-tree -r "$(git write-tree)" --name-only        # f.txt only — the edit and g.txt are missing

# (2) the scratch index outside the workdir captures both
idx="$(mktemp /tmp/scratch.XXXXXX.idx)"; rm -f "$idx"
GIT_INDEX_FILE="$idx" git read-tree HEAD
GIT_INDEX_FILE="$idx" git add -A
GIT_INDEX_FILE="$idx" git write-tree | xargs git ls-tree -r --name-only   # f.txt AND g.txt
rm -f "$idx"

# (3) commit-tree needs an identity
git -c user.email= -c user.name= commit-tree "$tree" -p HEAD -m wip     # Author identity unknown

# (4) the empty tree, for a repo with no commit
git hash-object -t tree /dev/null                      # 4b825dc642cb6eb9a060e54bf8d69288fbee4904
```

## Appendix B — files this design touches

| Path | Role |
|---|---|
| `bin/dispatch-mode.sh` | single-stage runtime; needs the epilogue (rung A) |
| `bin/dispatch-stages.sh` | multi-stage runtime; already has the epilogue to mirror |
| `adapters/cursor/stream-events.py` | cursor trajectory translator; needs `input` (rung B) |
| `bin/oracfit-thinking-tee.py` | opencode trajectory translator; already emits `input` |
| `bin/oracfit-behavior-scan.py` | the deterministic Tier-0 scanner the supervisor learns from |
| `bin/oracfit-ring.sh` | the calibration loop (`owner_score_pred` vs real) |
| `bin/emit-usage-feedback.sh` | writes the malformed `extra` field (rung E) |
| `bin/lib-oracfit-gauntlet.sh` | the feedback + ground-truth injection channel (rung D) |
| `bin/dispatch-stages.sh` | the `owner_question` contract (line 445) and the exit-7 path (line 589) |
| `core/protected-paths-default.txt` | the rule-47 globs a scoped restore must skip (rung D2) |
| `fluxos/_comum/mapa-regras.md` | the 27 class-`R` rules = the question set (rung G) |
| `incidents/` | the prose corpus the triads are compiled from (rung C) |
| `core/gotchas/` | the triad bank (rung C) — created by the spec below |
| `bin/oracfit-gotcha.py` | the triad compiler and validator (rung C) plus `evaluate`, the matcher over a signals bundle (rung D) |
| `bin/lib-oracfit-gotcha.sh` | the Tier-0 scan, the signals bundle and the prescription injection at the attempt boundary (rung D) |
| `specs/sup-01-evidencia-quando-o-run-morre.md` | dispatchable spec, rung A |
| `specs/sup-02-argumentos-das-tool-calls.md` | dispatchable spec, rung B |
| `specs/sup-03-gotcha-compilado.md` | dispatchable spec, rung C |
| `specs/sup-04-reset-sem-destruir-evidencia.md` | dispatchable spec, rung D2 |
| `specs/sup-05-matcher-determinista.md` | dispatchable spec, rung D |
| `specs/sup-06-usage-jsonl-legivel.md` | dispatchable spec, rung E |
| `bin/oracfit-usage-json.py` | the JSON rules for the usage slots, the line check and the repair of the base (rung E) |
| `core/supervisor/questions.json` | the typed question set, one question per class-`R` rule (rung G) |
| `bin/oracfit-questions.py` | the validator, the index and the System-One export of the question set (rung G) |
| `core/supervisor/README.md` | the contract of the question set (rung G) |
| `specs/sup-07-perguntas-tipadas.md` | dispatchable spec, rung G |
| `bin/oracfit-systemone.py` | the client of `POST /v1/systemone` (rung H) |
| `docs/SYSTEMONE.md` | the contract of the client (rung H) |
| `specs/sup-09-cliente-systemone.md` | dispatchable spec, rung H |
| `bin/oracfit-distill.py` | the post-loop distiller: usage report → draft triad (rung J) |
| `core/gotchas/drafts/README.md` | the contract of the draft folder (rung J) |
| `specs/sup-10-destilador-pos-loop.md` | dispatchable spec, rung J |
| `bin/oracfit-policy.py` | the policy engine: typed answers → one order (rung I) |
| `core/supervisor/policy.json` | the shipped policy — uncalibrated, so it always continues (rung I) |
| `core/supervisor/policy.md` | the contract of the policy (rung I) |
| `specs/sup-11-politica-do-supervisor.md` | dispatchable spec, rung I |
| `specs/sup-12-telemetria-log-tail.md` | dispatchable spec, rung 12 (the `log_tail` defect) |
| `bin/lib-oracfit-supervisor.sh` | the runtime side of the order: applies it at the attempt boundary (rung 13) |
| `specs/sup-13-runtime-executa-a-ordem.md` | dispatchable spec, rung 13 |
| `specs/sup-14-reset-executavel.md` | dispatchable spec, rung 14 (the executable RESET) |
| `specs/sup-15-escalate-pausa-a-run.md` | dispatchable spec, rung 15 (the executable ESCALATE) |
| `tests/test-supervisor-escalate.sh` | the suite of the executable ESCALATE: pause, inbox, ledger, usage, refusals (rung 15) |
| `specs/ref-r13-prova-obsoleta.md` | refinement spec: retargets the rung-13 proof at an unknown action (rung 15) |
| `bin/oracfit-supervisor-ask.sh` | the ask chain: export the question set, ask System-One, hand the answers to the policy engine (rung 16) |
| `tests/test-supervisor-ask.sh` | the suite of the ask: no endpoint asks nothing, the answers become an order, a failing endpoint does not fail the run (rung 16) |
| `specs/sup-16-o-runtime-pergunta.md` | dispatchable spec, rung 16 (the runtime asks) |
| `bin/oracfit-calibrate.py` | the calibration recorder: a scored ring plus the owner's threshold become a derived policy (rung 17) |
| `tests/test-supervisor-calibrate.sh` | the suite of the calibration: no score is refused, the line is copied, the threshold is the owner's (rung 17) |
| `specs/sup-17-a-calibracao-e-registrada.md` | dispatchable spec, rung 17 (the calibration is recorded) |
| `tests/test-supervisor-stages-ask.sh` | the suite of the multi-stage ask: the hint reaches the next stage attempt, RESET and ESCALATE are refused there (rung 18) |
| `specs/sup-18-o-multi-stage-tambem-pergunta.md` | dispatchable spec, rung 18 (the multi-stage asks too) |
| `specs/sup-19-o-escalate-no-multi-stage.md` | dispatchable spec, rung 19 (the ESCALATE reaches the owner in the multi-stage) |
| `bin/lib-oracfit-checkpoint.sh` | the checkpoint: a side-ref commit of the tracked tree, scratch index, nothing moved (rung 20) |
| `specs/sup-20-o-reset-no-multi-stage.md` | dispatchable spec, rung 20 (the RESET in the multi-stage) |
| `bin/lib-oracfit-supervisor-ask.sh` | the shared ask: both runtimes write the round's state and call this (rung 21) |
| `specs/sup-21-a-pergunta-mora-num-lugar-so.md` | dispatchable spec, rung 21 (the ask lives in one place and asks only the mapped questions) |
| `bin/oracfit-supervisor-plan.py` | the rehearsal: the policy as a readable plan, with no endpoint and no network (rung 22) |
| `tests/test-supervisor-plan.sh` | the suite of the rehearsal: what it shows, what it refuses, what it does not do (rung 22) |
| `specs/sup-22-o-ensaio-da-politica.md` | dispatchable spec, rung 22 (the rehearsal of the policy) |
| `specs/ref-r22-o-veredito-da-calibracao.md` | refinement spec: the engine exposes the calibration verdict; the rehearsal only reports it (rung 22) |
| `specs/sup-23-a-pergunta-retida-nao-vai-a-cabo.md` | dispatchable spec, rung 23 (the withheld question never reaches the wire) |
| `bin/lib-oracfit-json-schema.sh` | the answer shape a stage declares: resolves the file and hands it to the model (rung 24) |
| `core/schemas/` | the four JSON Schemas the shipped modes declare — one per stage that names one (rung 24) |
| `tests/test-json-schema.sh` | the suite of the answer shape: the runtime hands it over, a missing file breaks the promise, the loader refuses an empty value (rung 24) |
| `specs/sup-24-o-json-schema-chega-ao-modelo.md` | dispatchable spec, rung 24 (the `json_schema` reaches the model) |
| `bin/lib-oracfit-session-facts.py` | the reader of the run facts: the session id and the token counters from the stream's `result` event (rung 25) |
| `tests/test-cursor-ledger.sh` | the suite of the closed ledger: the cursor dispatch closes it, the database still wins, the usage row carries the session id (rung 25) |
| `specs/sup-25-o-dispatch-cursor-fecha-o-ledger.md` | dispatchable spec, rung 25 (the cursor dispatch closes the ledger) |
| `bin/dispatch.sh` | the simple dispatch: exports the run id and announces the run before the runner starts (rung 26) |
| `bin/ledger-finalize.sh` | the finalizer: closes the announce with one `run_finished`, best effort, after the ledger and usage rows (rung 26) |
| `tests/test-dispatch-events.sh` | the suite of the announce: the run appears, it closes, it fails, it is alive while working, and the event never breaks the run (rung 26) |
| `specs/sup-26-o-dispatch-aparece-no-painel.md` | dispatchable spec, rung 26 (the simple dispatch appears in the panel) |
| `tests/test-rate-limit.sh` | the suite of the throttle: the runtime waits what the mode declares, measured in milliseconds (rung 27 — the measurement was wrong, not the runtime) |
| `specs/sup-27-o-suite-do-rate-limit-sem-flake.md` | dispatchable spec, rung 27 (the rate-limit suite measures instead of subtracting) |
| `core/gotchas/2026-08-12-dispatch-escalate-chama-opencode-cru-sem.json` | the first real triad: compiled from a recorded incident, trigger written by hand, class `diffuse` (rung 28) |
| `tests/fixtures/gotchas/2026-08-12-dispatch-escalate-chama-opencode-cru-sem.fire.json` | the fire evidence: real signals plus a citation per value (rung 28) |
| `tests/fixtures/gotchas/generic-failure.json` | the negative control: a round that failed in a generic way must not fire the triad (rung 28) |
| `tests/test-gotcha-bank.sh` | the suite of the bank: it is not empty, the triad fires on its own evidence, stays quiet on a healthy round, is narrow, and every trigger value is quoted from the incident (rung 28) |
| `specs/sup-28-o-primeiro-trio-real.md` | dispatchable spec, rung 28 (the first real triad) |
| `bin/lib-oracfit-mode-promises.sh` | the conference of the promises: it resolves the declared `prompt_template` / `json_schema` by calling the two libs the runtime uses (rung 29) |
| `bin/lib-oracfit-mode-loader.py` | the reader of the mode YAML; the `promises` subcommand only declares the promised names (rung 29) |
| `tests/test-mode-promises.sh` | the suite of the promise: a broken promise is refused at creation time, a resolvable one passes, and the check agrees with the runtime resolution (rung 29) |
| `specs/sup-29-o-tools-de-custom-mode-recusam-promessa.md` | dispatchable spec, rung 29 (the custom-mode tools refuse a broken promise) |
| `bin/oracfit-distill.py` | the distiller: reads a usage report **or** a human postmortem and writes the triad draft (rung 30) |
| `tests/test-distill-postmortem.sh` | the suite of the postmortem path: the draft, the symptom, the empty trigger, the literal citations, the refused postmortem, and the old path intact (rung 30) |
| `specs/sup-30-o-destilador-aceita-o-postmortem.md` | dispatchable spec, rung 30 (the distiller accepts the postmortem) |
