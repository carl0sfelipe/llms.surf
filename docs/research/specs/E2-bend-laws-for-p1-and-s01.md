# E2 — Bend 2: state real laws (P1 kernel, passphrase-helper S01), see what closes

Purpose: measure how much of *our* invariants BendTT can state and prove,
with a cheap-model author and a sub-second judge. Requires E1 steps 3–4
PASS. Owner: ZCode. Budget: two afternoons.

## Part A — P1 in Bend against the shared vectors

Playground: `~/bend/llms-kernel/`. **Not** inside the llms.surf tree until
the direction's D6 gate says so.

1. Port the data model (`CatalogModel`, `RegistryModel`, `ChainEntry`,
   `PolicyError`) and `resolve` for the **cheap route only** (the other
   routes are a port of legacy heuristics, not laws).
2. Load `kernel/vectors/p1/cases.json` (copy it; the file is the contract)
   and run all `tier:cheap` cases. Record pass/fail per case.
3. Write `LAWS.bend` mirroring `kernel/laws/P1.md` L2–L7 as universally
   quantified statements. L1 (wire format) is Rust/shell-specific — skip.
4. For each law: let the cheap tier write `PROOF.bend`; record attempts,
   time, whether it closed. If a law cannot be **stated** in BendTT
   (affinity, missing stdlib), record *why* — that is the finding.

Table to fill (`~/bend/llms-kernel/E2A-RESULTS.md`):

| Law | Statable? | Proof closed? | Attempts (cheap) | Attempts (expensive) | Check time | Notes |

## Part B — passphrase-helper S01 laws

Playground: `~/bend/pph/`. From
`~/Projects/passphrase-helper/specs/S01-checksum-recuperacao-cartao.md`:

| Law | Statement |
|---|---|
| S01-L1 | `decode(encode(indices)) == indices` for all index vectors of length N over [0, 7775] |
| S01-L2 | Changing exactly one word changes the check word, or the checksum fails — quantify honestly: state it as "for all single substitutions, `verify` returns false **or** the substitution collides"; then measure the collision rate empirically as a separate number |
| S01-L3 | The generator's rejection sampling never yields an index outside [0, 7775] |
| S01-L4 | Recovery with one `?` returns a list that contains the true word |

SHA-256 in Bend: **do not** hand-roll for the proof leg. Model the hash as
an opaque function with the one property the laws need (determinism);
prove the laws relative to it. Note in results that this is proof modulo
the hash — the same honesty caveat the product copy must carry.

## Acceptance

- Both results tables filled; every "no" has a reason.
- Zero Bend code in `llms.surf/` or `passphrase-helper/` trees.
- One paragraph in each results file: "would I trust this over
  `proptest`/`kani` for this pillar today? why?"

## What this decides (feeds direction D6 and research §6 E5)

- Ratio of laws statable in BendTT → how much of the kernel can ever be
  "proof-backed".
- Cheap vs expensive proof-closure → the shape of the 1 %/99 % split for
  proofs (H-Bend-1).
- If Part A closes L2–L7 with cheap models, schedule E5 (10 tasks,
  ledger-measured). If not, Bend stays a judge, not an author, and the
  Rust kernel remains the product.
