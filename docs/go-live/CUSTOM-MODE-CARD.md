# Name your break — custom modes in 5 minutes

> The lineup has three waves (`paddle`, `tow`, `surfcheck`). The rest of the
> ocean is yours: a custom mode is the break you find and name. One file,
> one validate, one run, one oracle. A stranger should read this card in
> 2 minutes. Zero schema changes — everything below validates against the
> loader shipped in this tree (`bin/lib-oracfit-mode-loader.py`).

## The whole grammar

```yaml
id: my_break            # [a-z0-9_]+ — name your break
version: "1"
name: my break
description: one honest line (no claims you cannot back with code)
stages:                 # 1..N sections of the wave, run in order
  - role: run           # unlock | plan | run | map | reduce
    model_ref: tier:cheap   # tier:cheap | tier:mid | tier:expensive | tier:vision
    oracle: true        # the gate comes from your task spec (see below)
    max_attempts: 3
  # a stage can also be mechanical — no model at all:
  # - role: run
  #   command: bash scripts/build.sh
gauntlet:               # optional: retry loop that injects oracle feedback
  enabled: true
  inject_feedback: true
  until_approved: true
  safety_ceiling: 5     # hard stop — no infinite paddling
  # precedence: with until_approved: true, safety_ceiling WINS over
  # max_attempts (effective ceiling = the LARGER of the two). max_attempts
  # alone only governs stages without a gauntlet block.
on_fail: halt           # a red stage never starts the next one
```

Rules of the water:

1. **The oracle is a real command on disk, and it decides — not the model.**
   It lives in your task spec under `## Oraculo`, as a raw line:
   `- comando: grep -q stub_ok .dispatch/stub-proof` —
   **never wrap it in backticks** (they become command substitution in the
   eval and die with a phantom exit 127 — incident 2026-08-10).
2. **Private by default.** Your mode is a file in *your* workdir
   (`core/modes/my_break.yaml`); it shadows built-ins and never leaves your
   machine unless you post it.
3. **Public = the file.** `oracfit mode share my_break` prints the canonical
   YAML; a friend runs `oracfit mode add my_break.yaml` and it installs only
   if `validate` + `lint` pass.
4. Keys outside the grammar above exist (`command:`, `input: prev_stage`,
   `artifacts:`, budgets) — `oracfit mode validate` will tell you if you
   step outside the schema. Anything truly new requires a schema extension
   plus a loader test: that is a cost decision, not a YAML edit.

## The three commands

```bash
llms-surf mode init my_break      # writes the scaffold to your workdir
llms-surf mode validate my_break  # schema says yes/no, with the reason
llms-surf run my_break task.md t1 # dispatch; the oracle closes it
```

## Example 1 — `glassy`: your own paddle

Clone of `normal`. Same pipeline, your break, your oracle. The oracle
command is per-task (in the spec), so this one file covers every mechanical
chore you throw at it.

```yaml
id: glassy
version: "1"
name: glassy
description: clean conditions — one cheap rider, your spec oracle decides
stages:
  - role: run
    model_ref: tier:cheap
    oracle: true
    max_attempts: 3
gauntlet:
  enabled: true
  inject_feedback: true
  until_approved: true
  safety_ceiling: 5
on_fail: halt
```

## Example 2 — `outside_set`: a two-stage mini tow

An outside set is too big to paddle into: an expensive model reads the wave
(and must pass its own oracle before anyone drops in), then a cheap model
rides it. A red unlock never starts the run.

```yaml
id: outside_set
version: "1"
name: outside set
description: expensive reads the wave, cheap rides it, red never drops in
stages:
  - role: unlock
    model_ref: tier:expensive
    artifacts: unlock/
    oracle: true
    max_attempts: 2
  - role: run
    model_ref: tier:cheap
    input: prev_stage
    oracle: true
    max_attempts: 3
gauntlet:
  enabled: true
  inject_feedback: true
  until_approved: true
  safety_ceiling: 4
on_fail: halt
```

Both examples were validated against the current loader in this session
(`validate` + `lint` green, no schema delta).

## The light game (no XP, no leaderboard)

- **First wave** — a green oracle within the first hour (the stub proves the
  path with zero tokens).
- **Your own break** — first custom mode that passes `validate` + `lint`
  and closes a run with a green oracle.
- **Share the break** — post the YAML (never a key, never a secret; the
  file has neither by construction).
- **Wipeouts are already real** — 106 incident postmortems in this cut.
  That ledger is the score; we do not invent a second one.
