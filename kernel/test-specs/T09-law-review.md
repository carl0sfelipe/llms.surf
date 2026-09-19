# T09 — Law review (read-only, no execution required)

Question: for each law in `kernel/laws/P1.md`, does the **statement**
match the **mechanism**, and does the mechanism match the **incident**?
This is the review a proof checker would do mechanically; here a reader
does it and writes down the gaps.

Read, in this order: `kernel/laws/P1.md`, `src/lib.rs`, `tests/laws.rs`,
`tests/vectors.rs`, `kernel/vectors/p1/cases.json`, then the incident
sources: `git show e82f008`, `bin/run-with-fallback.sh` lines 28–95,
`bin/lib-oracfit-mode-loader.py` `_catalog_order`/`_resolve_tier_cheap`,
`docs/go-live/DECISIONS-E6-FABLE-FECHAMENTO.md` (M2, M4, M5, M6/R4).

## For each law L1–L7 answer

1. **Statement precise?** Is it a universally quantified property with a
   clear domain? Rewrite it if not (propose text).
2. **Mechanism sufficient?** Does the named test actually force the
   statement, or a weaker one? Examples to look for: generators that
   cannot produce the violating case; assertions inside a branch that
   might never execute; `prop_assert` on a derived value instead of the
   output.
3. **Incident closed?** Would the original incident's input make this
   test red on the pre-fix code? If you cannot argue it, say so.
4. **Type or test?** Could this law be a type instead of a test (e.g.
   `provider: Option<String>` already makes "provider = '1'" harder but
   not impossible — `Some("1")` still type-checks). Propose the newtype if
   cheap.

## Also review

5. `PolicyError::ProviderOutsideAllowlist` is stricter than Python
   (violation vs pass-through). Is the decision recorded where an
   operator will find it when dispatch suddenly exits 2 after a catalog
   sync? (Check `P1.md`, the CLI message, the spec.) If not, `gap`.
6. `direct()` sets `keyless: true` for every entry. Is that a lie the
   wire format tells the shell? What would a consumer conclude? Propose
   either a tri-state or a documented "not applicable".
7. `single_tier_id` port: list every branch of the Python that the Rust
   does **not** replicate (e.g. the Python's dead `tier == "cheap"` block
   inside the `models` branch) and every branch the Rust adds.
8. Candidate laws in `P1.md` "Not laws (yet)": for each, write the
   statement and the cheapest mechanism.

## Report

One section per law with the four answers, then the three review items,
then a ranked list of proposed changes (`must | should | could`).
