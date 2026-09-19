# T02 — Do the shipped tests test what they claim?

Question: are `tests/vectors.rs` and `tests/laws.rs` honest — do they
exercise the claims in `kernel/laws/P1.md`, and would they fail if the
expectation were wrong?

## Steps

1. `cd kernel && cargo test --release -- --nocapture 2>&1 | tee /tmp/t02.log`.
   Oracle: all green; record counts per test binary.
2. Vector self-check (tamper the **expectation**, not the code): copy
   `kernel/vectors/p1/cases.json` to `/tmp/cases.bak`; edit one expected
   `keyless` from `true` to `false` in `cheap_zero_key_only`; run
   `cargo test --release --test vectors`. Oracle: **FAIL** naming that
   case. Restore the file. Repeat once for an `expect.error` variant
   (change `CatalogMissing` to `NoLiveRef`). Oracle: FAIL.
3. Vector coverage: for each `PolicyError` variant in `src/lib.rs`, grep
   `cases.json` for a case expecting it. Oracle: every variant except
   `MalformedField` has a vector (MalformedField is covered by L1b in
   laws). List any missing.
4. Law coverage: for each `L\d` row in `kernel/laws/P1.md`, confirm the
   named test function exists in `tests/laws.rs` and the named vectors
   exist in `cases.json`. Oracle: 100 %.
5. Proptest volume: run laws with `PROPTEST_CASES=5000 cargo test
   --release --test laws`. Oracle: green; record wall-clock.
6. Shrinking sanity: set `PROPTEST_CASES=2000` and confirm no test is
   trivially vacuous — for `l2_l4_l5_l6_cheap_gates`, add **temporary**
   instrumentation in a scratch copy (`/tmp`) counting how many generated
   inputs reach the `Ok` branch vs each `Err` branch. Oracle: each branch
   is hit ≥ 5 % of runs. If a branch is < 1 %, that is a `gap` finding
   (the generator is not exercising the law).

## Report extras

Table: test name → what it asserts (one line) → your judgement
(`honest | weak | vacuous`).
