# T06 — Mutation: do the laws bite?

Question: if the kernel is deliberately broken in the ways the incidents
describe, does at least one shipped test go red? A mutation that survives
all tests is a `gap` finding (the law exists on paper only).

Work on a scratch copy (`cp -r kernel /tmp/t06-kernel`); never commit.
For each mutation: apply, `cargo test --release 2>&1 | grep 'test result'`,
record **which** test(s) failed (name), revert.

| # | Mutation (in `src/lib.rs`) | Incident it re-creates | Expected killer |
|---|---|---|---|
| M1 | `render_us`: use `'\t'` instead of `US` | e82f008 | `l1_us_wire_roundtrip` or `l1b` |
| M2 | `Chain::new`: remove the `contains(US)` check | e82f008 | `l1b_delimiters_are_rejected` |
| M3 | `is_dead`: return `false` always | E5-M2 | vectors + `l2_l4_l5_l6_cheap_gates` |
| M4 | `is_dead`: match only `FANTASMA` | E5-M2 | same |
| M5 | `catalog_order`: drop the `!m.keyless` key | E5-M4/R1 | `l3_cheap_order`, vectors |
| M6 | `catalog_order`: sort context ascending | R1 | same |
| M7 | `catalog_order`: remove the `ref` tiebreak | determinism | `l3_cheap_order` (determinism half) — verify it actually catches it; if not, `gap` |
| M8 | `cheap_chain`: skip credential gate (`if false && !m.keyless`) | E5-M5 | `l2_l4_l5_l6_cheap_gates`, vector `cheap_zero_key_only` |
| M9 | `cheap_chain`: credential gate reads `std::env::var(p)` as a fallback | E5-M5 (env leak) | **expect survival** — no test can see env. Report as designed gap; propose the mechanism (a test that sets env and asserts no effect). |
| M10 | `cheap_chain`: allowlist violation → `continue` instead of `Err` | R4 | `l5_outside_allowlist_is_a_violation`, vector |
| M11 | `cheap_chain`: when `catalog` is `None`, return a chain with `deepseek-v4-flash-free` | E5 (dead default) | `l6_no_catalog_never_defaults`, vector |
| M12 | `Chain::new`: allow empty entries | L6 | vectors `*_is_loud`; check whether any law catches it independently |
| M13 | `cheap_chain`: reverse `entries` before building the chain | L7 | subsequence assertion in `l2_l4_l5_l6_cheap_gates` |
| M14 | `single_tier`: return provider `Some("1")` when meta is missing | e82f008 literal | vector `expensive_outside_catalog_typed_unknown_provider` |
| M15 | `direct`: drop fallbacks | direct path | vector `direct_id_with_fallback_and_statuses` |

## Oracle

PASS if ≥ 13 of 15 mutations are killed and the survivors are exactly the
ones marked "expect survival" or explained as gaps with a proposed test.
Any mutation that survives **and** corresponds to a law in `P1.md` is a
`bug` in the test suite (severity high).

## Report extras

Matrix mutation → killer test names → verdict. Total wall-clock.
