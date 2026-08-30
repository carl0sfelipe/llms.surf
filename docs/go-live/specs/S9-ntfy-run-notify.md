# S9 — o grito da praia: aviso no celular quando o run termina ou pergunta

Mode: hand or glm_smart under ring discipline, oracle frozen first ·
**file ceiling: 5 files** · Order: AFTER go-live/residuals-s8 merges.

## Why (measured, not vibes)

2026-08-29: the implementer finished in 13 minutes; the owner, away with
his kid, found out ~2 hours later. Dead wall-clock: ~1h47 for 13 min of
work. The binding constraint of the product is now OWNER ATTENTION LATENCY,
not tokens — and S8 sharpens it: a run paused on owner_question at minute 2
waits silently until someone looks. Today the only phone surface is pull
(the authenticated cloudflared panel link); nothing pushes.

## Decisions already made by the owner (do not relitigate)

- Channel: ntfy.sh — one curl, no account, phone app. Chosen 2026-08-29.
- WhatsApp is VETOED as a dependency: the owner measured repeated failures
  with the nhermes bridge. Do not add any WhatsApp path.
- The ntfy topic name is a bearer secret: lives in env
  (ORACFIT_NTFY_TOPIC), never in YAML, never in git, never echoed to logs.

## Verified data (dados verificados)

- bin/lib-oracfit-events.sh is the single funnel every dispatch event goes
  through (oracfit_emit_event), and neither go-live branch touches it —
  conflict-free hook point.
- Terminal states that matter: run_finished (status pass/fail) and, after
  the residuals-s8 merge, owner_question (run paused, exit 7) plus
  run_finished status=owner_question.
- grep for ntfy/telegram/notify/push in bin/ found no existing push
  mechanism (2026-08-29); the pull surface is oracfit gui --remote.
- Rule 12: every network call carries a timeout. Rule 13: the notify call
  must never be chained into validation or commit paths — it is advisory.

Do not invent (nao invente) flags, env names, endpoints or numbers beyond
those listed above (alem destes); undecidable items are [TO DECIDE], never
guessed. NUNCA use declare const or any phantom reference — the mechanism
is a file on disk that the oracle can run.

## Work

1. bin/oracfit-notify.sh (new, executable): reads ORACFIT_NTFY_TOPIC —
   unset means silent no-op exit 0 (feature is opt-in; no site claim until
   real). Set means: curl -m 5 -s POST of a TERSE body to
   ${ORACFIT_NTFY_URL:-https://ntfy.sh}/$ORACFIT_NTFY_TOPIC, always
   || true — a notify failure never changes any exit code.
2. Hook in bin/lib-oracfit-events.sh: when the emitted event type is
   run_finished or owner_question, call oracfit-notify.sh best-effort with
   run_id, task and status ONLY. Never send the question body, spec text or
   paths — workdir content does not leave the machine; the owner opens the
   panel to read details.
3. tests/test-notify.sh (new): no external network — override
   ORACFIT_NTFY_URL to a local one-shot python3 http.server on 127.0.0.1
   that records the POST; assert (a) unset topic sends nothing, (b) a
   run_finished emit produces exactly one terse POST with run_id and
   status, (c) curl failure (server down) leaves the caller exit code
   untouched.
4. Counts: suite total +1 on the three static surfaces;
   tests/test-site-honesty.sh stays green.

## Do not touch

Dispatch scripts (dispatch-mode.sh, dispatch-stages.sh), gauntlet lib,
mode YAMLs, LICENSE, model-registry.json — the hook lives in the events
funnel only.

VERIFICACAO: grep -q oracfit_emit_event bin/lib-oracfit-events.sh

## Barra

- reference: the 2026-08-29 attention-latency measurement above and the S8
  pause contract (docs/go-live/specs/S8-owner-question.md) — S9 is what
  makes that pause usable by a human who is not staring at the terminal.

## Oraculo

- comando: bash tests/test-notify.sh && grep -q ORACFIT_NTFY_TOPIC bin/oracfit-notify.sh && grep -q oracfit-notify bin/lib-oracfit-events.sh && bash tests/test-site-honesty.sh

Exit 0 only after: opt-in push works against a local fake server, secrets
stay in env, terse body only, and a dead ntfy never hurts a run.
