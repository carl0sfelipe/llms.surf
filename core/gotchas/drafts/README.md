# Gotcha drafts

A draft is a triad frame distilled from a finished run's usage report
(`incidents/uso/`). `bin/oracfit-distill.py distill` fills in the
**symptom** from the round's diff — or, when no diff is possible, from a
factual line the report itself supports — and leaves empty everything the
hand still has to write.

The distiller does not promote, does not decide, does not inject, and
does not call a model.

## What a draft does not have

A draft does **not** carry:

- a **trigger** — `trigger.class` is `""` and `trigger.clauses` is `[]`
- a **prescription** — the field is an empty string
- a **fire canary** — `canary.fire_fixture` points at
  `tests/fixtures/gotchas/<id>.fire.json`, but that file is not created

The trigger cannot be invented. The bank spec (`core/gotchas/README.md`)
calls the trigger the falsifiable piece of the triad: a predicate that
must fire on the recorded scar and stay quiet on a healthy run. Inventing
it in the distiller is the defect the format exists to prevent. The
prescription is the human's call about what to do next. The fire fixture
is evidence, not a synthesized file.

The `needs` field names those three holes: `prescription`, `trigger`,
`canary.fire_fixture`. `canary.quiet_fixture` already points at the
shared healthy fixture (`tests/fixtures/gotchas/healthy.json`).

`status` is `draft`.

## Why this folder is not the bank

Drafts live in `core/gotchas/drafts/`. The bank validator
(`python3 bin/oracfit-gotcha.py validate` with no arguments) reads only
`core/gotchas/*.json` — the glob does not descend into a subdirectory. A
draft in this folder therefore does not enter the validated bank, and a
`status` of `draft` does not fail the bank.

The root `core/gotchas/*.json` is the bank. Do not write drafts there.

## Promotion

A draft becomes an active triad by hand:

1. Write `trigger.class` and `trigger.clauses` (the falsifiable
   predicate).
2. Write `prescription` (what to do when the trigger closes).
3. Create the fire fixture at `canary.fire_fixture` from real evidence.
   Keep `canary.quiet_fixture` on the shared healthy fixture.
4. Set `status` to `active` (take the draft status off) and move the
   file to `core/gotchas/<id>.json`.
5. `python3 bin/oracfit-gotcha.py validate` then requires both canaries:
   the trigger must fire on the fire fixture and must not fire on the
   quiet fixture.
