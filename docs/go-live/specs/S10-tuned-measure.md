# S10 — registro e medição before/after de modelo tunado (gate do claim)

Mode: hand or glm_smart, oracle frozen first · **file ceiling: 6 files** ·
Order: after S11 (the lint lands before the first tuned/ id exists).
Purpose: build the MACHINE that makes the word "fine-tune" honest
(E2-D1 in docs/go-live/DECISIONS-E2-MODELO-POR-TASK.md). The real
measurement waits for the owner's GPU ("sobe" suspended); the harness and
its stub proof do not wait.

## Verified data (dados verificados)

- model-registry.json exists at the repo root and the dispatcher's ledger
  records model, estimated cost and oracle result per run (ESCALADA-2,
  "O que já é FATO no tree").
- The llamacpp adapter already talks to an OpenAI-compatible endpoint;
  serving one's own model happened in the 2026-08-27 dogfooding
  (vast3090 precedent, ESCALADA-2).
- E2-D1 freezes the claim gate: registry entry with serving evidence +
  before/after on 5 real task specs (same protocol and seed, both runs in
  the ledger) + this spec's oracle green.
- E2-D2 freezes the id convention: tuned/<dominio>-<base>, provenance in
  the registry via tuned_from and measured_delta fields.
- adapters/stub/runner.sh is the house hook for network-free end-to-end
  tests (S8/S9 precedent).

Do not invent (nao invente) registry fields, adapter flags, metric names
or numbers beyond those listed above (alem destes); anything undecidable
is [TO DECIDE], never guessed. NUNCA use declare const or any phantom
reference — the harness must read the real registry and the real ledger
or halt loud.

## Work

1. bin/tuned-measure.sh (new, executable): takes a base model id, a
   tuned/<dominio>-<base> id and a list of 5 task spec paths; runs each
   spec against BOTH ids under the same protocol and seed; writes a
   report that names the ledger run_ids per side and the per-task
   verdicts; exits non-zero if any run is missing from the ledger.
2. Registry: document (in the registry README section or adjacent doc)
   the tuned entry format — id tuned/<dominio>-<base>, tuned_from,
   measured_delta pointing at the report's run_ids. No entry is created
   by this story: the first real entry is GPU work, after the "sobe".
3. tests/test-tuned-measure.sh (new): stub adapter, mktemp workdir, two
   fake model ids, 5 tiny fixture specs — proves the harness runs both
   sides, refuses a missing ledger entry, and the report names run_ids.
   No network.
4. Suite counts on the static surfaces; test-site-honesty stays green.

## Do not touch

Vast, any GPU endpoint, model-registry.json entries (machinery only),
LICENSE, core/modes/. No public copy change: "fine-tune" stays NEXT until
E2-D1(a)(b)(c) all hold.

VERIFICACAO: test -f model-registry.json

## Barra

- reference: E2-D1 and E2-D4 in docs/go-live/DECISIONS-E2-MODELO-POR-TASK.md
  — dogfood runs ARE the measurement; the harness must make that cheap.

## Oraculo

- comando: bash tests/test-tuned-measure.sh && test -x bin/tuned-measure.sh

Exit 0 only after: the measuring machine is proven on the stub, refuses
unledgered runs, and no public claim moved an inch.
