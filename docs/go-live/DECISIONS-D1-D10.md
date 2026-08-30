# Go-live decisions — D1–D10

> Fable session, 2026-08-29. Direction + frozen choices for the integrated
> MVP go-live (llms.surf v4 public + bestmodel.run). No implementation here.
> Executor: GLM (`glm_smart`) via the spec pack in `docs/go-live/specs/`.

## Verified facts this session (checked in this tree, nothing invented)

1. **`bin/llms-surf start` is broken at HEAD.** `cmd_first_proof`
   (`bin/oracfit:243-249`) dispatches `${ORACFIT_ROOT}/specs/oracfit-smoke-normal.md`
   and `specs/` does not exist in this public cut (rule 52 declared it
   PRIVATE). Five references point at the missing file: `bin/oracfit:247`,
   `bin/test-oracfit-tldr.sh:20`, `bin/release-gauntlet-verify.sh:72`,
   `tests/test-gui-remote.sh:63`, `tests/test-protected-paths.sh:14`.
   The 2-minute hero promise fails on a fresh clone today. This is P0 (spec S1).
2. The stub runner (`adapters/stub/runner.sh`) writes
   `<workdir>/.dispatch/stub-proof` containing `stub_ok` — that is the
   natural smoke oracle.
3. Custom modes need **zero schema change** for the MVP. The loader
   (`bin/lib-oracfit-mode-loader.py`) already allows: roles
   `unlock|plan|run|map|reduce|export|render|vision_gate`, tiers
   `cheap|mid|expensive|vision`, `command:` for mechanical stages,
   `oracle: true|<string>`, gauntlet block. Both example YAMLs in
   `CUSTOM-MODE-CARD.md` validate against the current loader.
4. `oracfit mode init|validate|lint` work today; the scaffold writes to the
   workdir overlay (`core/modes/<id>.yaml`), which already shadows built-ins.
5. `oracfit modes` lists all 20 YAMLs; the TUI stars 3 (`MODES_RECOMMENDED`).
6. LICENSE is proprietary; `site/llms.txt` says so; the honesty test
   (`tests/test-site-honesty.sh`) mechanically pins site counts to the tree.

---

## D1 — Two products, one go-live

**Decision:** confirm the proposed cut. llms.surf = *do the work* (3 waves +
name-your-break custom). bestmodel.run = *know what fits your machine*. All
paid traffic (Twitter replies/ads, Meta ads) lands on llms.surf. The OSS
magnet is **bestmodel.run, which is already AGPL/MIT** — no LICENSE flip in
this go-live.

**Why:** the magnet already exists and is honest today; flipping llms.surf's
LICENSE is irreversible and blocks nothing in this launch. The one-line
announcement the site can cash on first scroll:

> *Cheap AI models do the work. A mechanical oracle proves it shipped.
> Clone it — 2 minutes, no API key.*

**Owner confirms?** Yes — (a) bestmodel as the OSS magnet vs. flipping a
"Lineup" subset of the dispatcher (recommend bestmodel; flip stays available
later), (b) the one-line promise wording.

## D2 — Public names for the 3 defaults

**Decision:** keep tree ids (`normal`, `unlock_plan`, `ui_visual_qa`);
add surf **aliases in UI/site copy only**, always shown as `alias (id)`:

| id | alias | why this word |
|---|---|---|
| `normal` | **paddle** | the everyday grind that gets you out there — mechanical tasks, cheap models |
| `unlock_plan` | **tow** | tow-in surfing: the jetski (frontier model) pulls you into a wave you could not paddle into, then you ride it (cheap models) |
| `ui_visual_qa` | **surfcheck** | the look at the waves before you paddle out — a human understands "visual check" without reading YAML |

**Why:** renaming ids touches specs, `MODES_RECOMMENDED`, ledgers and docs
for zero user value; aliases are copy. One word each; no collision with
"Swell" (hosted SKU that does not exist).

**Owner confirms?** Yes — taste call on the three words.

## D3 — Custom mode syntax (the heart)

**Decision:** the grammar is a **subset of the existing schema — zero new
keys**. The card (`docs/go-live/CUSTOM-MODE-CARD.md`) is the product: id +
1–N stages (role + tier, or `command:` for mechanical steps) + `oracle: true`
+ gauntlet. The oracle command itself lives in the task **spec**
(`## Oraculo`, raw command, **no backticks** — incident 2026-08-10), so a
mode stays reusable across tasks.

**Privacy:** by **location, not by field**. A custom mode is a file in the
user's workdir overlay — it never leaves the machine unless the user posts
it. "Public" is an act (share the file), not a flag. An explicit
`share: false` root key would require schema extension + a loader test;
**recommended against for MVP** (a field implies infrastructure that does
not exist).

**Owner confirms?** Only if he wants the explicit `share:` field anyway.

## D4 — Private vs public mechanism

**Decision:** public = **the YAML file itself**, nowhere else. MVP mechanism
(spec S4): `oracfit mode share <id>` prints the canonical YAML with a
provenance header (id, sha256, "validate before you ride"); `oracfit mode
add <file>` installs into the workdir overlay only after `validate` +
`lint` pass. Community index = one pinned "share your break" GitHub
Discussion on the repo, linked from the site. No marketplace, no login, no
billing, no app store cosplay.

