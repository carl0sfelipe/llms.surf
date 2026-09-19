# T13 — Law presence gate (`kernel/scripts/check-laws.sh`)

> Provenance note: this file is the spec written down after the fact. The
> battery README's second-wave section references `T11-T20-second-wave.md`,
> which (like `T13-*.md` itself) was never committed on `main` or on any
> `p1-*` branch. The text below is reconstructed 1:1 from the dispatch
> prompt that the runner executed, so the branch is self-consistent.

Question it answers: is every law id written in `kernel/laws/*.md`
actually anchored by a mechanism that exists — and is every design
divergence recorded where the laws live?

Budget: inherited wave-2 default (30–45 min); spec file itself was
missing, so the budget was the dispatch prompt's scope only.

## Artifact (permanent, by design)

`kernel/scripts/check-laws.sh` — presence-only gate, executable, no
dependencies beyond grep/find, cwd-independent. For every
`kernel/laws/*.md`:

1. every law id matching `\bL[0-9]+[a-z]?\b` written in the file must
   appear literally (case-sensitive) in `kernel/dispatch-policy/tests/`
   or `kernel/vectors/` — exactly the CI check promised by P1.md
   "Rule for this directory" ("presence-only, like the AGENTS.md grep in
   bestmodel S25c — content honesty stays human");
2. the file must carry a `## Decisions` heading (README rule 1: design
   divergences get a Decisions row, not spoken prose).

Exit 0 green; exit 1 red with one `FAIL:` line per violation.

## Oracle (mechanical, temporary, never committed)

- Gate must be **red** on pristine `main` (this proves both checks bite).
- Gate must be **green** after the run's promotions.
- Gate must go **red** again on a fake law id (`L99`) appended to P1.md,
  then return to green once the fake is discarded. The fake is a drill
  artifact only and must never be committed.
- `cd kernel && cargo test --release` exits 0 on the branch (battery-wide
  oracle).

## Non-goals

- No semantic check of whether a tagged mechanism bites (T06's job).
- No CI wiring: P1.md reserves that for P2 ("CI check (to add with P2)").
- No `src/` edits.
