# English refactor plan — one name, English everywhere

> Owner decision, 2026-10-02: llms.surf is open source and pre-v1 with zero users, so there is no reason
> to keep legacy names or aliases. Contributors come from everywhere; every file must be readable and
> forkable by someone who does not speak Portuguese.
> Status: plan. The rule for **new** code is already enforced (AGENTS.md "Language",
> `bin/check-english.py`). This document removes the **old** debt.

## 1. Decisions already taken

| Topic | Decision |
|---|---|
| Product / CLI name | `llms-surf` (`surf` alone clashes with the suckless browser). Env prefix `SURF_` (already used by `SURF_TOOLCHAIN_GATE`). |
| Legacy names | `oracfit`, `Dispatch`, `ORACFIT_*`, `DISPATCH_*`, `.dispatch/` are removed, not aliased. |
| Scope | Code (identifiers, comments, messages) + entry docs (README, AGENTS/CLAUDE/QWEN/ZCODE, SKILL, `fluxos/`, `core/*.md`, `docs/` technical docs) in English. |
| Stays Portuguese | `incidents/`, old logs, `docs/stories/` (historical record), `tests/fixtures/` (real specs as test data), `site/blog/`. A note in `incidents/README` says why. |
| GUI | Strings move to `panel/locales/en.json` (default) + `panel/locales/pt-BR.json`. |
| When | **After the open branches are closed** (§4, phase 0). A tree-wide rename on top of 14 open branches turns every merge into a conflict. |

## 2. Measured footprint (2026-10-02, branch `feat/check-delegacao`)

- `oracfit`: 2,379 occurrences in 281 tracked files; 32 file names (`bin/oracfit*`, `bin/lib-oracfit-*`,
  `bin/test-oracfit-*`).
- Env vars: 64 distinct `ORACFIT_*`, 26 distinct `DISPATCH_*`; `.dispatch/` referenced in 107 files.
- Portuguese in code (`python3 bin/check-english.py --all`): ~6,450 lines in 204 files —
  `bin/` 3,385 · `tests/` 1,482 · `panel/` 564 · `core/` 460 · `adapters/` 359 · `site/` (non-blog) 114 ·
  `model-registry.json` 47. Largest: `bin/oracfit-panel-server.py` (276), `tests/test-ring-runner.sh`
  (225), `panel/passos.html` (208), `bin/oracfit-ring.sh` (208), `bin/check-oracle.py` (142).
- Outside this repo: 12 files in `~/hq-memoria` reference `oracfit` / `$ORACFIT_ROOT`; consumer repos
  (`/opt/inference`, the hq tasks) call `oracfit run|batch` and write specs with Portuguese headings.

Re-measure before starting: the numbers move with every merge.

## 3. Name map

### 3.1 Product names (mechanical, scripted)

| Today | After |
|---|---|
| `bin/oracfit` | `bin/llms-surf` |
| `bin/oracfit-<x>.{sh,py}` | `bin/<x>.{sh,py}` — the prefix is redundant inside this repo's `bin/` |
| `bin/lib-oracfit-<x>.{sh,py}` | `bin/lib/<x>.{sh,py}` |
| `bin/test-oracfit-<x>.sh` | `tests/test-<x>.sh` (one test location) |
| `oracfit_<fn>` shell functions | `surf_<fn>` |
| `ORACFIT_<X>`, `DISPATCH_<X>` | `SURF_<X>` (collisions resolved by hand: e.g. `ORACFIT_ROOT` and `DISPATCH_ROOT` → `SURF_ROOT`) |
| `.dispatch/` state dir | `.llms-surf/` |
| headings "Dispatch — opencode" etc. | "llms.surf — opencode" |

### 3.2 Portuguese names → English

| Today | After |
|---|---|
| `fluxos/`, `fluxos/_comum/` | `flows/`, `flows/_shared/` |
| `step-01-escolher-alvo.md`, `step-02-medir-em-sandbox.md`, `step-01-registrar.md`, ... | `step-01-pick-target.md`, `step-02-measure-in-sandbox.md`, `step-01-record.md`, ... |
| `bin/check-saude.sh`, workflow `check-saude` | `bin/check-health.sh`, `check-health` |
| `bin/check-fantasma.sh` | `bin/check-ts-declare.sh` (says what it catches) |
| `bin/corte-review.py`, `panel/corte.html` | `bin/release-cut-review.py`, `panel/release-cut.html` |
| `bin/oracfit-acao.py`, `oracfit acao` | `bin/owner-action.py`, `llms-surf action` |
| `panel/passos.html`, `ajuda`, `retomada`, `regras` | `steps.html`, `help`, `resume`, `rules` |
| `fantasma-baselines/` | `ts-declare-baselines/` |
| spec headings `## Oráculo`, `- comando:`, `## Dados verificados`, `## ENTREGÁVEIS`, `## Objetivo`, `## Barra`, `- nome:`, the no-invention clause | `## Oracle`, `- command:`, `## Verified data`, `## DELIVERABLES`, `## Goal`, `## Bar`, `- name:`, "Do not invent numbers, dates or sources beyond the ones listed" |

