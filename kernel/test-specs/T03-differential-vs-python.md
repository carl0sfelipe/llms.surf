# T03 — Differential vs the Python it replaces (generated inputs)

Question: for **arbitrary** registries/catalogs, does
`dispatch-policy resolve tier:cheap` produce the same ordered ref list
(after the same gates) as `bin/lib-oracfit-mode-loader.py resolve-tier`
combined with the credential gate in `bin/run-with-fallback.sh`?

Scope: `tier:cheap` only (that is the law-bearing route). Reference
behaviour = Python `_resolve_tier_cheap` (order + dead-id gate) followed by
the shell's rule "skip non-keyless entries whose provider is not in the
credential set". The shell reads credentials from files; here you pass the
set explicitly, so implement the reference gate in your harness exactly
as `run-with-fallback.sh` lines ~80–90 do.

## Steps

1. Write `/tmp/t03/harness.py` (outside the repo) that, with a fixed seed:
   - generates a catalog of 0–40 entries: refs from a pool of 60 strings
     (allow duplicates and empty `ref`), `provider` ∈ {opencode,
     openrouter, null}, `keyless` bool, `context_length` ∈ {null, 0, 1,
     4096, 262144, 1_000_000, ties on purpose};
   - generates a registry that stamps a random subset of those refs with
     `id_status` ∈ {EXISTE, PROVAVEL, FANTASMA, NAO-ENCONTRADO,
     NAO-VERIFICADO, "", missing key};
   - picks a credential set ⊆ {opencode, openrouter};
   - writes both JSON files, runs Python `resolve-tier` (capture stdout
     refs + exit code) and applies the reference credential gate; runs the
     Rust binary with `--credentials` and parses field 1 of the US output
     + exit code; compares.
2. Run 2 000 iterations. Oracle: 0 mismatches in (exit code class,
   ordered ref list). Exit-code mapping: Python 2 ≙ Rust 2; Python 0 with
   empty-after-gate in the shell ≙ Rust 2 (`EmptyAfterCredentialGate`).
3. **Expected known difference (not a bug, verify it):** a catalog entry
   whose `provider` is outside `{opencode, openrouter}` → Python skips or
   includes it; Rust exits 2 `ProviderOutsideAllowlist` (law L5, stricter
   by decision). Exclude such providers from the generator in step 2 and
   run a **separate** 200-iteration batch that includes `paidcorp` to
   confirm Rust always exits 2 and Python never does. Report both.
4. Empty-`ref` entries: Python `_catalog_order` drops them
   (`if m.get("ref")`), Rust `catalog_order` drops them. Confirm on 50
   targeted cases.
5. Save every mismatching input pair under `/tmp/t03/mismatch-<n>/` and
   attach the smallest one to the report verbatim.

## Report extras

Iterations, mismatches, the minimized reproducer if any, harness path.

## Verified data (dados verificados)

The model MAY use only: this spec, the kernel/ tree (sources, tests,
laws, vectors, Cargo.lock), kernel/test-specs/oracle.sh, the local
toolchain, and command output produced during the run. Não invente
número, prazo ou fonte além dos listados — do not invent numbers,
deadlines, or sources beyond those listed here.

NUNCA use declare const como workaround — importe de verdade (never
stub an import or fabricate a symbol).

VERIFICACAO: grep -m1 '^## Verdict:' kernel/test-specs/reports/T03.md

## Oráculo

- comando: bash kernel/test-specs/oracle.sh T03
- exit esperado: 0 (report em kernel/test-specs/reports/T03.md com
  primeiro '## Verdict:' PASS, FAIL ou BLOCKED — FAIL/BLOCKED exige
  '## Promoted' não-vazio — e 'cd kernel && cargo test --release' exit 0).
