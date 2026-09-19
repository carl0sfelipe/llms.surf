# D-MERGE — integration of waves 1–2 into `p1-integrate`

## Verdict: PASS

All six D-MERGE steps applied in the fixed order, `cargo test --release`
green after each, and all four final oracles green. No open decision
point: every judgement call traced back to an explicit clause of
`kernel/test-specs/DECISIONS-wave1-2.md` (see Findings for the trace).

Final SHA of `p1-integrate` at report time: the commit carrying this
file (parent `77c0ff0`; branch based on `main` @ `87a12a1`, the commit
on top of the announced `f4650ab` — one docs-only research commit, no
kernel content; noted, not acted on).

## Evidence

### O1 — `PROPTEST_CASES=5000` on 3 seeds — GREEN

Mechanism: proptest reads the environment variable `PROPTEST_RNG_SEED`
(u64). Three seeds, full suite per seed:

```
seed=0x1234567890abcdef cargo_exit=0   laws: 14 passed; vectors: 1 passed (37 cases)
seed=0xdeadbeefcafebabe cargo_exit=0   laws: 14 passed; vectors: 1 passed
seed=42                 cargo_exit=0   laws: 14 passed (0.43–0.50 s); vectors: 1 passed
```

(≈ 70 000 property executions per run across the 8 proptest laws plus the
unit/CLI/vector suites; the historical L3 red at 5000 cases is gone.)

### O2 — `kernel/scripts/check-laws.sh` on the integrated tree — GREEN

```
$ ./kernel/scripts/check-laws.sh
check-laws: green (1 file(s) scanned, ids present, Decisions headings in place)
O2_EXIT=0
```

T13's gate passes with L8 (and L1–L8, L1b/L1c) present; P1.md carries the
required `## Decisions` heading (one table, one row per D-* plus the
promoted per-task decisions).

### O3 — T06's 15 mutations re-applied on a scratch copy — 15/15 KILLED

Scratch copy outside the repo (`/tmp/t06-verify`, `CARGO_TARGET_DIR`
local, pristine baseline green, `cargo test --release` per mutant,
kill = suite red). Counting as T06 counts: M12 counted once, both
variants killed → 15/15 spec mutations killed.

```
M1  KILLED ['cli_happy_path_wire_and_formats', 'l1_us_wire_roundtrip']   (render_us tab)
M2  KILLED ['l1b_delimiters_are_rejected']                              (drop US check)
M3  KILLED ['cli_happy_path_wire_and_formats', 'l2_l4_l5_l6_cheap_gates'] (is_dead false)
M4  KILLED ['l2_l4_l5_l6_cheap_gates']                                  (is_dead FANTASMA-only)
M5  KILLED ['l3_cheap_order']                                           (drop !keyless)
M6  KILLED ['l3_cheap_order']                                           (ctx ascending)
M7  KILLED ['l3_cheap_order']                                           (drop ref tiebreak)
M8  KILLED ['l4_holds_regardless_of_env']                               (skip credential gate)
M9  KILLED ['l4_holds_regardless_of_env']                               (env fallback) — killed by T17/T06 mechanisms as decided
M10 KILLED ['l5_outside_allowlist_is_a_violation']                      (violation → continue)
M11 KILLED ['cli_catalog_absence_vs_corruption_split', 'l6_no_catalog_never_defaults'] (default chain)
M12 KILLED ['l6_chain_new_rejects_empty']; KILLED ['l6_chain_new_rejects_empty'] (a: empty ref; b: empty vec)
M13 KILLED ['l2_l4_l5_l6_cheap_gates']                                  (reverse entries)
M14 KILLED ['all_p1_vectors_conform']                                   (provider Some("1"))
M15 KILLED ['all_p1_vectors_conform']                                   (drop fallbacks)
SPEC MUTATIONS KILLED: 15/15
```

### O4 — T03 harness, 2000-iteration main batch + paidcorp + emptyref — GREEN

`/tmp/t03/harness.py` (unmodified) against the integrated binary
`/tmp/p1-integrate/kernel/target/release/dispatch-policy`, reference
Python from the live tree:

```
[main]     iterations=2000 mismatches=1272
[paidcorp] iterations=200  mismatches=2
[emptyref] iterations=50   mismatches=26
TOTAL_MISMATCHES=1300
```

Classification of all 1300 mismatches against the documented exclusion
classes (input- and output-level, scripted):