**Why:** an ads click understands "copy a file, paste a file". Everything
heavier is infrastructure the go-live does not need.

**Decided 2026-08-29 (delegated back to Fable):** ship the pinned "share
your break" Discussion at launch, seeded with the two example YAMLs from
the card. One pin, zero infra.

## D5 — TUI/CLI 1-hour journey

**Decision:** menu option 1 becomes **"First wave — stub, no API key,
~1 min"**: zero questions, runs the bundled example spec on the stub.
"New task" becomes option 2 and offers `examples/first-wave.md` as a
template when the user has no spec. Mode listing shows the 3 waves +
workdir customs; workshop modes behind an "all modes" reveal. Full journey:
`docs/go-live/JOURNEY-1H.md`. Second hour, not first: real adapter keys,
multi-stage customs.

## D6 — Tokens at cost + idle 3090s (shape, no price)

**Decision:** one honest site section, "**Tokens at cost — when the irons
sweat**": today you bring your own key (8 adapters + stub); an at-cost token
pool from idle 3090s is **not live** and has **no price** until measured.
Waitlist = GitHub issue template (no login, no new infra). Selling unlocks
on **mechanical criteria, not calendar**: (1) throughput of the actual rig
measured by the verify flow and recorded in `model-registry.json` — until
then no number exists; (2) per-key metering on top of the existing
usage-hub accounting; (3) honesty test extended so any hosted cell must
match the registry; (4) demand threshold: **25 distinct GitHub accounts**
on the waitlist (decided 2026-08-29, delegated back to Fable: at-cost means
zero margin, so N only buys proof of *stranger* demand before the metering
work gets built — 25 is beyond friend-circle reach on this channel and
small enough not to stall the flywheel; a threshold is a policy dial, not a
measurement, so it invents nothing). Bridge to bestmodel: tier rows on the
site link "will it fit your GPU? → bestmodel.run"; feeding bestmodel
answers into `model_ref` is v2.

**Owner confirms?** Vehicle = GitHub issue template (confirmed); N = 25
(owner may turn the dial, the criterion class is frozen).

## D7 — Ads and replies

**Decision:** the ad promises exactly what the first scroll cashes: *clone →
first green oracle in 2 minutes, no API key, no signup*. Forbidden in ads
and replies: "open source" (LICENSE is proprietary), tok/s, $/M, "hosted",
"marketplace". Single CTA: the clone command (site copy button / "Clone it"
in the ad). Copy in `docs/go-live/COPY.md`.

## D8 — Site v4 home

**Decision:** home = hero (clone-first, keep) + the 3 waves as 3 cards
(`alias (id)` + one honest line each) + **one** custom card ("Name your
break" — condensed ficha + the `mode init` command) + wipeouts strip
(counts from `DATA.stats`) + tokens-at-cost section (D6) + journey switcher
unchanged. God modes appear nowhere on the home. Full mode count stays in
`llms.txt` (agent surface). Honesty test remains mandatory and gains
negative greps (no god-mode ids on home, no price patterns, no OSS claim).

## D9 — The 17 workshop modes

**Decision:** keep all in git and in `oracfit modes` (operator/CLI surface —
scripts and muscle memory depend on it). TUI default list: 3 waves +
workdir customs, with an "all modes" reveal. Site home: the 3 only. No
deletions, no git hiding.

## D10 — Spec order for GLM

Six stories, `docs/go-live/specs/`, dispatch in this order (S1 first, S6
last; S2–S5 independent of each other):

| spec | story | oracle (one line) |
|---|---|---|
| S1 | first wave works from a clean clone | bash tests/test-first-wave.sh plus negative grep of the dead path |
| S2 | TUI first-wave default + 3-wave listing | bash tests/test-tui-first-wave.sh |
| S3 | mode init surf scaffold, validates+lints out of the box | bash tests/test-mode-init-scaffold.sh |
| S4 | mode share / mode add round-trip | bash tests/test-mode-share-add.sh |
| S5 | site v4 home: 3 waves + custom card + honest tokens section | bash tests/test-site-honesty.sh plus alias/negative greps |
| S6 | one mechanical go-live gate chaining all local tests | bash tests/test-go-live-local.sh |

**Not touched by any story:** LICENSE, existing `core/modes/*.yaml`,
`model-registry.json`, `incidents/`, the bestmodel repo (S25/S23/SEO),
anything cloud/Swell, prod, Vast, the Paraguay rig.

---

## Housekeeping notes (not stories)

- `docs/go-live/` is a work-order pack, not product: add it to the
  publish-cut PRIVATE_DIRS before the next public cut.
- Every story that adds a test file changes the `suites` count: the story
  updates `site/app.js` DATA.stats and `site/llms.txt` in the same commit —
  `tests/test-site-honesty.sh` green is part of each oracle chain (S6).
- `docs/SMOKE-WITH-FIRE.md` is rewritten by this session: Phase A = go-live
  checklist, Phase B = this pack only.
