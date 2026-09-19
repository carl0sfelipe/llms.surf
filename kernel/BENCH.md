# BENCH — permanent build/perf numbers

One row per measurement: date, machine, subject/size → number.
Feeding rule: every perf/build finding from `kernel/test-specs/` lands
here (README rule 1). Numbers are from worktrees on this repo; absolute
values are machine-specific — compare only before/after on the same
machine.

| Date | Machine | Subject | Size | Result |
|---|---|---|---|---|
| 2026-09-19 | Omarchy (Arch), Linux 7.1.9-arch1-2, x86_64, 28 cores, 32 GB RAM, rustc 1.98.1 | cold `cargo build --release` (kernel workspace) | 9 normal deps (serde + serde_json closure) | 6.6 s wall, 0 warnings (T01) |
| 2026-09-19 | same | `cargo clean && cargo build --release --offline` | — | exit 0, 6.6 s wall; lockfile complete (T01) |
| 2026-09-19 | same | `target/release/dispatch-policy` | 774,504 B | sha256 `681be081…cf3e23` identical across 3 builds (online ×2, offline ×1); dynamic deps: linux-vdso, libgcc_s, libc only; RSS: n/a (GNU time not installed) (T01) |
| 2026-09-19 | same | `cargo test --release --test laws`, default 256 cases x 6 properties | — | 0.02–0.03 s test binary wall (~20 % of runs red: see T02, L3) (T02) |
| 2026-09-19 | same | `PROPTEST_CASES=5000 cargo test --release --test laws` (30 000 property executions) | — | red (L3); 0.39–0.41 s test binary wall, ~0.46–0.48 s incl. cargo harness, 3/3 runs (T02) |
| 2026-09-19 | same | cold `cargo test --release` build of the workspace (deps + 2 test binaries) | — | 12.6 s compile (T02) |
| 2026-09-19 | linux 7.1.9-arch1-2 x64, cargo 1.98.1, 16-way build | dispatch-policy `cargo test --release`, cold (7 tests: 6 laws + 1 vectors) | 11.7 s wall (build dominates), suite itself 0.02 s + 0.00 s |
| 2026-09-19 | same | dispatch-policy `cargo test --release`, warm re-run (src/lib.rs touched) | ~4.0 s wall per run (16 consecutive runs in T06 battery, 65.1 s total) |
| 2026-09-19 | same | T06 mutation battery: 16 mutations of `src/lib.rs`, all tests per mutation | 13/15 spec mutations killed (M12 counted once, both variants survived; M9 survives by design) |
| 2026-09-19 | same | note (T02 F3, closed by D-MERGE per DECISIONS-wave1-2 "Unpromoted items"): outcome distribution of `l2_l4_l5_l6_cheap_gates`, scratch counters at `PROPTEST_CASES=2000`, `--test-threads=1` | 2001 executions | ok 61.2 % (1225) · `NoLiveRef` 36.6 % (733) · `EmptyAfterCredentialGate` 2.2 % (43) · other 0.0 % — numbers, no action |
| 2026-09-19 | Arch Linux 7.1.9-arch1-2, Xeon E5-2680 v4 @ 2.40GHz, 28 threads, 31Gi RAM | `tier:cheap` whole resolution: shell path (`run-with-fallback.sh` CHAIN_META block: python3 spawning a 2nd python3, `lib-oracfit-mode-loader.py`) vs `dispatch-policy` release binary | real `model-registry.json` (26 models) + `data/free-catalog.json` (11 refs), 20 runs each after warmup | shell median 102.2 ms (min 96.6, max 224.1) · binary median 1.1 ms (min 1.0, max 1.5) · ≈91x |
