# Delegation check — is it worth delegating this task?

> Origin (2026-10-02): after three dispatches to Sonnet on `inference-paraguai`, the owner noticed that
> "Sonnet delivers almost faster than the time you spend writing and fixing specs".
> Status: implemented — `bin/delegation-check.py`, `bin/oracfit-verify.sh`, `bin/oracfit-roi.py`,
> cost capture in `adapters/claude-code/runner.sh`.

## 1. What the three dispatches showed (measured)

| Run | Spec written by the orchestrator | Delivered by the executor (code + tests) | Executor time | Attempts |
|---|---|---|---|---|
| `6916e35a` TR-1+TR-3 | 7.1 KB | ~13 KB (398 lines inserted) | 80 s | 1 |
| `0d0581d7` TR-6+TR-7 | 7.2 KB | ~11 KB (5 KB code + 159 test lines) | 129 s | 1 |
| `e36e4daa` TEL-1 | 7.0 KB | ~12 KB (391 insertions in 18 files) | 88 s | 1 |

Sources: `wc -c /opt/inference/dispatch/*.md`, `git show --stat`, `.dispatch/ledger/mode.jsonl`.
The specs are kept as test fixtures in `tests/fixtures/delegation/`.

- **Spec ÷ delivery ≈ 0.55–0.65.** The orchestrator (the most expensive model) wrote more than half of what it
  would have written doing the task itself, and then **read it all back** in review. Review is not optional:
  the review, not the oracle, caught the missing `umask` in the backup and a test that pinned transient state.
- **All passed on the first attempt.** The usual payoff of delegation (the trial-and-error loop running in the
  cheap context) **never happened**.
- The executor spends too: it reads context and runs tests. With the orchestrator writing 60% of the output,
  the total was probably **equal or worse** than doing it directly. Nobody could tell, because the ledger
  recorded `estimated_cost` as a constant `"0"` and the claude-code runner threw away the
  `total_cost_usd`/`usage` that `claude -p` returns.

**Conclusion:** delegating a small, well-specified task that passes on the first try to a paid model is a cost,
not a saving. Delegating is still right when (a) the executor is ~free (the local GPU); (b) the output is large
compared to the spec; (c) the task will iterate a lot (the loop burns executor tokens, not orchestrator tokens);
(d) the orchestrator has other work to do in parallel; (e) the orchestrator's context must be protected.

## 2. The check — `oracfit delegation-check`

**Run it before writing the spec**:

```
oracfit delegation-check --deliverable-lines <n> [--context a,b] --executor <model_id>
```

Writing the spec is the expensive part, so refusing only the dispatch saves nothing (owner, 2026-10-02).
In this mode the spec size is estimated (`SPEC_TO_OUTPUT_RATIO` = 0.94, measured on the specs above) and the
decision is cost-only. With a finished spec, `oracfit delegation-check <spec> --executor X` measures it for
real, which is useful for calibration, not for saving.

### Inputs (all measured, nothing guessed)
- `spec_tok` = spec characters ÷ 4.
- `output_tok` = sum of the line budgets under DELIVERABLES (`<= N lines`) × tokens per line (12 for now).
  No budget declared → the check refuses and asks for one (exit 3).
- `context_tok` = size of the files named under "Verified data" (or `--context`).
- Prices: `core/prices.json` (USD per million tokens); `null` = unknown → exit 4; local GPU = 0.
- `attempts` = mean from the ledger for that executor once it has ≥ 3 rows; otherwise 1.5.

### Formula
```
delegate = spec_tok·P_orch_out + output_tok·P_orch_in (review)
         + attempts·(context_tok·TOOL_ROUNDS·P_exec_in + output_tok·1.3·P_exec_out)
direct   = output_tok·1.3·P_orch_out + attempts·context_tok·TOOL_ROUNDS·P_orch_in
```
`TOOL_ROUNDS` = tool round-trips per attempt (6 for now).

### Verdict
| # | Condition | Output |
|---|---|---|
| 1 | executor has no per-token cost (local GPU) | `DELEGATE` (exit 0) |
| 2 | `--parallel` or `--protect-context` | `DELEGATE` |
| 3 | `spec_tok / output_tok > 0.5` and paid executor (spec mode only) | `DIRECT` (exit 10, a warning, not an error) |
| 4 | `delegate ≤ 0.7 · direct` | `DELEGATE` |
| 5 | otherwise | `DIRECT` |

The output prints both costs and the reason on one line; `--json` gives the same fields for scripts.

## 3. Direct mode that stays visible — `oracfit verify <spec> <task>`

`DIRECT` must not mean "vanished from the panel" (owner rule: everything goes through llms.surf).
`oracfit verify` calls no model:

1. `oracfit verify <spec> <task> --before` — the oracle must be **red** (exit 2 if it is already green:
   make the oracle stricter);
2. the orchestrator implements;
3. `oracfit verify <spec> <task>` — runs the oracle and writes a ledger row with `model_id: orchestrator`,
   `mode_id: direct`, `cost_source: orchestrator-unmeasured`, plus `run_started`/`run_finished` events.

Same gate, same proof, without paying for the round-trip.

## 4. Measured ROI — closing the loop

1. `adapters/claude-code/runner.sh` reads `total_cost_usd` and `usage` from the JSON (via
   `result_summary.py`) and hands them to the ledger (`estimated_cost`, `executor_in_tok`,
   `executor_out_tok`). A denied write now exits 3 instead of 0 (incident 2026-10-02: five attempts burned,
   no file written).
2. `oracfit roi [--since YYYY-MM-DD] [--json]` — per executor: pass rate, first-try %, mean attempts,
   measured cost, cost per pass. Unmeasured cost shows as `n/a`, never 0. It prints the mean attempts to feed
   back into the check.
3. Next: a `DELEGATE` whose real ROI comes out < 1 three times in a row for the same task class becomes an
   incident ("the delegation rule is wrong for this class").
