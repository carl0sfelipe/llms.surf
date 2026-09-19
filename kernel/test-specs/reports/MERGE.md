# MERGE — `p1-integrate` + incidents 1–3 onto `main` (D-MERGE-APPROVE)

## Verdict: PASS

Receipt for the merge sequence in `kernel/test-specs/DECISIONS-merge-inc3-t18.md`
§D-MERGE-APPROVE. Work landed on branch `integrate/p1-to-main` (no direct
push to `main`).

## Evidence

Base: `origin/main` @ `ab9f10f`.

| Step | Command | Result |
|---|---|---|
| 1 | `git merge --no-ff origin/p1-integrate` (`8e5d4b6`) | merge commit `89621d8` |
| 2 | `git merge --no-ff origin/p1-inc-1` (`9b67a32`) | merge commit `973f072` |
| 3 | `git merge --no-ff origin/p1-inc-2` (`30d88d9`) | merge commit `86751a1` |
| 4 | `git merge --no-ff origin/p1-inc-3` (`c3bbba1`) | merge commit `ecf4305` |

`kernel/test-specs/T11-T20-second-wave.md`: no textual conflict. Blob
`b54589e` is identical on `main` (`1e69908`), `p1-integrate`, and the
merge result — main's copy kept, as required.

### Oracle 1 — `cd kernel && cargo test --release`

```
CARGO_EXIT=0
```

Three consecutive runs after the fixture-path pin below: all exit 0.
Release suite: `env_isolation` 1 ok; `laws` 14 ok; `vectors` 1 ok
(37 cases). rustc 1.98.1 (workspace rustup stable). rustc 1.83.0 cannot
parse edition2024 transitive deps (`getrandom`); not used.

First run on the merged tree (shared `p1-t04-{pid}-*.json` fixtures) was
red: `cli_unknown_format_value_falls_back_to_us` (empty vs US wire) and,
on a retry, `cli_catalog_absence_vs_corruption_split` (exit 3 vs 2). Both
pass in isolation. Cause: parallel CLI tests truncated the same temp
registry/catalog mid-read. Not a kernel `src/` change.

### Oracle 2 — `kernel/scripts/check-laws.sh`

```
check-laws: green (1 file(s) scanned, ids present, Decisions headings in place)
LAWS_EXIT=0
```

`cargo fmt --all -- --check` exit 0; `cargo clippy -p dispatch-policy --release -- -D warnings` exit 0 (D-QUALITY, already on `p1-integrate`).

## Findings

1. **gap / test isolation (T04 CLI fixtures).** `cli_fixture` used
   `p1-t04-{pid}-{name}` so every CLI test in the `laws` binary shared
   one registry/catalog file. A truncate-then-write race made a sibling
   `Command` read empty/partial JSON → exit 3. Promoted below.

## Promoted

- `kernel/dispatch-policy/tests/laws.rs`: `cli_fixture` paths unique per
  call (`p1-t04-{pid}-{n}-{name}`); unreadable-dir catalog unique per
  call. `src/**` untouched.

`README.md`, `site/app.js`, `site/llms.txt`: incident count 111 → 114
(three promoted D-DISPATCH files). `bin/check-docs.sh` and
`tests/test-site-honesty.sh` require the copy to match the tree.

## Out of scope (by D-MERGE-APPROVE)

- T18 / T19 / T20 (next, one PR each).
- D-INC3 measure + overlay|restore (next PR; zcode binary not in this
  cloud — do not invent the measurement).
- Re-running O1–O4 of `reports/D-MERGE.md` (already green on
  `p1-integrate` @ `8e5d4b6`).
