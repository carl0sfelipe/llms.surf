# Dispatch — zcode

```bash
source adapters/zcode/env.sh
bin/smoke-test.sh glm-5.2-zcode
bin/dispatch.sh glm-5.2-zcode specs/minha-tarefa.md minha-task
```

Exporta `DISPATCH_RUNNER` → `adapters/zcode/runner.sh`.

Detalhes: `adapters/zcode/ZCODE.md` + `adapters/zcode/DISCOVERY.md` (CLI 0.15.2 via ZCode.app, `--prompt`, model em `~/.zcode/cli/config.json`).

Auth: `zcode login` (apiKey no cli config). `TOOLS=1`.

## Pelo celular (GUI remota)

`oracfit gui-tunnel --auth-token <token> --enable-dispatch` sobe a GUI com
link https autenticado — dá pra despachar o zcode pela página Dispatches e
acompanhar ao vivo. Detalhes: `docs/gui-remote.md`.

## Language

All code is written in English: file names, identifiers (variables, functions, flags, JSON keys,
env vars), comments, log lines and CLI messages. A name in any other language is not allowed, even
for one variable — contributors come from everywhere and must be able to read and fork any file.

- Enforced by `bin/check-english.py` (part of `bin/check-saude.sh` and CI). It checks only the lines
  your branch adds, so old Portuguese code does not block you. Run it before committing:
  `python3 bin/check-english.py`.
- A line that must read Portuguese input (spec headings the gate still parses) carries `english-ok`
  and the reason; a block uses `english-ok-begin` / `english-ok-end`.
- Kept in Portuguese on purpose: `incidents/` and old logs (historical record), `tests/fixtures/`
  (real specs used as test data), `docs/stories/` (specs as they were sent), `site/blog/`.
- Old Portuguese code is being renamed in one pass: `docs/english-refactor-plan.md`.
