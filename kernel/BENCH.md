# BENCH — kernel numbers

One row per measured run: date, machine, what was measured, result.
Numbers are from worktrees on this repo; absolute values are machine-
specific — compare only before/after on the same machine.

| Date | Machine | What | Result |
|---|---|---|---|
| 2026-09-19 | linux 7.1.9-arch1-2, x86_64, rustc release profile | `cargo test --release --test laws`, default 256 cases x 6 properties | 0.02–0.03 s test binary wall (~20 % of runs red: see T02, L3) |
| 2026-09-19 | linux 7.1.9-arch1-2, x86_64, rustc release profile | `PROPTEST_CASES=5000 cargo test --release --test laws` (30 000 property executions) | red (L3); 0.39–0.41 s test binary wall, ~0.46–0.48 s incl. cargo harness, 3/3 runs |
| 2026-09-19 | linux 7.1.9-arch1-2, x86_64 | cold `cargo test --release` build of the workspace (deps + 2 test binaries) | 12.6 s compile |
