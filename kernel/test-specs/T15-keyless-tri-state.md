# T15 — Credential-gate tri-state on the wire

> Provenance note: the canonical spec text lives (untracked) in the
> owner tree at `kernel/test-specs/T11-T20-second-wave.md`, section
> "## T15" (precedent: T12/T13, same untracked second-wave file). The
> section below is that text committed verbatim, so the branch is
> self-consistent.

## T15 — Credential-gate tri-state on the wire (45 min)

`keyless: true` on the direct-id path is not what it says. Change the
wire field to a tri-state the shell can ignore safely: keep `1|0` for
tier routes; emit `-` for "gate not applicable" on direct ids; update
`parse_us`, vectors `direct_*`, law L1 generator, and one line in
`P1-dispatch-policy-rust.md` integration step 3 ("the loop treats `-` as
`1`"). Oracle: all tests green; `run-with-fallback.sh`'s existing
`[ "$KEYLESS" != "1" ]` check still passes `-` through the gate (verify by
reading — the shell is not modified here).

