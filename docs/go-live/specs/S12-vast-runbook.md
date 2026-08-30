# S12 — runbook Vast 3090: as lições pagas viram gate executável

Mode: hand or glm_smart, oracle frozen first · **file ceiling: 5 files** ·
Order: LAST of the E2 sequence; usable the day the owner returns the
"sobe" (Vast is SUSPENDED — this story spends $0 and touches no instance).

## Verified data (dados verificados)

- The owner's Vast skill exists with MEASURED cost lessons: mandatory
  cost canary, inet_down_cost watched, zombie instances billing, sick
  hosts, first-minute audit, safe destruction (ESCALADA-2 item 3 and the
  skill referenced there).
- E2-D3 freezes the serving shape: one llama-server per ACTIVE domain,
  never per mode; llamacpp adapter speaks OpenAI-compatible endpoints
  (vast3090 dogfooding precedent 2026-08-27).
- The suspension is an owner decision recorded 2026-08-30 ("nada sobe no
  Vast por enquanto"); zero instances, credit intact.
- Rule 12: network calls carry timeouts; the house treats owner money per
  hour as a ceiling to enforce, not a hope.

Do not invent (nao invente) prices, ceilings, host names, flags or
numbers beyond those listed above (alem destes); every dollar value in
the runbook is [DIAL DO DONO] until he sets it. NUNCA use declare const
or any phantom reference — the preflight reads real env/files or refuses
to bless a launch.

## Work

1. docs/runbook-vast-3090.md (new): the launch/kill discipline as a
   NUMBERED procedure born from the skill's lessons — choose offer
   (inet_down_cost in view), mandatory cost canary before real work,
   first-minute audit, daily ceiling check, zombie sweep, safe destroy.
   Every monetary threshold written as [DIAL DO DONO], none invented.
2. bin/vast-preflight.sh (new, executable): refuses to bless any launch
   plan unless (a) a daily ceiling env/value is set, (b) a canary step is
   present in the plan file, (c) a destroy-by condition is stated. Pure
   local file/env checks — no network, no Vast API call in this story.
3. tests/test-vast-runbook.sh (new): fixture plan files — one complete
   (blessed), one missing the ceiling (refused), one missing the canary
   (refused). No network.
4. Suite counts on the static surfaces; test-site-honesty stays green.

## Do not touch

Vast itself (no API calls, no instances — the suspension stands), the
llamacpp adapter, model-registry.json, LICENSE, public copy (cloud stays
whitelist-gated on both surfaces, decision audited 2026-08-30).

VERIFICACAO: test -d adapters

## Barra

- reference: the incident-grade lessons in the owner's Vast skill (the
  $10.33 class) — the runbook must be those lessons made mechanical, not
  optimism with steps.

## Oraculo

- comando: bash tests/test-vast-runbook.sh && test -x bin/vast-preflight.sh && test -f docs/runbook-vast-3090.md

Exit 0 only after: no launch can be blessed without ceiling, canary and
destroy-by — the three holes the owner already paid to discover.
