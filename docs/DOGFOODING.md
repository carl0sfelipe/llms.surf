# Dogfooding llms.surf

This is the guide for the first thing **you** build with the factory: a real
thing you need, made by the machine, with the oracle deciding whether it
worked.

Nothing here needs a GPU, a local model or an API key to start. A mechanical
mode — a stage that runs a command — costs nothing and proves the loop.
A model only enters where a machine cannot check the answer.

---

## 0. Install (2 minutes, no key)

```bash
git clone https://github.com/carl0sfelipe/llms.surf.git
cd llms.surf
export ORACFIT_ROOT="$PWD" DISPATCH_RUNNER="$PWD/adapters/stub/runner.sh"
```

`bin/llms-surf` is the public facade; `bin/oracfit` is the same CLI under the
old name. Everything below works with either.

```bash
bin/llms-surf start      # first proof: the whole loop on a stub, $0 spent
bin/llms-surf gui        # http://127.0.0.1:8766/home.html — mission control
```

`start` is the honest proof of life: it runs the full loop (spec → attempt →
oracle → verdict) with the stub runner. If `start` is green, the machine is
installed correctly.

To use a real model later, source one adapter and drop the stub:

```bash
source adapters/cursor/env.sh        # or claude-code, opencode, qwen-code…
```

---

## 1. The loop in four commands

```bash
oracfit spec init task.md        # a spec that already passes the gate
$EDITOR task.md                  # say what must exist when it is done
oracfit mode init my_mode        # a mode: the shape of the work
oracfit run my_mode task.md my-task
oracfit status --task my-task    # the canonical verdict (JSON)
oracfit panel                    # observe every run, live
```

The four commands are the whole product:

| command | what it really does |
|---|---|
| `spec init` | writes a spec whose oracle is **red on purpose** — it fails before the work exists |
| `mode init` | scaffolds a mode YAML **into `core/modes/` of this workdir**, already installed |
| `run` | dispatches the spec through the mode; the oracle decides green or red |
| `status` | the last verdict of that task, machine-readable — no model opinion involved |

(`mode init` installs the mode where `run` finds it. A YAML you wrote or
received somewhere else goes through `mode add` — see section 5.)

---

## 2. Write the spec: the oracle is the whole contract

A spec has three things that matter: the **task** (which files must exist),
the **verified data** (every fact the worker may use) and the **oracle** (one
command that is red before the work and green after).

```markdown
# Task: a CLI that prints the install line of the project

## Task

Create `scripts/install-line.sh`. It prints exactly one line:
`llms.surf - the budget leads, the oracle decides`

## Rules

Do not invent names, dates or numbers beyond the ones listed here.
Never use declare const or an empty stub as a workaround: import and implement for real.

## Verified data

- The sentence the script must print is the one in the Oracle command below.

## Oracle

- command: test -f scripts/install-line.sh && scripts/install-line.sh | grep -qx "llms.surf - the budget leads, the oracle decides"
- expected exit: 0

## Verification

VERIFICATION: test -f scripts/install-line.sh && scripts/install-line.sh | grep -qx "llms.surf - the budget leads, the oracle decides"
```

Three rules that bite, and why:

1. **The oracle must fail before the work exists.** A command that fails
   because it does not exist yet is a *valid* red oracle; a command that fails
   because it is a typo is not. The gate (`oracfit spec check`) refuses the
   second one.
2. **Every fact goes in "Verified data".** A path written between backticks
   there is checked against the workdir *before any model is called*. If the
   file does not exist, the run stops there — it does not burn money to
   hallucinate. (A path in an *instruction* — "create `x.sh`" — is free: it
   is what the worker has to produce, not a claim about today.)
