# Public Cut — Oracfit v1.0.0

Este repositório é o produto **Oracfit v1.0.0** — despacho por aptidão com oráculo local.

## O que está aqui

- Core do framework (classify → mode → runner → oracle → panel)
- Painel observe-only
- Modes YAML (schema v1), incluindo `unlock_plan` / `vision_catalog` (runtime v2)
- Adapters: opencode, Claude Code, Hermes
- Scripts de bin/, check-saude, smoke tests

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