- duplicate-ref (D-L3): **1300** — every mismatch catalog contains ≥1 ref
  occurring more than once; in every `Ok` mismatch the reference keeps N
  occurrences / gates by last-wins while Rust emits each ref once. Across
  all 2250 iterations there is **zero** `Ok` case in which `rust_refs` is
  not unique (L8 holds everywhere).
- corrupted-catalog exit (D-EXIT): **0** — the harness never generates an
  unreadable/invalid-JSON/wrong-kind catalog (nothing to exclude).
- paidcorp: **0 outside the duplicate-ref class** — the 2 paidcorp-batch
  mismatches are L8 interactions (the forced paidcorp occurrence was
  deduped away by a better-ranked duplicate of its ref).

**Zero mismatches outside the documented exclusion classes.**

### Per-step gates

`cargo test --release` was run green after every step (only documented
exception: immediately after step 2 the suite carried wave 1's own
promoted red, `l3_cheap_order`, 12 passed / 1 failed — resolved by
D-L3/T16 in step 3 as the fixed order prescribes; recorded in the merge
commit message).

### Final quality gates on the integrated tree

`cargo fmt --check` exit 0 · `cargo clippy --release --all-targets -- -D
warnings` exit 0 · `cargo test --release` exit 0 (6/6 targets ok).

## Findings

1. **Branch base** — the instruction said `main @ f4650ab`, but `main`
   had moved to `87a12a1` (one docs-only research commit adding
   `docs/research/…` and an E2 spec; no kernel content). The literal
   command (`git worktree add … -b p1-integrate main`) was followed;
   the branch therefore contains that docs commit. No action needed on
   merge to main.
2. **Step 2 green-gate deviation (documented, per DECISIONS)** — the
   wave-1 merge commit carries a deliberately red suite: T11 promoted
   `l3_cheap_order` red as its own evidence ("owner decision pending"),
   and D-MERGE's fixed order puts the fix (T16+D-L3) one step later.
   The DECISIONS doc itself notes the input as "oracle red on L3"; the
   next-step green gate is satisfied from step 3 onward.
3. **D-L3 mechanism location** — implemented literally: the dedup lives
   in `catalog_order` (sort by key, then dedupe by `ref` keeping the
   first = best-ranked; full sort-key ties keep the file-order first via
   the stable sort). Consequence, recorded in the L8 law row: later
   occurrences never reach the L2/L4/L5 gate loop, so the
   `SkipReason::DuplicateRef` channel T16 built is superseded on the
   cheap route and no skip is reported for them (the guard stays in
   `cheap_chain` as defence in depth, and the direct-path fallback
   collapse is unchanged). Vectors that pinned the reported-skip or
   both-legs behaviour were re-pinned (list below).
4. **Regressions seeds not carried** — wave 1 had committed two
   `l3_cheap_order` seeds and T12 added a third
   (`laws.proptest-regressions`). All three pin the *falsified*
   file-order determinism claim and predate the restated law's strategy;
   per D-L3 and P1.md's own rule ("never commit it while the law it pins
   is still failing") the file is deliberately absent from the
   integration. The full-tie input class stays pinned at vector level by
   the re-pinned `T02_l3_duplicate_ref_ties_keep_file_order`.
5. **Re-pinned vectors (name → motive)** —
   - `T05_empty_provider_is_allowlist_violation` → T14 (D-PROVIDER):
     `provider: ""` normalizes to `None` at parse; the entry now resolves
     `Ok` with `provider: null` instead of `ProviderOutsideAllowlist`.
     (Surfaced late: T14's own suite run was masked by the laws-target
     failure ordering, so it landed inside the T16 commit.)
   - `T02_l3_duplicate_ref_ties_keep_file_order` → L8/D-L3: only the
     best-ranked (here file-order-first, `provider: null`) occurrence
     enters; `skipped: []`.
   - `T03_duplicate_ref_gate_is_per_occurrence` → L8/D-L3: selection is
     per-ref; the opencode occurrence is deduped before the gate loop;
     `skipped: []` (entries unchanged).
   - `T03_duplicate_ref_shell_exit2_rust_still_ok` → L8/D-L3 (D-L3.2):
     Rust expectation stands (shell exits 2, Rust keeps the keyless
     occurrence); `skipped: []`.
   - `T05_duplicate_ref_keeps_both_legs` → L8/D-L3: name pins the
     superseded parity behaviour; only the best-ranked (keyless) leg
     enters.
   - `T16_duplicate_ref_first_occurrence_wins` → D-L3: entries unchanged
     (first occurrence wins); the `DuplicateRef` skip is not reported
     because the dedup moved into `catalog_order`.
   - `direct_id_with_fallback_and_statuses`, `direct_cli_hint_resolves_to_id`
     → T15/D-WIRE: `keyless: null` (wire `-`, gate not applicable).
   - `T05_cli_hints_non_string_ignored` → T15/D-WIRE: same; this vector
     did not exist on T15's pre-wave1 base and was caught by the union.
