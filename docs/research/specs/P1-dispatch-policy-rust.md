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
3. The loop that consumed `CHAIN_META` stays as is (same US format); the
   loop treats `-` as `1`. Delete the inline Python. (Wire note, T15/D2:
   tier routes emit `1|0` only; direct ids emit `-` = "gate not
   applicable" — until that rewiring lands, the unchanged
   `[ "$KEYLESS" != "1" ]` check keeps `-` inside the credential gate,
   so the shell can ignore the third value safely.)
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

## Cross-implementation contract (added by T10, 2026-09-19)

T10 wrote a docs-only Python consumer (from `kernel/laws/P1.md`, this doc
and the vectors — never `src/lib.rs`): it passes 13/13 shared vectors, but
only by guessing the rules below, which existed **only in code**. A Bend-lab
implementer would have to guess the same. Each rule was verified against
the built binary; pinning vectors are proposed in
`kernel/test-specs/reports/T10.md` (add to `cases.json` when accepted).

- `PolicyError` variants (this doc previously listed none):
  `CatalogMissing`, `NoLiveRef{request}`, `EmptyAfterCredentialGate{request,
  skipped}`, `ProviderOutsideAllowlist{ref, provider}`, `NoModelForTier{tier}`,
  `UnknownModel{request}`, `MalformedField{field, value}`.
- Registry-first chains for the paid tiers (first hit wins, in order):
  `mid` = id `deepseek-v4-pro` → id `deepseek-v4-flash-openrouter` → first
  paid/free model whose `best_for` contains "raciocínio médio" or "código".
  `expensive` = first paid model whose id contains "frontier" or "pro" →
  id `claude-sonnet-5` → first model with `best_for` "melhor qualidade".
  `vision` = id `gemini-3.6-flash` → first model whose `best_for`/id
  mentions "vision"/"visão". Stamped defaults when the registry yields
  nothing: mid → `deepseek-v4-pro`, expensive → `claude-sonnet-5`,
  vision → `gemini-3.6-flash`, all with `id_status: ""`.
- A tier-route id that IS in the free catalog takes that catalog entry's
  `provider`/`keyless` and passes the credential gate (so the tier route
  can end in `EmptyAfterCredentialGate`); ids absent from the catalog get
  provider `null`, keyless `true`, and no gate. The tier route never
  expands `fallback`.
- `skipped` is one list in `catalog_order` encounter order — not grouped
  by reason, not in file order.
- Per entry the dead gate (L2) runs before the allowlist check: a DEAD id
  citing a provider outside the allowlist is skipped as `DeadId` and never
  raises `ProviderOutsideAllowlist` (L5's "a catalog citing one is a
  violation" bites only for live entries).
- A keyed catalog entry with `provider: null` passes both the allowlist
  check and the credential check (no provider to deny).
- Direct id / `cli_hints` path: no dead gate, no credential gate, no
  allowlist; `fallback` ids are appended in declared order and a fallback
  id missing from the registry still yields an entry (`id_status: ""`,
  provider `null`). `cli_hints` aliases apply only on this path — the
  cheap route matches catalog refs to registry ids exactly. Pinned
  (D-NEXT-6, 2026-09-19) by vectors
  `T10_direct_fallback_absent_from_registry_still_entry`,
  `T10_cheap_route_ignores_cli_hints_alias`,
  `T10_direct_alias_resolves_to_registry_id`.
- `is_dead` is substring containment: a status *containing* `FANTASMA`,
  `NAO-ENCONTRADO` or `NAO-VERIFICADO` is dead, as L2 states.
