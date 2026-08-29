# v4 plan — read the sea

> measured, reported, or "no data yet — we say so". nothing else.
> HTML twin: `site/v4-plan.html`.

## The pipeline today

One 4-stage pipeline ships in this public cut: **spec open → dispatch → oracle → incident**.

God modes, rings, `critic-guard`, watchdog, frozen-oracle sha256, and the usage hub are in the tree (`core/modes/`, `bin/`, `tests/`). Median ring duration and dollar cost of a typical run are **no data yet on this page** — we will not reprint a README anecdote as a live metric.

## Swell roadmap

| item | number | tier |
|---|---|---|
| Public site (`site/`) | files in this git tree | measured |
| Swell hosted endpoint | — | no data yet — we say so |
| tok/s on a hosted 3090 cell | — | no data yet — we say so |
| Llama-3.3-70B on our rig | — | no data yet — we say so |
| Saquarema dedicated rigs | pricing on request | no data yet — we say so |
| Does this model fit your GPU? | [bestmodel.run](https://bestmodel.run) | sister product |

## After v1 is live

Smoke-with-fire: Fable dogfoods the live site and the CLI, then `llms-surf` dispatches remaining work (bestmodel S25 cluster, llms.surf v1.1 from real usage) through `glm_smart` under frozen oracles. Spec: [`docs/SMOKE-WITH-FIRE.md`](SMOKE-WITH-FIRE.md).
