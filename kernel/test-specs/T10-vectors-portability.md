# T10 — Vectors portability (Bend-lab readiness)

Question: is `kernel/vectors/p1/cases.json` a real cross-implementation
contract, or does it lean on Rust/serde details? Prove it by writing an
independent consumer in Python that passes all 13 cases using **only the
statements in `kernel/laws/P1.md` and the vectors**, without reading
`src/lib.rs`.

## Steps

1. Read `kernel/laws/P1.md`, `docs/research/specs/P1-dispatch-policy-rust.md`
   and `cases.json`. **Do not open `src/lib.rs`** until step 5.
2. Write `/tmp/t10/p1.py`: `resolve(request, registry, catalog, allowlist,
   credentials) -> ("ok", entries, skipped) | ("error", variant)` for the
   cheap route; for `mid/expensive/vision` and direct ids, implement from
   the spec text only.
3. Write `/tmp/t10/run_vectors.py` that loads `cases.json`, applies
   overrides (`catalog: null` = absent; absent key = fixture), runs your
   `resolve`, compares to `expect`.
4. Record which cases pass **before** reading the Rust. Every failing case
   is a portability finding: either the vector encodes an unstated rule
   (then the rule must be added to `P1.md` or the spec — `gap`), or the
   vector is wrong (`bug`).
5. Now read `src/lib.rs`; list every rule you had to infer from code that
   was not in the docs. Those are the sentences the Bend lab would also
   have to guess.
6. Schema check of the vectors file: every case has `name`, `incident`,
   `request`, `credentials`, `expect`; `expect` is exactly one of
   `{ok:{entries,skipped}}` or `{error:<variant>}`; every variant named
   exists in the `PolicyError` list in `P1-dispatch-policy-rust.md`
   (or the crate). Write the JSON-schema you infer to
   `/tmp/t10/cases.schema.json` and attach it.
7. Propose ≤ 5 additional vectors that would have caught the rules from
   step 5, in the same JSON shape (do not add them to the repo; put them
   in the report).

## Oracle

PASS = 13/13 after step 5 with all inferred rules listed; the report's
step-4 number (pass count before reading code) is the portability score.
Score < 10 → `gap` on the docs, not on the vectors.
