## T17 — Environment isolation mechanism (30 min)

M9 in T06 survives because no test observes the environment. Add
`tests/env_isolation.rs`: set `OPENROUTER_API_KEY`, `OPENCODE_TOKEN`,
`HOME`, `PATH` to poison values, run `resolve` with an empty credential
set, assert every non-keyless entry is skipped (L4 holds regardless of
env). Then re-apply M9 on a scratch copy and confirm the new test kills
it. Oracle: mutation killed; test in tree.

