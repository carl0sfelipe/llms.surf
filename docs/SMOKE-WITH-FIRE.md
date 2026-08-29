# Smoke with fire — after llms.surf v1 public

> **When:** after the official public v1 of this site is live (DNS + this
> `site/` deployed), not before. **Who:** Fable (expensive, meta +
> dogfood), then `llms-surf` dispatching GLM (`core/modes/glm_smart.yaml`)
> for remaining implementation. **Why:** GLM cannot be trusted with the
> S25/S26 shotgun without frozen oracles; Fable cannot spend 25% of a
> plan rewriting Python. This split is the product eating itself.

Nothing in this file is implementation. It is the ring spec.

## Phase A — Fable smokes the live v1 (fire, not screenshot)

Fable, in a new session, against the **deployed** origin (not `file://`):

1. Load `https://llms.surf/` (or the real public host). Fail the ring if
   the hero, oracle-loop, stats strip, wipeout cards, swell table, and
   quickstart are not all reachable.
2. Assert the stats strip numbers still match git HEAD of this repo
   (`tests/test-site-honesty.sh` green on that commit).
3. Click every nav link and the four inner pages. Copy-button copies the
   real clone URL (`carl0sfelipe/llms.surf`).
4. Confirm Swell still reads **no data yet** unless a measured cell was
   deliberately added.
5. Local CLI: `bin/llms-surf start` with the stub runner, then
   `bin/llms-surf gui` — the panel loads. This is the 2-minute promise.
6. Write a short `docs/v1-smoke-log.md`: what broke, what was confusing,
   what a stranger would bounce on. That log is the input to Phase B,
   not a vibe.

A screenshot of the hero is not a smoke. Behavior is.

## Phase B — llms-surf dispatches GLM (the 99%)

Open a ring in the **bestmodel** repo (S25) and, separately, a ring here
for v1.1. Mode: `glm_smart`. Oracle frozen at ring open. Gauntlet on.
Safety ceiling 4.

### B1 — bestmodel S25 (parity & modality-blind gate)

Source of direction: `~/Work/bestmodel/docs/direction-2026-08-29.md`.
GLM does not get to rediscover architecture. It executes:

| story | mechanical oracle (sketch — freeze the real command at ring open) |
|---|---|
| S25a ABC inventory | `rg -n "def fetch_" packages/fake-adapters apps/public-api` plus a new test that introspects `DatabaseSession` and instantiates `PostgresSession`; `make test` includes it and it fails if any abstract method is missing on either backend |
| S25a round-trip | a test writes a video scenario through the session API and reads back `source_class`, `recipe_id`, and video scalars on **both** backends |
| S25b gate video leg | `make gate` log contains a video-mock POST and an assertion that leaderboard row **count increased** and `source_class` is present |
| S25c AGENTS.md | `make gate` (or a tiny grep in it) fails if any of `packages/domain-schema`, `packages/fake-adapters`, `apps/public-api`, `apps/intake-worker`, `cli/benchmark-probe`, `infra/migrations` lacks an `AGENTS.md` containing `Change checklist` |

If GLM cannot make an oracle green, it files an incident and stops. It
does not invent a sixth backend.

### B2 — llms.surf v1.1 from Phase A log

Only items that Phase A actually observed. Candidates (not a wishlist):

- broken link, dead copy-button, stats drift, mobile nav, missing PNG
- README still claiming a number the honesty test would reject
- deploy/DNS leftovers

Oracle: the same `tests/test-site-honesty.sh` plus a curl of the live
host returning 200 on `/`, `/readme`, `/incidents`, `/v4-plan`.

### B3 — bestmodel.run launch leftovers

Only after S25 is green. Not in the first GLM ring. Per-user keys (S23)
and the visual honesty UI (S24) stay on the v2 roadmap. Cloud stays on
hold (direction D4/D7).

## What Fable still owns (do not give to GLM)

- Any new honesty-tier or schema decision (S26).
- License change (proprietary vs Lineup-as-OSS). The site currently
  tells the truth: LICENSE is proprietary. Flipping that is the owner.
- Inventing a Swell price.
- Touching production `bestmodel-prod` or a rented rig.

## Preconditions (not a calendar)

- This `site/` is deployed and reachable on a public host.
- `tests/test-site-honesty.sh` is green on the deployed commit.
- Owner has a GLM/Zhipu path that `glm_smart` can actually call
  (`model_ref: zhipuai/glm-5.2-coding-plan`). If that adapter is dark,
  the ring does not open — we say so, we do not pretend a dispatch.

## Done when

Phase A log exists. S25 oracles green or an incident filed for each
red. Live site still honest. No new invented number on either product.