3. **Two clauses the gate demands**: the anti-invention line ("never use
   declare const or an empty stub") and a `VERIFICATION:` line that proves
   the property. A spec without them is refused.

Check the spec before spending anything:

```bash
oracfit spec check task.md
```

`oracfit spec init task.md` writes exactly this skeleton — start from it
instead of from a blank page.

---

## 3. The mode: mechanical first, model only where needed

`oracfit mode init <id>` scaffolds a mode; `oracfit mode init <id> --from
paddle` copies an existing one (aliases: `paddle` = normal, `tow` =
unlock_plan, `surfcheck` = ui_visual_qa).

A stage is **model-backed** when it has a `model_ref:` — the model writes the
arm, and the oracle still decides. A stage is **mechanical** when it has a
`command:` — then **no model is called at all**: the machine runs the command
and the oracle checks the result. A mechanical stage runs something that
*already exists* (a builder, a test, a formatter, a generator): it is the
cheap, deterministic part of the work.

The canonical shape is a chain: the model writes, the machine verifies.

```yaml
id: my_mode
version: "1"
description: >
  The model writes the file; the machine runs it and decides.
stages:
  - role: run
    model_ref: tier:cheap
    oracle: true
    max_attempts: 3
  - role: render
    command: >
      cd "$ORACFIT_WORKDIR" &&
      test -f scripts/install-line.sh &&
      scripts/install-line.sh | grep -qx "llms.surf - the budget leads, the oracle decides"
    oracle: true
    max_attempts: 2
gauntlet:
  enabled: true
  inject_feedback: true
  safety_ceiling: 4
on_fail: halt
```

The roles the grammar accepts are fixed: `unlock`, `plan`, `run`, `map`,
`reduce`, `export`, `render`, `vision_gate`. `unlock → plan → run` is the
expensive-to-cheap chain (`tow`); `run` alone is `paddle`.

Before it runs, the mode has to survive three gates:

```bash
oracfit mode validate my_mode.yaml   # grammar + the files the stages promise
oracfit mode lint my_mode.yaml       # every claim points at an existing mechanism
oracfit mode show my_mode.yaml       # the shape of the mode, without opening the YAML
oracfit mode add my_mode.yaml        # install it in this workdir, validated
```

`mode validate` also refuses a mode that **promises a file that does not
exist** (`prompt_template` / `json_schema`) — at creation time, naming the
promise that broke, instead of at the first stage of a paid run.

---

## 4. Run it and watch it

```bash
oracfit run my_mode task.md my-task
oracfit status --task my-task     # the verdict, as JSON
oracfit panel                     # every run of this workdir, live
```

The panel shows the run **while it works** — the run announces itself when it
starts and closes itself when it ends, so a run that is stuck is visible as
stuck. The ledger row (`ledger/ledger.jsonl`) keeps the cost, the tokens and
the oracle exit of every run; `oracfit roi` sums it.

A red run is the normal first run: the oracle is red until the work exists,
and the stub runner writes nothing, so a stub run ends red **on purpose**.
What matters is the shape of the failure — the gauntlet prints the gap, and
the next attempt gets that gap as feedback:

```
gauntlet stage=run attempt=1 gap=oracle exited 1 with empty output …
ERROR: stage run failed after 3 attempts
status: fail
```

`oracfit status --task my-task` then gives the machine-readable verdict:

```json
{"task": "my-task", "run_id": "…", "status": "fail", "attempts": 3, "last_oracle_exit": "1"}
```

Fix the spec or the code, run it again with a new task name. A red run is
structured feedback, not a loss.

---

## 5. Share a mode (second machine, second person)

```bash
oracfit mode share my_mode        # prints the YAML ready to post
oracfit mode add their-mode.yaml  # on the other machine: installs it, validated
```

`add` installs into the workdir overlay, never into the install. It refuses an
invalid YAML and it refuses a mode whose promised files do not resolve — and
it leaves nothing half-installed.

---

## 6. Where things live

| path | what it is |
|---|---|
| `core/modes/*.yaml` | the shipped modes (21 of them) |
| `core/prompts/`, `core/schemas/` | the files a mode may promise by name |
| `core/gotchas/` | the memory of the factory: triads compiled from real incidents |
| `incidents/` | 126 postmortems; the raw material of the triads |
| `ledger/ledger.jsonl` | the ledger of every run: cost, tokens, oracle exit |
| `.dispatch/` | logs and events of this workdir |
| `docs/decision-supervisor.md` | the design of the supervisor and the ladder it climbs |
| `specs/` | **private**, gitignored: the dispatchable specs live here |

Note the last row: `specs/` is private to your machine and is never committed.
The public surface is the code, the modes, the incidents and the docs.

---

## 7. The doctrine, in three lines

- **The machine decides, not the model.** Nothing ships on a model's word —
  not even the judge's.
- **A green oracle is the only victory.** The oracle fails before the work and
  passes after it; everything else is feedback for the next attempt.
- **A recurring failure becomes a mechanism.** Every incident that repeats
  ends as a rule, a test or a triad — not as a story.

That is the flywheel: build the thing you need, and every failure you hit on
the way turns into protection for the next thing you build.
