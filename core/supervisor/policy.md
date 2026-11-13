# Supervisor policy contract

The policy is a deterministic map from **question ids** to one of four
actions. It reads typed answers (the System-One record from
`bin/oracfit-systemone.py`) and writes **one order**. It does not inject a
hint, restore a tree, take a snapshot, pause a run, or call git.

**The policy writes the order; the runtime is who executes it.**

## Engine

```
python3 bin/oracfit-policy.py decide \
  --answers <file.json> \
  --policy <file.json> \
  [--state <file.json>] \
  [--out <file.json>]
```

Exit: 0 decided · 1 did not decide · 3 usage error.

`--state`, when given, is read and **not interpreted**. It exists so a
caller can pass the round's state without the engine inventing anything
about it. The engine never writes the workdir. The only file it writes is
`--out`, and only when the caller passes `--out`.

## Policy file

Shipped at `core/supervisor/policy.json`. Shape:

```json
{
  "version": 1,
  "calibration": {"ring": "", "line": ""},
  "thresholds": {"act_above": 0.8},
  "rules": {
    "r42-long-job-outside-dispatch-is-orphan": {
      "action": "ESCALATE",
      "pergunta": "...",
      "se": ["se ... -> ...", "se ... -> ..."]
    }
  }
}
```

| field | meaning |
|---|---|
| `version` | integer version of the policy |
| `calibration.ring` | name of the ring that measured this policy. Empty = not calibrated |
| `calibration.line` | the ring's `CALIBRATION` log line, copied. Empty = not calibrated |
| `thresholds.act_above` | number in `0..1`. A question fires from this mass (a `noul`) or confidence (a `choice` / `score`) upward. The number has **no effect** until both calibration fields are filled |
| `rules` | object mapping a **question id** (not a rule number) to an action |

An invalid policy (bad `version`, `act_above` outside `0..1`, an action
outside the four, or a required field missing or malformed) exits **1**
with the cause on stderr and does not decide.

The shipped policy has empty `calibration` and empty `rules`. Mapping a
question to an action is the judgment of whoever calibrates. Until then
the engine always returns CONTINUE.

## The four actions

| action | in the order | what the runtime will do (not this engine) |
|---|---|---|
| `CONTINUE` | `action`, empty `question_id`, `value` 0.0 | nothing. The round follows the mechanical path |
| `INJECT_HINT` | plus non-empty `hint` | put that hint where the next attempt will read it |
| `RESET` | plus non-empty `hint` | snapshot, scoped restore, and carry that hint on the scar line of the next attempt's spec |
| `ESCALATE` | plus non-empty `pergunta` and `se` | the existing owner-question path: one `pergunta` and a fork of consequences |

There is no fifth action.

### Fields required per action

- `CONTINUE` — nothing.
- `INJECT_HINT` — `hint` (non-empty text).
- `RESET` — `hint` (non-empty text). That hint is what travels in the
  scar of the next attempt; this engine only copies it into the order.
- `ESCALATE` — `pergunta` (non-empty text) and `se` (a list of **at least
  two** strings, each `se <answer> -> <what you do>`). This is the
  owner-question contract already enforced by the multi-stage runtime
  (`pergunta:` plus at least two `se ... -> ...` lines). A question
  without a fork is ignored there; the policy refuses it here.

`pergunta` and `se` are data. They live in the JSON, not in the engine.

## Precedence

Among questions that **fired**, the strongest action wins:

**ESCALATE > RESET > INJECT_HINT**

If none fired, the decision is `CONTINUE`. `CONTINUE` in `rules` never
competes: it is the default, not a winning action.

When two questions fire with the same action, the higher trigger value
wins; a tie keeps the earlier answer in the record.

## Calibration is measured, not claimed

If `calibration.ring` **or** `calibration.line` is empty, the decision is
`CONTINUE` with reason `not calibrated`. There is no valid threshold
without that evidence. The supervisor reuses the ring loop
(`bin/oracfit-ring.sh` subcommand `score`, which records `owner_score`
and prints a `CALIBRATION` line). This policy does not invent a second
loop and does not parse the line: non-empty ring and line **are** the
evidence.

The shipped `act_above` of `0.8` is a placeholder. It is not a measured
threshold.

## Abstention is a first-class answer

For each question in the answers record that has a rule in the policy,
the engine reads one number:

| answer type | field |
|---|---|
| `noul` | `noul` (the abstention mass) |
| `choice` | `confidence` |
| `score` | `score` |

If that field is missing, the question **does not fire**. That is not an
error. If the value is **below** `thresholds.act_above`, the question
does not fire. Below the threshold the supervisor has **no opinion** and
the round follows the mechanical path. It never guesses to look useful.

A `noul` whose mass is below the threshold does not fire, even when its
rule maps to `ESCALATE`, `RESET`, or `INJECT_HINT`. Precedence then runs
on the questions that remain.

An answer whose question id is not in `rules` changes nothing and is not
an error.

