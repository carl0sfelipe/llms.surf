# T05 — Malformed inputs

Question: garbage in → typed loud error or a correct chain; **never** a
panic, never a silently wrong chain.

Build once; every case below is a pair of JSON files + a command. Record
exit code, stdout line count, stderr first line. Panic anywhere = FAIL.

## Registry cases

1. `{}` (no `models`) → treated as empty registry.
2. `{"models": null}` → expect parse error exit 3 **or** empty; record
   which (serde default vs null is a design question — note).
3. `models` entries missing `id` → entry has `id: ""`; `tier:cheap` must
   still work; direct request `""` must be `UnknownModel` or usage, never
   a chain with an empty ref.
4. `id_status` as a number (`"id_status": 5`) → exit 3 parse error (typed
   field), not a chain.
5. `fallback` containing non-strings → exit 3.
6. `cli_hints` with nested objects → ignored for aliasing (only string
   values alias), no crash.
7. Duplicate ids with different statuses → document which status wins
   (last write in `status_map`); ensure deterministic across two runs.
8. 0-byte file → exit 3.
9. UTF-8 BOM at file start → record behaviour (serde_json rejects BOM →
   exit 3). Note, not bug, unless the shell tree produces BOMs.

## Catalog cases

10. `models` entry with `keyless: "true"` (string) → exit 3.
11. `context_length: -1` → exit 3 (u64).
12. `context_length: 1e6` (float) → exit 3 unless serde accepts; record.
13. Two entries, same `ref`, different `keyless` → both appear in the
    chain? Python keeps both; Rust keeps both. Confirm parity and flag as
    `gap` (dedup is a candidate law).
14. `ref` containing `\x1f` → `MalformedField`, exit 2, stdout empty.
15. `ref` containing `\n` → same.
16. `provider: ""` (empty string, not null) → treated as unknown provider?
    In Rust `Some("")`: allowlist check fails → `ProviderOutsideAllowlist`.
    Python treats `""` as falsy → no provider. **This is a real
    divergence**: reproduce, report as `bug` or `gap` with the exact
    behaviour of both.

## Allowlist cases

17. `{"providers": []}` → every provider-bearing catalog entry is a
    violation; a keyless entry with `provider: null` still forms a chain.
18. `providers` with duplicates / whitespace variants (`"openrouter "`)
    → whitespace is **not** trimmed; confirm and note.

## Credentials

19. `--credentials` with a provider not in allowlist → irrelevant, no
    effect, no error.
