# P1 test battery — one spec per subagent

Target: `kernel/dispatch-policy` @ `2356d0e` or later. Each spec is
self-contained: a subagent gets **one** file, runs it, writes **one**
report to `kernel/test-specs/reports/<spec-id>.md`, and touches nothing
else. Specs are independent; run them in parallel.

Common rules (every subagent):

- Work in a **fresh clone or worktree** of llms.surf; never in the owner's
  live tree. `git worktree add /tmp/p1-<spec-id> HEAD`.
- Do not edit `kernel/dispatch-policy/src/**` unless the spec says so
  (T06 does, and reverts).
- Report format is fixed: `## Verdict: PASS | FAIL | BLOCKED`, then
  `## Evidence` (commands + raw output, trimmed), then `## Findings`
  (numbered; each with severity `bug | gap | note` and the law it touches
  if any). A finding with no reproduction command is a note, not a bug.
- Never "fix" the kernel to make your spec pass. Report.
- Budget per spec is written in the spec. Stop at budget; write BLOCKED.

| Id | Spec | Question it answers | Budget |
|---|---|---|---|
| T01 | `T01-build-reproducibility.md` | Does it build clean, warning-free, offline, twice identically? | 20 min |
| T02 | `T02-vectors-and-laws.md` | Do the shipped tests actually test what they claim? | 30 min |
| T03 | `T03-differential-vs-python.md` | Does the Rust match the Python on **generated** inputs, not just today's file? | 60 min |
| T04 | `T04-cli-contract.md` | Exit codes, wire format, stderr phrasing, argument handling | 30 min |
| T05 | `T05-malformed-inputs.md` | Garbage in → typed loud error, never a chain, never a panic | 40 min |
| T06 | `T06-mutation.md` | If the code is broken on purpose, does a law go red? | 60 min |
| T07 | `T07-adversarial-and-perf.md` | Delimiters, unicode, 100k-entry catalogs, time and memory | 40 min |
| T08 | `T08-shadow-integration.md` | Side by side with `run-with-fallback.sh` on the real tree, no changes | 45 min |
| T09 | `T09-law-review.md` | Read-only: does each law's statement match its mechanism? | 45 min |
| T10 | `T10-vectors-portability.md` | Can a non-Rust consumer (Python) run the vectors identically? (Bend-lab readiness) | 45 min |

Dispatcher prompt (paste to each subagent, replacing `<ID>`):

> Read `kernel/test-specs/README.md` then `kernel/test-specs/<ID>-*.md`.
> Execute only that spec, in a worktree. Write the report to
> `kernel/test-specs/reports/<ID>.md` in the exact format. Do not modify
> the kernel. Do not run other specs.
