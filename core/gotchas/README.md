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
      { "kind": "stderr_pattern", "pattern": "<regex source>", "path_glob": "<glob>" }
    ]
  },
  "canary": {
    "fire_fixture": "tests/fixtures/gotchas/<id>.fire.json",
    "quiet_fixture": "tests/fixtures/gotchas/healthy.json"
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
`tests/fixtures/gotchas/healthy.jsonl` without creating either file. A
triad whose trigger includes `oracle_exit` or `behavior_flag` must point
the fire canary at a signals bundle (`.json`) before it can be `active`.

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

Globs match a path relative to the base directory of that kind, and also
the file name, with the same fnmatch bash `case` uses (`*` crosses `/`).
The glob is decided **before** the file is opened: the walk matches
`path_glob` against the relative path (and the file name) and only then
reads. Unreadable files and files that do not decode as UTF-8 are skipped.
The walk does not descend into a `.git` directory; other hidden directories
such as `.dispatch/` are still walked.

## Signals bundle

`evaluate` (and a `.json` canary) read a JSON object. Signals are taken
from the top level, or from a nested `signals` object when that key holds
an object (other top-level keys are metadata and are ignored).

| field | meaning |
|---|---|
| `oracle_exit` | integer, the round's oracle exit code |
| `behavior_flags` | list of flag ids from `bin/oracfit-behavior-scan.py` |
| `stderr_dir` | directory of oracle logs |
| `text_root` | workdir root (base of `text_pattern`) |
| `events_dir` | directory of event files |

A relative directory is resolved against the current working directory; an
absolute path is used as-is. A missing base directory is not an error: the
clause that needed it stays unsatisfied. Unreadable files are skipped.

`match` still evaluates a **file**. On a file target, only regex kinds can
be satisfied; `oracle_exit` and `behavior_flag` cannot be read from a file
and are treated as not satisfied.

## Canary contract

Both files are required and both must exist. Two fixture forms:

- a path that **ends in `.json`** is a **signals bundle**: the trigger is
  evaluated with the same evaluator `evaluate` uses
- any other path (for example `.jsonl`) is an events/text file: only regex
  clauses can be satisfied, over that file's contents (`match` semantics)

`validate` applies that rule to the fire canary and to the quiet canary.

A triad whose trigger has an `oracle_exit` or `behavior_flag` clause can
only become `active` when the fire canary is a signals bundle (`.json`);
otherwise `validate` reports `canary fixture is not a signals bundle:
<path>`.

- `canary.fire_fixture` — proof the trigger still fires: the trigger **must**
  match this fixture.
- `canary.quiet_fixture` — proof it does not fire on a healthy run: the
  trigger **must not** match this fixture.

Shared quiet fixtures:

- `tests/fixtures/gotchas/healthy.json` — a healthy round (oracle exit 0,
  no flags), for triads with a scalar clause
- `tests/fixtures/gotchas/healthy.jsonl` — a healthy events file, for
  regex-only triads

A canary is evidence. Do not synthesize a fire fixture for a real incident.
The compiler only writes the path.

## `status`

- `active` — passes `validate`; `evaluate` lists the triad when the trigger closes
- `draft` — does not pass (`compile` emits this); `evaluate` never lists it, even when the conjunction would hold

## Commands

```
python3 bin/oracfit-gotcha.py compile <incident.md> [--out file]
python3 bin/oracfit-gotcha.py validate [file...]
python3 bin/oracfit-gotcha.py match <target>
python3 bin/oracfit-gotcha.py evaluate --signals <file> [--bank <dir>]
```

`validate` with no arguments checks every `core/gotchas/*.json`. Exit 0 when
every file is ok, 1 when any failed, 2 on usage error. `match` prints each
matching `id`, or `no match`; it exits 1 only on usage error.

`evaluate` prints one JSON object per **active** triad whose trigger closed, fields
`id`, `class`, `title`, `prescription`, sorted by id. A `draft` triad is not
listed even when the conjunction would hold. When nothing closes it prints
nothing and exits 0. `--bank` defaults to `core/gotchas`. Exit 2 on a usage
error (missing `--signals`, signals file missing or invalid, `--bank` not a
directory).

At the attempt boundary the single-stage runtime evaluates the round and
appends each **active deterministic** triad that closed to the next attempt's
composed spec, through the gauntlet channel. A `diffuse` triad is listed
by `evaluate` and is not injected. A `draft` triad is not listed and is
not injected.
