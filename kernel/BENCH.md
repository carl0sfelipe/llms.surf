# BENCH — permanent build/perf numbers

One row per measurement: date, machine, subject/size → number.
Feeding rule: every perf/build finding from `kernel/test-specs/` lands
here (README rule 1).

| Date | Machine | Subject | Size | Result |
|---|---|---|---|---|
| 2026-09-19 | Omarchy (Arch), Linux 7.1.9-arch1-2, x86_64, 28 cores, 32 GB RAM, rustc 1.98.1 | cold `cargo build --release` (kernel workspace) | 9 normal deps (serde + serde_json closure) | 6.6 s wall, 0 warnings (T01) |
| 2026-09-19 | same | `cargo clean && cargo build --release --offline` | — | exit 0, 6.6 s wall; lockfile complete (T01) |
| 2026-09-19 | same | `target/release/dispatch-policy` | 774,504 B | sha256 `681be081…cf3e23` identical across 3 builds (online ×2, offline ×1); dynamic deps: linux-vdso, libgcc_s, libc only; RSS: n/a (GNU time not installed) (T01) |
