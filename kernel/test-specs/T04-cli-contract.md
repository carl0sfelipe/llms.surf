# T04 — CLI contract

Question: does the binary honour exit codes, wire format and argument
handling exactly as `docs/research/specs/P1-dispatch-policy-rust.md` and
`src/main.rs` doc comment state?

Fixtures: use `kernel/vectors/p1/cases.json` `fixtures.*` written to
`/tmp/t04/{registry,catalog,allowlist}.json`.

## Checks (each: command → expected → observed)

1. No args → usage on stderr, exit 2, **nothing on stdout**.
2. `resolve` without `--registry` → usage, exit 2.
3. `--registry /nonexistent` → `ERROR: cannot read registry`, exit 3.
4. `--registry` pointing at invalid JSON → `ERROR: cannot parse`, exit 3.
5. `--allowlist` missing → usage, exit 2 (it is required).
6. `--catalog /nonexistent` with `tier:cheap` → `WARN ... tratado como
   ausente` on stderr, then `✖ rota free sem catálogo`, exit 2.
7. `--catalog` with `"kind": "something-else/1"` → WARN kind + exit 2.
8. Happy path `tier:cheap --credentials openrouter`: stdout has exactly 4
   lines; each line has exactly 3 US (`\x1f`) separators
   (`awk -F'\x1f' '{print NF}'` = 4 for all); last field ∈ {0,1}; no
   trailing spaces; ends with `\n`.
9. Same with `--format json`: valid JSON (`python3 -m json.tool`), keys
   `chain.request`, `chain.entries[]`, `skipped[]`; entry keys exactly
   `ref,id_status,provider,keyless`.
10. `--credentials " openrouter , ,opencode "` (spaces, empty items) →
    same result as `openrouter,opencode`.
11. Unknown flag `--foo x` → usage, exit 2.
12. Flag without value at the end (`--credentials`) → usage, exit 2, no
    panic.
13. stderr never contains `panicked at` in any of the above.
14. stdout is empty on every non-zero exit (a consumer piping stdout must
    never get a partial chain).

## Report extras

A table of the 14 checks with observed exit code and first stderr line.

## Verified data (dados verificados)

The model MAY use only: this spec, the kernel/ tree (sources, tests,
laws, vectors, Cargo.lock), kernel/test-specs/oracle.sh, the local
toolchain, and command output produced during the run. Não invente
número, prazo ou fonte além dos listados — do not invent numbers,
deadlines, or sources beyond those listed here.

NUNCA use declare const como workaround — importe de verdade (never
stub an import or fabricate a symbol).

VERIFICACAO: grep -m1 '^## Verdict:' kernel/test-specs/reports/T04.md

## Oráculo

- comando: bash kernel/test-specs/oracle.sh T04
- exit esperado: 0 (report em kernel/test-specs/reports/T04.md com
  primeiro '## Verdict:' PASS, FAIL ou BLOCKED — FAIL/BLOCKED exige
  '## Promoted' não-vazio — e 'cd kernel && cargo test --release' exit 0).
