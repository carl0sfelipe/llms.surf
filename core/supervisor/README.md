# Supervisor question set

The supervisor answers typed questions. It does not decide. This directory holds
the versioned question set: one question per class-R rule in the rules map
(`fluxos/_comum/mapa-regras.md`). Class R is the set of rules that still need
judgment and have no mechanism today.

The file is `core/supervisor/questions.json`. A later client (rung H) exports it
and POSTs the result to `/v1/systemone`. This rung writes the question; it does
not call a model, does not talk to the network, and does not pick CONTINUE /
INJECT_HINT / RESET / ESCALATE.

A suggestion is an order of tool calls, not a verdict. No question in this set
carries an action, a command, or a patch. The text of each rule stays in the
map; the set names the rule by number.

## Pocket rule

**A question with no incident history is not asked.** `asked` is true only when
`incidents` names at least one postmortem that exists on disk. `asked` is false
when the list is empty; then `withheld_reason` says why the question is
withheld. Export with `--asked-only` drops withheld questions so a client cannot
ask them by accident.

## File format

```json
{
  "version": 1,
  "source": "fluxos/_comum/mapa-regras.md",
  "questions": [
    {
      "id": "r16-recurring-failure-becomes-a-rule",
      "rule": 16,
      "type": "noul",
      "instructions": "Does this trajectory repeat a failure that already happened before and still has no mechanism?",
      "evidence": ["bin/oracfit-behavior-scan.py", "events.jsonl"],
      "cost": {"model_calls": 1, "state": "short"},
      "asked": true,
      "incidents": ["incidents/2026-07-24-travamento-silencioso.md"]
    }
  ]
}
```

| field | meaning |
|---|---|
| `version` | integer version of the set |
| `source` | path of the rules map the set is built from; must exist |
| `questions` | list; exactly one object per class-R rule the map declares |

Each question:

| field | meaning |
|---|---|
| `id` | unique slug `r<n>-<words>`. `<n>` is the rule number, zero-padded when it has a single digit (`r01-...`) |
| `rule` | integer class-R rule number. The rule's prose stays in the map |
| `type` | `noul`, `choice`, or `score` — the System-One types |
| `instructions` | the question, in English, ending in `?`. Not a command |
| `criteria` | required for `choice` and `score`, **absent** for `noul`. `choice`: object with two or more keys (short label → description). `score`: array of two or more strings, the scale in rising order |
| `evidence` | non-empty list of what the question reads (see Signals) |
| `cost` | `model_calls` (integer ≥ 1) and `state` (`short` or `full`). `note` is optional |
| `asked` | boolean |
| `incidents` | paths relative to the repo root of files that exist under `incidents/`. Non-empty when `asked` is true; empty when `asked` is false |
| `withheld_reason` | required when `asked` is false: a non-empty sentence saying why the question is not asked |

The set points at paths. It does not embed the contents of an incident, a log, or
a spec.

## Signals

Each `evidence` item must satisfy at least one of:

1. it contains one of these signal tokens, written exactly:
   `events.jsonl`, `tool_call`, `thinking`, `oracle_exit`, `behavior_flags`,
   `stderr`, `git_diff`, `git_status`, `log_size`, `ledger`, `spec`, `workdir`
2. it names a path that exists in the repository

Those tokens are the compact state L0 already produces: the events stream
(`thinking`, `tool_call`), the behavior scan (`behavior_flags` / B1–B8 in
`bin/oracfit-behavior-scan.py`), the oracle exit, stderr, git diff and status,
log size, the ledger row, the spec, and the workdir. The question set does not
invent a second calibration loop; `bin/oracfit-ring.sh` already records
`owner_score_pred`.

## `short` vs `full`

This is the latency split from the design note (§9), not a quality grade.

| `state` | when | what the model is shown |
|---|---|---|
| `short` | frequent questions at a choke point (pre-flight, attempt boundary, post-loop) | a compact state vector: B-flags, oracle tail, ledger line |
| `full` | rare, heavy questions | the whole trajectory |

A CPU decision model can answer a short-state question in seconds and cannot
re-read a whole trajectory on every attempt. Prefer `short`.

## Validator

```
python3 bin/oracfit-questions.py validate [--set <file>]
```

Default file: `core/supervisor/questions.json`. Exit 0 when the set is ok, 1
when it is not, 3 on a usage error. Each failure is one stdout line
`set: <reason>`.

It checks:

1. the file parses as JSON, `version` is an integer, `source` names a file that exists
2. `questions` is a list, and the set of `rule` values **equals** the set of
   class-R rule numbers the map declares right now (a rule line starts with
   `| <number> |` and has `**R**` in the third field; the class legend does not
   count). Not one question more, not one less
3. every `id` is unique and matches `r<n>-<words>` for that question's `rule`
4. `type` is one of the three types; `criteria` has the shape of the type
5. `instructions` is a non-empty string ending in `?`
6. `evidence` is a non-empty list, and each item is a signal token or an existing path
7. `cost` has `model_calls` integer ≥ 1 and `state` in `short` / `full`
8. `asked` is a boolean; when true, `incidents` has at least one path and every
   path exists on disk; when false, `incidents` is empty and `withheld_reason`
   is a non-empty sentence

A tampered copy in `$TMPDIR` must fail. The suite proves six cuts: empty
evidence, invalid type, `asked` true with a missing incident file, a `rule` not
in the map, duplicate ids, and `criteria` on a `noul`.

## `list` and `export`

```
python3 bin/oracfit-questions.py list [--asked-only]
python3 bin/oracfit-questions.py export [--asked-only] [--ids a,b,c]
```

`list` prints one line per question:

```
<id>  rule=<n>  type=<type>  cost=<model_calls>  state=<short|full>  asked=<true|false>
```

`export` prints the System-One request body, and only that body:

```json
{
  "questions": {
    "<id>": {
      "type": "choice",
      "instructions": "...",
      "criteria": {"a": "...", "b": "..."}
    }
  }
}
```

Each value has exactly `type` and `instructions`, plus `criteria` when the type
has criteria. No `rule`, no `evidence`, no `cost`, no `incidents`. The client
adds `state` (the run's compact state) when it POSTs. Default export includes
every question in the set; `--asked-only` keeps `asked` true; `--ids` keeps the
named ids (an unknown id is a usage error, exit 3).
