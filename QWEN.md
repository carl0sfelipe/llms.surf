# Dispatch — qwen code

Este repositório é um framework de orquestração de trabalho entre vários modelos de IA, usável a partir de vários CLIs.

**Leia `SKILL.md` primeiro** — regras, mapa geral e protocolo anti-travamento.

## Quero X, leia Y

| Quero | Leia |
|---|---|
| despachar trabalho para um modelo | `fluxos/dispatch/SKILL.md` |
| entender um dispatch que travou | `fluxos/diagnose/SKILL.md` |
| medir um modelo antes de gravar no registry | `fluxos/verify/SKILL.md` |
| transformar uma falha em proteção real | `fluxos/incident/SKILL.md` |
| saber onde foi parar a regra N | `fluxos/_comum/mapa-regras.md` |

## Ativação

```
source adapters/qwen-code/env.sh
```

Exporta `DISPATCH_RUNNER` → `adapters/qwen-code/runner.sh`.

## Documentação

`adapters/qwen-code/QWEN.md` — CLI `qwen` não instalada neste host; modelos
Qwen acessíveis via opencode hoje.

## Capacidades (TOOLS)

Trabalho que exige ler arquivo ou rodar comando só vai para runner com
`TOOLS=1`. qwen-code tem `TOOLS=0` — CLI ausente, nada verificado.

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