## Decision record

Stdout (and `--out` when given) is a JSON object with **exactly** these
top-level keys:

```json
{
  "decision": "CONTINUE",
  "reason": "not calibrated",
  "order": {
    "action": "CONTINUE",
    "question_id": "",
    "value": 0.0
  }
}
```

| field | meaning |
|---|---|
| `decision` | one of the four actions |
| `reason` | a short phrase for why: `not calibrated`, `no rule fired`, or `<id> fired with confidence 0.91` (or `mass` / `score`) |
| `order.action` | the same action |
| `order.question_id` | the question that fired; empty on CONTINUE |
| `order.value` | the number that fired; `0.0` on CONTINUE |
| `order.hint` | on `INJECT_HINT` and `RESET` |
| `order.pergunta`, `order.se` | on `ESCALATE` |

The record is an **order**, not a verdict. It has no key `verdict`,
`correct`, or `decision_score`. It does not carry "the right answer". It
carries what to do: the hint to inject, or the owner question with its
fork of consequences.

## Runtime

The policy writes the order; the runtime (`bin/lib-oracfit-supervisor.sh`)
is who executes it, at the attempt boundary after the gauntlet feedback.
The attempt boundary is reached only when the oracle failed the previous
attempt, so the supervisor is consulted **after a failure**: a run that
passes on its first attempt ends without any order.
A refused order never fails the run: nothing happens, the reason is on
the event, and the round follows the mechanical path as if the order
were CONTINUE.

| action | what the runtime does |
|---|---|
| `CONTINUE` | nothing. Result `noop` |
| `INJECT_HINT` | append the non-empty `order.hint` to the gauntlet accumulator so the next attempt's spec carries it. Without a hint the order is refused |
| `RESET` | snapshot, scoped restore from HEAD, then the scar plus the hint on the accumulator (see below) |
| `ESCALATE` | write the owner question to the inbox and pause the run (see below) |

### RESET

RESET is executed in this order. The tree does not move until the
evidence is on a ref.

1. **Evidence.** The dirty working tree (tracked edits and untracked
   files) is saved as a commit under `refs/llms-surf/wip/<run>/iter-N`
   before any restore. The snapshot does not move HEAD, the real index,
   or the working tree. If the snapshot cannot be taken, the order is
   refused and nothing happens. The commit sha and the ref name go on
   the summary and the event.
2. **Target.** The tracked paths the attempt changed against HEAD (the
   index, the working tree, and deletions). Protected paths are skipped:
   the same globs the restore already uses (`.oracfit-protected` in the
   workdir when it exists; otherwise the default list, only when the
   workdir is this checkout). Paths under `.dispatch/` are skipped.
3. **Restore.** Those paths are restored from **HEAD** (the last clean
   checkpoint), not from the snapshot ref. A refused restore restores
   nothing; the order is refused and the event says nothing was restored.
4. **Scar.** The scar line (naming the ref) and the order's `hint` go on
   the accumulator, in the same markdown block the gauntlet uses, so the
   next attempt's spec carries both.

RESET does **not** delete a file, does **not** move HEAD, and does
**not** restore a protected path. Untracked files the agent created
stay. Without a non-empty `hint`, or when the snapshot or the restore
cannot be done, the order is refused: nothing happens and the run
continues.

### ESCALATE

ESCALATE is the owner-question path. Nobody in the system knows the
answer; the answer exists only in the owner's head. Burning more
attempts would fill the hole with invention, so this action spends the
attempt in progress and waits.

1. **Validate the fork.** The order needs a non-empty `pergunta` and
   `se` with **at least two** consequences, each `se <answer> -> <what
   you do>` — the same form the multi-stage runtime checks with
   `grep -cE` on a consequence line. Without that, the order is
   refused: nothing is written, the run is not paused, and the round
   follows the mechanical path as if the order were CONTINUE.
2. **Write the question.** The file goes to the workdir inbox as
   `<run_id>.question.md`. It has, in this order: a `pergunta:` line
   with the order's text; the consequences, one per line, as they came
   in the order; and the minimum context the owner needs (run id, mode,
   task, attempt). The library does not invent the question.
3. **Pause the run.** The runtime leaves the attempt loop, records
   status `owner_question` and `oracle_exit` 7, skips the final oracle
   recheck (that recheck runs only on `fail`; it must not flip a run
   that is waiting for the owner), emits `owner_question`, and closes
   the ledger, the usage row, and the final lines with that status.
   Exit is **7**. The paused run is not `pass` and not `fail`.
4. **The owner answers** through `oracfit resume <run_id> "<answer>"`,
   which appends to the inbox queue. The question file is for the owner
   to read; the queue is what the runtime injects into the spec.

ESCALATE does **not** invent the question, does **not** accept a
question without a fork, and does **not** mark the paused run as
`pass`. A refused order never fails the run.

## Pocket rule

**The policy writes the order; the runtime is who executes it.**
