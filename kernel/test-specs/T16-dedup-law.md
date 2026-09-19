# T16 — Dedup law (45 min)

> Provenance note: the canonical text lives in
> `kernel/test-specs/T11-T20-second-wave.md` (§ "## T16"), which — like the
> rest of the second wave — was never committed on `main`. The body below is
> that section verbatim, committed here so the branch is self-consistent
> (precedent: `T13-law-presence-gate.md`).

Two catalog entries with the same `ref` currently both enter the chain
(Python parity). Decide whether a chain may contain a ref twice. Proposed
law L8: "a chain never contains the same ref twice; the first occurrence
in `catalog_order` wins". Implement, add proptest + vector, add Decisions
row (note the deliberate divergence from Python and why: retrying the
same dead ref twice is the E5 smell). Oracle: green; T03 harness
exclusion list documents the divergence.