6. **T10's five proposed vectors — mechanical `name`+`expect` dedupe** —
   - ADDED: `T10_skip_order_is_catalog_order`,
     `T10_vision_registry_first_gemini`,
     `T10_expensive_prefers_id_containing_pro`,
     `T10_tier_id_in_catalog_takes_catalog_meta`.
   - SKIPPED: `T10_dead_entry_shields_outside_allowlist` — its
     `expect` (`{"error":"NoLiveRef"}`) equals three existing pins and it
     is semantically identical to `T03_dead_id_gate_precedes_allowlist`
     (same property, same input class: single dead ref citing paidcorp).
   - Promotion note: `T10_skip_order_is_catalog_order`'s registry
     override was extended with the two statuses its verified expectation
     depends on (`mimo-v2.5-free`/EXISTE, `ghost-model:free`/FANTASMA) —
     the cases.json `registry` override *replaces* the fixture registry
     rather than merging.
7. **T02 F3 closed** — error-class distribution recorded as a `note` row
   in `BENCH.md` (numbers, no action), per "Unpromoted items — closed".
8. **T12 artifacts reconciled** — `kernel.yml` gates unchanged; its
   "known state at birth: RED" header comment gained an integration note
   (resolved green same day). T12's three `laws.proptest-regressions`
   seeds were not carried (Finding 4); T12's Decisions rows were folded
   into P1.md's single Decisions table with the stale premise amended;
   its law-presence self-skip guard dissolved as designed (T13 landed).
9. **M7 oracle hardening (test-only)** — the first O3 run had M7 (drop
   the `ref` tiebreak) surviving: `dup_ref_catalog` gave every entry a
   globally distinct `context_length`, so different refs never tied and
   the tiebreak was unobservable. The generator now derives ctx as the
   per-ref occurrence index (same-ref occurrences still never tie on the
   full key — D-L3's set-function property is untouched), which makes the
   strictly-increasing-key assertion bite on the tiebreak. No src/ change;
   suite green before/after.
10. **Trivial formatting note** — `cargo fmt` (D-QUALITY) reformatted
    `src/` and `tests/` (wave-1 evidence: 38 hunks), and one cases.json
    block is stored expanded where earlier style was inline; JSON
    semantics unchanged.

## Promoted

- `kernel/test-specs/T11-T20-second-wave.md`,
  `kernel/test-specs/T13-law-presence-gate.md` — second-wave specs,
  verbatim from p1-T12 / p1-T13 (step 1).
- Merge of `p1-wave1` (b297ddd): T01–T10 artifacts, 37→31 vectors at that
  point, BENCH.md, reports T01–T11 (step 2).
- T14 (85f79c3), T16 (20c3961) + D-L3 restatement, T15 (5b9dc96 + 9c6ad4d),
  T17 (002371e), D-L1c, D-EXIT applied in order with re-pins (step 3);
  Unpromoted items closed (T02 F3 → BENCH note; T10 vectors landed/skipped).
- D-QUALITY: `cargo fmt` + clippy `#[derive(Default)]` fix (step 4).
- T12: `.github/workflows/kernel.yml`, `bin/check-saude.sh` kernel line,
  reports (step 5); T13: `kernel/scripts/check-laws.sh` + L7 mechanism tag.
- `kernel/laws/P1.md`: L1 tri-state mechanism, L3 restated, L8 added,
  Decisions table (single) with per-task rows plus one row per D-* —
  D-L3, D-L6, D-L1c, D-EXIT, D-PROVIDER, D-WIRE, D-ENV, D-SHELL,
  D-QUALITY, D-DISPATCH — dated 2026-09-19 (step 6).
- `kernel/vectors/p1/cases.json`: 37 cases (31 wave-1 + T14 + T16 + 4×T10),
  re-pins as listed in Finding 5/6.

Open decision points not covered by DECISIONS: **none**.
