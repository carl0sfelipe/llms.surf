# Modes catalog — the YAML that drives a dispatch

This is the reference the CLI points at. It is the whole syntax of a mode file,
plus how to create one without copying from the source tree by hand.

A mode is a YAML file that says **what runs, in which order, and what decides
that the work is done**. The dispatcher never asks a model whether the work is
finished: the oracle does, mechanically.

---

## 1. Where a mode file lives

Two places, and the workdir wins:

```
<workdir>/core/modes/<id>.yaml    # the project you are working in
<ORACFIT_ROOT>/core/modes/<id>.yaml   # the installation
```

The order is: **workdir overlay first, then ROOT**. A mode with the same id in
both places shadows the ROOT one — in the listing and in `oracfit run <id>`.
Both places are seen, so the same file resolves the same way in the listing and
in the run.

`oracfit mode add` always writes to the workdir overlay, never to ROOT.

## 2. The two runtimes

| Runtime | Used when | Knows about |
|---|---|---|
| `bin/dispatch-mode.sh` | a single stage **without** `command:` | models only |
| `bin/dispatch-stages.sh` | more than one stage, **or** any stage with `command:` | models and mechanical stages |

The router in `bin/oracfit` (`cmd_run`) picks between them. The property that
decides "this stage is mechanical" is the presence of `command:` — never the
number of stages.

## 3. Root keys

```yaml
id: my_break              # required. lower_snake_case, unique in the overlay
version: "1"              # required. string, quoted so YAML keeps it a string
name: My Break            # optional. human label
description: >             # optional. one paragraph, plain language
  What this mode does.
stages: [...]              # required. at least one stage
max_attempts: 3            # optional. default attempts per stage
preflight: <command>       # optional. runs before the first stage (a shell
                            # command, or a list of preflight check names)
on_fail: halt              # optional. halt (default) or continue
gauntlet: {...}            # optional. see §5
run_attempt_budget: 5      # optional. global cap on role=run attempts
publish: {...}             # optional. publish config; requires human_approval
```

`id` must match `[a-z0-9_]+`. A mode whose id is invalid is refused at
creation time, not at run time.

## 4. A stage

```yaml
stages:
  - role: run              # unlock | plan | run | map | reduce | export | render | vision_gate
    model_ref: tier:cheap  # a tier (tier:cheap|mid|expensive|vision) or a registry id
    command: <shell>       # a mechanical stage: this command runs instead of a model
    oracle: true           # this stage is gated by the oracle
    input: prev_stage      # feed the previous stage's output in
    artifacts: out/        # directory for this stage's artifacts
    prompt_template: ...   # file with the prompt for this stage
    json_schema: ...       # file with the JSON schema the answer must match
    tools: true            # allow the runner to use tools
    max_attempts: 3        # attempts for this stage
    rate_limit_s: 0        # pause between attempts
    owner_question: once   # may pause the run to ask the owner one question
    stage_oracle: <cmd>    # deterministic gate after a command stage
    oracle_command: <cmd>  # alias of stage_oracle
    preflight: <cmd>       # deterministic gate before the attempt
    preflight_command: <cmd>
    freshness_targets: []  # paths that must be fresh (visual stages)
```

**A stage is one of two things.** Either it has `model_ref` and calls a model,
or it has `command` and runs a script. A stage with `command:` and no
`model_ref` is *mechanical*: no model is dispatched, the command runs, and the
oracle decides the verdict. A stage with both is refused by the loader — the
runtime would call the model and drop the command without a word.

**Roles.** `unlock`, `plan`, `run`, `map`, `reduce`, `export`, `render`,
`vision_gate`. A `map` stage must declare `rate_limit_s > 0`.

