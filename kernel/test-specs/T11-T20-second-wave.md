# Second wave — T11–T20

Every spec here produces a mechanism or a decision in the tree, not a
report about one. Same common rules as README (worktree, branch
`p1-<ID>`, dispatched through llms.surf, report + `## Promoted`).

## T11 — Promote the first wave (60 min)

Input: branches `p1-T01` … `p1-T10`. Merge their promoted artifacts into
one branch `p1-wave1`: union of new vectors (dedupe by `name`), law/test
changes, `P1.md` Decisions rows, `BENCH.md` rows. Oracle: `cargo test
--release` green on `p1-wave1`; every report's `## Promoted` path exists
in the branch; a table in the report: finding → artifact → spec id.
Anything a report claimed but did not produce is listed as `unpromoted`
and the spec id is flagged — that is the metric of whether the first wave
was honest.

## T12 — CI for the kernel (30 min)

Add `.github/workflows/kernel.yml`: `cargo fmt --check`, `clippy -D
warnings`, `cargo test --release`, `PROPTEST_CASES=2000` on `laws`, and
the law-presence check from T13. Runs on push to any branch touching
`kernel/**`. Oracle: workflow file validates (`actionlint` if available),
and a deliberate red (temporary bad vector in a scratch branch) fails the
job. Artifact: the workflow + one line in `check-saude.sh` that runs
`cargo test` when the kernel dir exists.

## T13 — Law-presence gate (30 min)

`kernel/scripts/check-laws.sh`: for each `L\d+` id in every
`kernel/laws/*.md`, require it to appear in `kernel/*/tests/**` or
`kernel/vectors/**`; exit 1 listing missing ids. Also require every
`kernel/laws/*.md` to have a `## Decisions` heading (presence-only, like
bestmodel S25c). Oracle: passes on HEAD; fails when a fake `L99` row is
added. Wire into T12 and `check-saude`.

## T14 — Decide `provider: ""` (30 min)

Today Rust treats `Some("")` as a provider outside the allowlist
(violation) while Python treats `""` as no provider. Decide: normalize
empty string to `None` at parse time (recommended — matches every
producer in the tree; write it as a serde `deserialize_with`), record the
decision in `P1.md` **Decisions**, add vector `T14_empty_provider_is_none`,
and confirm T03's harness (if promoted) no longer flags it. Oracle:
vector green; T05 §16 case now passes.

## T15 — Credential-gate tri-state on the wire (45 min)

`keyless: true` on the direct-id path is not what it says. Change the
wire field to a tri-state the shell can ignore safely: keep `1|0` for
tier routes; emit `-` for "gate not applicable" on direct ids; update
`parse_us`, vectors `direct_*`, law L1 generator, and one line in
`P1-dispatch-policy-rust.md` integration step 3 ("the loop treats `-` as
`1`"). Oracle: all tests green; `run-with-fallback.sh`'s existing
`[ "$KEYLESS" != "1" ]` check still passes `-` through the gate (verify by
reading — the shell is not modified here).

## T16 — Dedup law (45 min)

Two catalog entries with the same `ref` currently both enter the chain
(Python parity). Decide whether a chain may contain a ref twice. Proposed
law L8: "a chain never contains the same ref twice; the first occurrence
in `catalog_order` wins". Implement, add proptest + vector, add Decisions
row (note the deliberate divergence from Python and why: retrying the
same dead ref twice is the E5 smell). Oracle: green; T03 harness
exclusion list documents the divergence.

## T17 — Environment isolation mechanism (30 min)

M9 in T06 survives because no test observes the environment. Add
`tests/env_isolation.rs`: set `OPENROUTER_API_KEY`, `OPENCODE_TOKEN`,
`HOME`, `PATH` to poison values, run `resolve` with an empty credential
set, assert every non-keyless entry is skipped (L4 holds regardless of
env). Then re-apply M9 on a scratch copy and confirm the new test kills
it. Oracle: mutation killed; test in tree.

## T18 — Shadow mode in the shell (60 min)

Implement integration step 1–3 of `P1-dispatch-policy-rust.md` **behind a
flag**: `LLMS_KERNEL=shadow` runs both the Python path and the binary,
diffs the US output, logs `kernel_shadow_diff=<0|1>` to the ledger entry,
and keeps serving the Python result. `LLMS_KERNEL=on` serves the binary.
Default unchanged. Add a `test-free-path.sh` leg that runs one dispatch in
shadow and asserts diff=0. Oracle: 13/13 + new leg PASS; `check-saude`
20/20. This is the first day the laws watch production traffic.

## T19 — `policy_version` in the ledger (20 min)

Additive field: the ledger entry records the kernel crate version and the
git sha of `kernel/` when `LLMS_KERNEL` is `shadow|on`. Oracle: a run in
shadow mode shows the field; a run with the flag off shows no field; the
ledger schema test (if one exists) is updated, not weakened.

## T20 — The battery as a llms.surf mode (45 min)

`core/modes/kernel_test.yaml` (schema v1, validated by `mode validate`):
stage `run` on `tier:cheap` with the spec file as input, then a
mechanical stage `command: kernel/test-specs/oracle.sh <ID>` implementing
the README oracle (report exists, verdict line, promoted non-empty or
PASS, `cargo test` green on the branch), `max_attempts: 3`, gauntlet off.
Oracle: `mode validate` passes; dispatching T01 through it produces a
ledger entry with `provider_efetivo`, attempts and the oracle exit. From
here on the battery is a product feature (run it on every kernel change)
and every run is an E5 data point.

## Why these ten

T11–T13 turn wave 1 into gates. T14–T17 turn the known gaps into laws.
T18–T19 put the laws in front of real traffic without a cutover. T20
makes the whole thing a mode of the product it protects. None of them
produces only a report.
