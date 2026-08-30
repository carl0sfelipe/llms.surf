# Smoke with fire — go-live gate for the integrated MVP

> Rewritten 2026-08-29 (Fable). Supersedes the previous Phase A/B: the old
> file cited a Swell table the site no longer has and pointed Phase B at
> bestmodel S25, which is NOT this go-live. bestmodel S25 direction lives
> in its own repo (`~/Work/bestmodel/docs/direction-2026-08-29.md`) and is
> out of this gate. Nothing in this file is implementation.

## Phase A — go-live checklist (ads may run only when all boxes tick)

Mechanical half first, human half second. A screenshot is not a smoke;
behavior is.

### A1. Local gate (one command)

`tests/test-go-live-local.sh` (spec S6) exits 0. It chains: site honesty,
first wave from a clean copy, TUI zero-question journey, mode init
scaffold, share/add round-trip, and the launch invariants (aliases on the
home, no god modes, no tok/s, no open-source claim, no prices).

### A2. Deployed host (human, against the real origin — not file://)

1. `curl` of the public host returns 200 on `/` and `/llms.txt`, and the
   deployed commit's `tests/test-site-honesty.sh` is green at that HEAD.
2. Fresh clone on a machine that never saw the repo: the 4 quickstart
   lines reach a green oracle in under 2 minutes on a stopwatch, no API
   key. This is the ad promise, measured, not assumed.
3. Three waves on the stub: `run normal` and `run unlock_plan` close green;
   `ui_visual_qa` runs via its script path (`bin/dispatch-vision-ui-qa.sh`)
   on fixture screenshots — if it cannot, the site must not imply it runs
   on the stub (honesty over coverage; the YAML-vs-script debt is known).
4. Custom path end to end: `mode init` → `validate` → `lint` → `run` (stub)
   → `mode share` prints a paste-ready YAML.
5. First scroll = ad: clone command with copy button, three waves, "name
   your break" card. Nothing above the fold that the git tree cannot back.
6. Every nav link and inner page loads; the copy button copies the real
   clone URL.

### A3. Log or it did not happen

Write `docs/v1-smoke-log.md`: what broke, what confused, where a stranger
would bounce. That log is the only input for post-launch fixes — no vibes.

## Phase B — pack residuals (nothing else)

S1–S6: hand-implemented on `go-live/s1-s6` (e9dfc3d), reviewed by Fable,
merged to main (6dc23f1) — Phase A precondition (a) satisfied.

The three residuals (smokes relocated to `tests/fixtures/` with all six
references repointed plus a gate line proving zero live `specs/` refs;
`tests/test-first-wave.sh` virgin-clone proof; `examples/` matching the
card in English with the 2-stage mini-tow) and S8 — the owner-question
contract in `unlock_plan` (`docs/go-live/specs/S8-owner-question.md`, spec
frozen at af00515 before the code) — were implemented on
`go-live/residuals-s8` (b1ff918) and approved by Fable 2026-08-29: local
gate 35/35, owner-question 8/8, first-wave green on the branch.

What remains, under the same oracle discipline (oracle frozen first),
in this order:

1. `docs/go-live/specs/S9-ntfy-run-notify.md` — push on run_finished /
   owner_question via ntfy.sh (opt-in, topic in env, terse body). First
   because it is small and because the measured constraint is owner
   attention latency (2026-08-29: 13 min of work discovered ~2 h later);
   without it the S8 pause is a dead-time trap. WhatsApp vetoed (owner:
   repeated nhermes bridge failures).
2. `docs/go-live/specs/S7-single-flight-status.md` — rule 53 mechanisms
   1–2 (single-flight lock per workdir, `status --task` canonical verdict).
   Urgency UP after S8: a paused-then-resumed run writes TWO run_finished
   lines for one run_id, so a raw grep of events.jsonl now misreads runs
   in exactly the way the 2026-08-27 incident described.

If an oracle cannot go green, file an incident and stop — do not widen
scope. Explicitly NOT in Phase B: bestmodel S25/S23, cloud/Swell anything,
SEO regeneration, LICENSE changes.

## What Fable still owns (do not hand to GLM)

- LICENSE decisions (proprietary vs any OSS cut) — owner + Fable only.
- Any price, SKU or throughput number: it must be measured on the rig and
  recorded in the registry before it may exist anywhere (D6 unlock
  criteria in docs/go-live/DECISIONS-D1-D10.md).
- New honesty tiers or schema extensions to the mode loader.
- Touching `bestmodel-prod`, Vast, or the Paraguay rig.

## Preconditions (not a calendar)

- `site/` deployed and reachable on the public host.
- Owner has a live GLM path for `glm_smart` (`model_ref:
  zhipuai/glm-5.2-coding-plan`); if that adapter is dark the ring does not
  open — we say so, we do not pretend a dispatch.

## Done when

Phase A boxes all tick, the smoke log exists, every S1–S6 oracle is green
(or has a filed incident), and no page, ad or bio claims a number or a
product the git tree cannot back.
