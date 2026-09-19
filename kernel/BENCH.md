# BENCH — permanent perf/build numbers for kernel P1

One row per measured number: date, machine, subject, result. Keep units in
the cell.

| Date | Machine | Subject | Result |
|---|---|---|---|
| 2026-09-19 | linux 7.1.9-arch1-2 x64, cargo 1.98.1, 16-way build | dispatch-policy `cargo test --release`, cold (7 tests: 6 laws + 1 vectors) | 11.7 s wall (build dominates), suite itself 0.02 s + 0.00 s |
| 2026-09-19 | same | dispatch-policy `cargo test --release`, warm re-run (src/lib.rs touched) | ~4.0 s wall per run (16 consecutive runs in T06 battery, 65.1 s total) |
| 2026-09-19 | same | T06 mutation battery: 16 mutations of `src/lib.rs`, all tests per mutation | 13/15 spec mutations killed (M12 counted once, both variants survived; M9 survives by design) |
