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

## Pocket rule

**The policy writes the order; the runtime is who executes it.**