Spec headings are **input from other repos**, not just code here, so `check-spec`, the gauntlet and
`delegation-check` accept both languages during phase 3 and drop Portuguese in phase 5, once the
consumer repos' spec templates are migrated. This is the only temporary dual form, and it has an end date.

### 3.3 Names that are English but do not explain themselves — owner decision

Rename only if the owner agrees; each is a product choice, not a translation.

| Name | What it is | Suggestion |
|---|---|---|
| modes `aion`, `ananke`, `autarca`, `demiurgo`, `hefesto`, `midas`, `ouroboros`, `pantocrator`, `talos` | experimental "god modes" (single frontier model running every role) | move to `core/modes/experimental/` with a one-line `description:` in English; keep the codenames or use `loop-v4`, `chain`, ... |
| `gauntlet` | retry loop with oracle feedback | keep (English, documented) |
| `flash_work_s`, `frontier_wait_s` | ledger timings | `executor_s`, `orchestrator_wait_s` |
| `ring` (`oracfit-ring.sh`) | god-mode ring runner | `mode-ring.sh` or keep |
| `lineup` | contributor points board | keep |

## 4. Phases

**Phase 0 — close the open branches (prerequisite).** 14 remote branches are not merged into `main`
(`git branch -r --no-merged origin/main`). Each one is merged or closed by the owner. Only then does phase 1 start,
on a fresh branch from `main`, with no other work in flight on this repo.

**Phase 1 — mechanical rename (one PR, scripted).** `bin/dev/rename-map.tsv` holds every pair from
§3.1–3.2. `bin/dev/apply-rename.py` applies it: `git mv` for paths, word-boundary replace for
identifiers, env vars and references, and it skips the Portuguese-on-purpose paths from §1. The same script
is used to rebase any branch that was cut before the rename (`apply-rename.py --on-branch`), so late work is
not lost. Gate: every suite green, `git grep -i oracfit` matches only `incidents/` and `docs/stories/`.
Done by the orchestrator directly: it is a script plus a review, not a large writing task.

**Phase 2 — translate comments and messages, one directory per PR.** Order by size from §2:
`bin/` → `tests/` → `core/` → `adapters/` → `model-registry.json`. This is large, mechanical output with
little context per file, so `llms-surf delegation-check` says DELEGATE to the local GPU (free); the
orchestrator reviews. Gate per PR: `check-english.py --all <dir>` is 0 and the suites are green. Do not change behaviour in
the same PR as a translation.

**Phase 3 — GUI locale.** `panel/*.html` strings go to `panel/locales/{en,pt-BR}.json`, English by default,
language picked from the browser. Spec headings are accepted in both languages from this phase on (§3.2).

**Phase 4 — entry docs.** README (the English one becomes the main one; `README.pt-BR.md` stays as a
translation), AGENTS/CLAUDE/QWEN/ZCODE, `SKILL.md`, `flows/`, `core/*.md`, technical `docs/`.
`incidents/README` gets the note "postmortems before 2026-10 are in Portuguese, kept as historical record".

**Phase 5 — dependents and lock-in.**
- `~/hq-memoria` (12 files), the owner's memory notes, consumer repos' spec templates and scripts
  (`/opt/inference`): `oracfit` → `llms-surf`, `$ORACFIT_ROOT` → `$SURF_ROOT`, headings in English.
- Drop the Portuguese spec headings from the parsers.
- CI runs `check-english.py --all` instead of the diff mode: from then on the whole tree must stay clean.

## 5. Done when

- `python3 bin/check-english.py --all` exits 0.
- `git grep -i -E "oracfit|ORACFIT_|DISPATCH_|\.dispatch/"` matches only the paths kept on purpose.
- `bin/check-health.sh` and every `tests/test-*.sh` are green; a dispatch from a consumer repo
  (`llms-surf run normal <spec> <task>`) passes end to end with an English spec.