**`input: prev_stage`.** A stage that declares it reads the work of the stages
before it. For every stage that ran, the runtime renders the answer it produced
(the runner log) and the files it wrote in its artifacts directory, and injects
the whole chain into the stage's spec. A mechanical stage (a `command:`) never
reads the spec, so it receives the same rendering in
`ORACFIT_PREV_STAGE_INPUT_FILE`, with `ORACFIT_PREV_STAGE_ROLE` and
`ORACFIT_PREV_STAGE_ARTIFACTS` next to it. The first stage of a mode cannot
declare it — the loader refuses the file, because there is no stage before it.
`input` also carries other values with their own meaning (`files_glob` in a
vision map stage, a directory path read by the stage's `command:`); only the
literal `prev_stage` chains stages.

**Tiers.** `tier:cheap`, `tier:mid`, `tier:expensive` and `tier:vision` expand
into an ordered chain of models from the free catalog / registry. The first
provider with usable credentials wins; the rest are fallbacks. A registry id
(`model_ref: deepseek-v4-pro`) pins one model exactly.

**Comments are allowed** on a value: `model_ref: tier:cheap   # the cheap tier`
resolves to `tier:cheap`.

## 5. The gauntlet

```yaml
gauntlet:
  enabled: true
  inject_feedback: true    # a failed oracle is fed back into the next attempt
  until_approved: true     # keep retrying until the oracle approves
  safety_ceiling: 5        # hard cap on attempts (exit code 2 when reached)
```

`inject_feedback` is what makes a mode self-correcting: the oracle's complaint
about attempt N is the input of attempt N+1.

`on_fail: halt` means a red stage stops the run — a failed unlock never starts
the run stage.

## 6. Pausing for the owner

```yaml
stages:
  - role: unlock
    owner_question: once
```

When the stage hits a fact only the owner has, the run **pauses** instead of
burning expensive attempts guessing:

- status becomes `owner_question`, exit code is `7`
- the question is written to `owner-question.md` in the artifacts dir, with
  the consequences of each possible answer spelled out
- resume with `oracfit resume <run_id> "<answer>"`

## 7. Creating a custom mode

```bash
# a scaffold: one cheap stage, gauntlet on, the grammar in comments
oracfit mode init my_break

# a copy of a built-in mode, renamed (aliases work too)
oracfit mode init big_day --from tow        # tow == unlock_plan

# check it before running it
oracfit mode validate my_break
oracfit mode lint my_break

# see what a mode does, without opening the YAML
oracfit mode show tow            # a surf alias works here too

# run it
oracfit run my_break task.md t-my-break

# print the YAML ready to paste into an issue
oracfit mode share my_break

# install someone else's shared YAML in this workdir
oracfit mode add ./pasted-mode.yaml
```

`mode init --from` copies the source's stages and renames the id. `mode add`
validates before it writes, refuses to overwrite an id with different content,
and writes nothing when the file is invalid.

Four ready-made examples live in `examples/`:

| File | Shape |
|---|---|
| `glassy.yaml` | one cheap stage — the simplest mode there is |
| `outside_set.yaml` | an expensive unlock, then a cheap run |
| `mechanical.yaml` | a stage that runs a script, no model at all |
| `elevate.yaml` | unlock, then run with the unlock in its input |

```bash
oracfit mode add ./examples/mechanical.yaml
```

## 8. Two modes worth knowing

| Mode | Alias | Shape |
|---|---|---|
| `normal` | `paddle` | one cheap stage, gauntlet with feedback, oracle-gated |
| `unlock_plan` | `tow` | unlock (expensive) → plan (mid) → run (cheap), `on_fail: halt` |

`normal` is the mechanical one: one cheap model, retried until the oracle
approves, capped by `safety_ceiling`.

`unlock_plan` is the elevating one: it spends an expensive unlock to clear the
plan, then plans at mid cost, then runs at cheap cost. A red unlock halts the
run before anything is spent downstream.

## 9. The rules the loader enforces

- unknown keys are refused (a typo fails `mode validate`, it does not get
  silently ignored)
- `id`, `version` and at least one stage are required
- `role` must be one of the eight roles; a `map` stage needs `rate_limit_s > 0`
- a stage with `command:` may not also carry `model_ref`
- `stage_oracle`, `oracle_command`, `preflight` and `preflight_command` must be
  non-empty command strings
- `freshness_targets` must be a non-empty list of paths
- `run_attempt_budget` must be a positive integer

The canonical check is mechanical: `oracfit mode validate <id>` — exit 0 means
the file is loadable and legal, not that the mode is a good idea. For the
second half (does the description match what the mode actually does), use
`oracfit mode lint <id>`.

The loader has a second reader for machines without PyYAML. Both readers must
read the same file the same way, and `tests/test-mode-loader.sh` compares them
on every mode and example in the tree — two readers that disagree are how a
mode behaves differently on one laptop than on another.
