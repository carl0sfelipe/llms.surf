# P1 — dispatch policy kernel in Rust (as built 2026-09-19 + integration story)

Status: **crate built and green** (`kernel/dispatch-policy`); integration
into the shell is the open story below. Direction:
`docs/research/direction-kernel-rust-bend-lab-2026-09-19.md` D1–D4.

## What exists (verified)

- `kernel/dispatch-policy/src/lib.rs` — pure `resolve(request, Inputs) ->
  Result<Resolution, PolicyError>`; no I/O. `tier:cheap` (catalog route),
  `tier:mid|expensive|vision` (registry-first + stamped defaults, ported),
  direct id / `cli_hints` alias with `fallback` list.
- `src/main.rs` — CLI; exit 0 / 2 (policy) / 3 (unreadable input); wire
  format US-delimited identical to what `run-with-fallback.sh` consumes;
  `--format json` for humans and the ledger.
- `kernel/vectors/p1/cases.json` — 13 shared conformance vectors, each
  tied to an incident. **Shared with the Bend lab.**
- `kernel/laws/P1.md` — L1–L7 with mechanisms; `tests/laws.rs` (proptest).
- Differential: `resolve tier:cheap` on the real `model-registry.json` +
  `data/free-catalog.json` with `--credentials openrouter` = byte-identical
  ref list to `lib-oracfit-mode-loader.py resolve-tier` (11 refs).

Build/test: `cd kernel && cargo test --release` (≈3 s after first build).

## Integration story (ZCode) — precondition, not schedule

Goal: `run-with-fallback.sh` calls the binary instead of the embedded
Python for the `tier:*` branch; behaviour unchanged; laws now guard prod.

1. Build the binary in CI and in `check-saude` (`cargo build --release`
   in `kernel/`; cache target). Absent binary = loud exit 3, never
   fallback to the Python path silently (that would be the E5 class).
2. In `run-with-fallback.sh`, the `tier:*` branch becomes:
   `CHAIN_META=$(dispatch-policy resolve "$MODEL" --registry "$REGISTRY"
   --catalog "$CATALOG" --allowlist data/free-provider-allowlist.json
   --credentials "$(free_cred_providers_csv)")` — where
   `free_cred_providers_csv` is a new tiny function in
   `lib-free-credentials.sh` that prints the providers with file
   credentials (the lib stays the single reader; the kernel never opens
   auth files — L4).
3. The loop that consumed `CHAIN_META` stays as is (same US format). Delete
   the inline Python.
4. Add to `bin/test-free-path.sh` a leg that runs both (Python
   `resolve-tier` and the binary) and diffs — keep for one release, then
   delete `resolve_tier` from the Python loader (the `mode validate` part
   of the loader stays until P4).
5. Ledger: no schema change; optionally record `policy_version` =
  crate version in the run entry (one field, additive).

Acceptance: `bin/test-free-path.sh` 13/13 + the new diff leg PASS;
`cargo test` green; `check-saude` 20/20; a dispatch `tier:cheap` with no
`auth.json` still reaches the keyless leg (vector `cheap_zero_key_only`
reproduced live).

Out of scope: adapters, TUI, `mode validate`, P2–P4.
