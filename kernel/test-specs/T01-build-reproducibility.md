# T01 — Build & reproducibility

Question: does `kernel/dispatch-policy` build clean, warning-free, with a
locked dependency set, and produce the same binary twice?

## Steps

1. `cd kernel && cargo build --release 2>&1 | tee /tmp/t01-build1.log`.
   Oracle: exit 0; `grep -c warning /tmp/t01-build1.log` = 0.
2. `cargo clippy --release --all-targets -- -D warnings`. Oracle: exit 0.
   If clippy is not installed: `rustup component add clippy` first; if
   that is impossible, mark this step BLOCKED (not FAIL).
3. `cargo fmt --check`. Oracle: exit 0.
4. Dependency audit: `cargo tree --edges normal | tee /tmp/t01-tree.txt`.
   Oracle: runtime deps are exactly `serde`, `serde_json` and their
   transitive closure; **no** `proptest` in the normal edges.
5. Offline rebuild: `cargo clean && cargo build --release --offline`.
   Oracle: exit 0 (lockfile is complete).
6. Reproducibility: `sha256sum target/release/dispatch-policy` →
   `cargo clean && cargo build --release` → `sha256sum` again. Oracle:
   identical hashes. If different, record whether
   `strip`/`--remap-path-prefix` would fix it (note, not bug).
7. Binary facts: `ls -l target/release/dispatch-policy`; `ldd` output.
   Oracle: dynamic deps limited to libc/libgcc/libm (no OpenSSL etc.).

## Report extras

Rust toolchain version (`rustc -V`), OS, build wall-clock for step 1.
