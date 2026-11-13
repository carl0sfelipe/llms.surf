# Gotcha triads

A gotcha is the unit of memory a supervisor can act on: a **trigger**, a
**symptom**, and a **prescription**. An incident in `incidents/` is prose.
Prose does not fire. A predicate does.

One JSON file per gotcha, at `core/gotchas/<id>.json`.

```json
{
  "id": "2026-07-26-spec-sem-clausula-anti-invencao-gera-num",
  "title": "spec sem clausula anti-invencao gera numero inventado no output",
  "source_incident": "incidents/2026-07-26-spec-sem-clausula-anti-invencao-gera-num.md",
  "symptom": "<prosa copiada do incidente>",
  "prescription": "<prosa copiada do incidente>",
  "trigger": {
    "class": "deterministic",
    "clauses": [
      { "kind": "oracle_exit", "value": 1 },
      { "kind": "behavior_flag", "value": "B2" },
      { "kind": "stderr_pattern", "pattern": "<fonte de regex>", "path_glob": "<glob>" }
    ]
  },
  "canary": {
    "fire_fixture": "tests/fixtures/gotchas/<id>.fire.jsonl",
    "quiet_fixture": "tests/fixtures/gotchas/healthy.jsonl"
  },
  "status": "active"
}
```

`id` is the `id` of the source incident's frontmatter. `source_incident` is
the path as given to the compiler.

## The trigger is written by hand

`bin/oracfit-gotcha.py compile <incident.md>` copies `symptom` and
`prescription` from the incident (each truncated at 1200 characters, original
text preserved) and **leaves the trigger empty**: `trigger.class` is `""`,
`trigger.clauses` is `[]`, `status` is `draft`. It points `canary` at
`tests/fixtures/gotchas/<id>.fire.jsonl` and at the shared quiet fixture
`tests/fixtures/gotchas/healthy.jsonl` without creating either file.

Inventing the predicate in the compiler is the defect this format exists to
prevent. After compile, a human writes `trigger.clauses`, sets
`trigger.class`, points the canary at real evidence, and flips `status` to
`active`.

## `trigger.class`

This is the most important decision in the file.

| class | What the conjunction means |
|---|---|
| `deterministic` | the conjunction **is** the decision: when it closes, the supervisor acts at the attempt boundary and L1 and L2 are not called (short-circuit at L0) |
| `diffuse` | the conjunction only **names** candidates; L1 filters the bank and L2 arbitrates before any action |

A gotcha that proves recurrent under the same signature is promoted from
`diffuse` to `deterministic` — rule 16 applied to the supervisor. Promotion
is a one-line edit; the trigger stays a conjunction of exact predicates.

## `trigger.clauses` — conjunction

Every clause must hold (logical AND). Each clause has a `kind`:

| kind | Fields | Meaning |
|---|---|---|
| `oracle_exit` | `value` (integer) | oracle exit code. Known codes: 0 ok, 1 error, 2 rate-limit, 3 usage error, 4 quota, 6 workdir blocked (lock refused), 7 `owner_question` |
| `behavior_flag` | `value` | a flag id from `bin/oracfit-behavior-scan.py`: `B1` restore-loop, `B2` identical failing tool_call ≥ 3, `B3` write without validation, `B4` biggest_gap empty ≥ 2, `B5` stuck gap (overlap ≥ 0.7), `B6` gauntlet log > 5 MB, `B7` pass without artifact write, `B8` ≥ 3 consecutive transport failures |
| `stderr_pattern` | `pattern`, `path_glob` | regex searched in files whose path matches `path_glob` |
| `text_pattern` | `pattern`, `path_glob` | the same, over workdir file contents |
| `events_pattern` | `pattern`, `path_glob` | the regex is searched in the text of each line of `.jsonl` event files that match `path_glob` |

Globs match a path relative to the workdir root, with the same fnmatch bash
`case` uses (`*` crosses `/`).

On a file target (`match`, and the canary check inside `validate`), only
regex kinds can be satisfied. `oracle_exit` and `behavior_flag` cannot be
read from a file and are treated as not satisfied.

## Canary contract

Both files are required and both must exist.

- `canary.fire_fixture` — proof the trigger still fires: the trigger **must**
  match this fixture.
- `canary.quiet_fixture` — proof it does not fire on a healthy run: the
  trigger **must not** match this fixture. Shared path:
  `tests/fixtures/gotchas/healthy.jsonl`.

A canary is evidence. Do not synthesize a fire fixture for a real incident.
The compiler only writes the path.

## `status`

- `active` — passes `validate`
- `draft` — does not pass (`compile` emits this)

## Commands

```
python3 bin/oracfit-gotcha.py compile <incident.md> [--out file]
python3 bin/oracfit-gotcha.py validate [file...]
python3 bin/oracfit-gotcha.py match <target>
```

`validate` with no arguments checks every `core/gotchas/*.json`. Exit 0 when
every file is ok, 1 when any failed, 2 on usage error. `match` prints each
matching `id`, or `no match`; it exits 1 only on usage error.
