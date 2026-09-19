# T07 — Adversarial inputs and performance

Question: does the kernel stay correct and bounded on hostile or huge
inputs? P1 sits on the dispatch hot path; it must be negligible.

## Adversarial

1. Refs with unicode (`"ref": "modelo-ção/🙂:free"`), RTL marks, zero-width
   joiners → chain renders and `parse_us` round-trips; ordering is by
   byte order of the `String` (document; compare with Python's `str`
   ordering on the same set — they should agree for UTF-8 codepoint order;
   if they differ on surrogates, note).
2. Refs differing only by case → both kept, order by bytes (`A` < `a`).
   Confirm parity with Python.
3. Very long ref (10 000 chars) → works; wire line is one line.
4. `context_length: 18446744073709551615` (u64::MAX) → parses; ordering
   correct; no overflow (Reverse on u64 is safe — confirm no `as i64`).
5. Deeply nested `cli_hints` (1 000 levels) → serde_json recursion limit
   → exit 3, not a stack overflow crash. Record.
6. 1 000 catalog entries all with the same key tuple → stable output
   across 5 runs (sort must be deterministic given equal keys — the ref
   tiebreak should make ties impossible unless refs are equal; test with
   equal refs too).

## Performance (release binary, `hyperfine` if available, else
`/usr/bin/time -v`, 10 runs each)

7. Real files (`model-registry.json` + `data/free-catalog.json`):
   wall-clock and max RSS. Target: < 5 ms, < 5 MB RSS.
8. Synthetic catalog 10 000 entries, registry 10 000 entries: target
   < 50 ms.
9. Synthetic 100 000 / 100 000: record time and RSS; target < 1 s,
   < 200 MB. Note complexity: `status_map` is a BTreeMap (n log n);
   `single_tier_id` scans linearly per rule (fine); `direct` is linear.
10. Compare 7–8 against the Python path
    (`python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:cheap
    --registry ...`) on the same inputs. Report the ratio; this number
    goes to the direction doc's "Rust for the right reason" claim only if
    measured here.

## Report extras

Table of sizes → ms → RSS for Rust and Python; any non-linear blow-up.
