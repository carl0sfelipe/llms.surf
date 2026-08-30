# S11 — lint do binding tuned/: model_ref fantasma reprova antes do run

Mode: hand or glm_smart, oracle frozen first · **file ceiling: 4 files** ·
Order: FIRST of the E2 sequence — 100% local, $0, lands before the first
tuned/ id ever exists (E2-D5 in docs/go-live/DECISIONS-E2-MODELO-POR-TASK.md).

## Verified data (dados verificados)

- E2-D2 freezes the convention: NO new schema key, NO new tier; a tuned
  model is a registry id shaped tuned/<dominio>-<base>, usable wherever
  model_ref already points at a registry id today.
- bin/lib-oracfit-mode-loader.py is the single validate/lint surface for
  mode YAMLs (S3/S8 precedent: it validates keys, roles, tiers and
  declared mechanisms).
- model-registry.json exists at the repo root.
- The anti-ghost family already exists as rule 45 (extractor/agent schema
  compatibility): a reference that nothing backs is refused before any
  model is called.

Do not invent (nao invente) schema keys, tier names, registry fields or
numbers beyond those listed above (alem destes); anything undecidable is
[TO DECIDE], never guessed. NUNCA use declare const or any phantom
reference — the lint reads the real model-registry.json or fails loud.

## Work

1. bin/lib-oracfit-mode-loader.py: lint gains ONE check — any stage
   model_ref beginning with tuned/ must exist as an id in
   model-registry.json (resolved from --root). Missing registry file with
   a tuned/ ref present = lint fail with a loud message; no tuned/ refs =
   zero behavior change for every existing mode.
2. tests/test-tuned-binding-lint.sh (new): mktemp workdir — a mode YAML
   with a tuned/ ref absent from the registry FAILS lint naming the id; a
   YAML with no tuned/ ref passes untouched; a YAML whose tuned/ ref is
   present in a fixture registry passes.
3. Suite counts on the static surfaces; test-site-honesty stays green.

## Do not touch

The validate() schema (ALLOWED_* sets stay as they are — this is lint,
not schema), core/modes/ shipped YAMLs, model-registry.json entries,
LICENSE, dispatch scripts.

VERIFICACAO: grep -q ALLOWED_STAGE bin/lib-oracfit-mode-loader.py

## Barra

- reference: E2-D2 — provenance lives in the registry, capability in the
  tier; the lint is the only new surface and it only refuses ghosts.

## Oraculo

- comando: bash tests/test-tuned-binding-lint.sh && grep -q "tuned/" bin/lib-oracfit-mode-loader.py

Exit 0 only after: a ghost tuned/ ref cannot reach a runner, and every
mode that exists today lints exactly as before.
