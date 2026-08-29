# Public Cut — llms.surf v3.5.0

This repository is the public product **llms.surf** (formerly Oracfit) —
local dispatch with a mechanical oracle. Marketing surface: `site/`.

## What is here

- Core of the framework (classify → mode → runner → oracle → panel)
- Observe-only panel
- Mode YAMLs (schema v1), including `unlock_plan` / `vision_catalog`
- Adapters: opencode, Claude Code, Cursor, Hermes, qwen-code, llama.cpp, zcode, prime-agent, stub
- `bin/`, `check-saude`, test suites
- `site/` — public marketing pages (honest DATA, gated by `tests/test-site-honesty.sh`)
- `incidents/` — the 106 postmortems that shipped in this cut (`uso/` is private and must not ship)

## O que fica no monorepo de desenvolvimento

- Incidents promote → regras
- Labs (experimentos, ghosts, scorecards)
- HANDOFF entre sessões
- Diário privado de decisões de design

## Painel

Observe-only por design. Botão stop/rerun é v2. Decisões ficam no CLI.

## Runtime unlock/vision

Os YAML `unlock_plan` e `vision_catalog` já estão no repo para validação (`mode validate`).
A execução multi-stage (unlock → plan → run / map → reduce) é **v2**.