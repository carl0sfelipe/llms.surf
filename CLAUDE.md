# Dispatch — Claude Code

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
source adapters/claude-code/env.sh
```

Exporta `DISPATCH_RUNNER` → `adapters/claude-code/runner.sh`.

## Documentação

`adapters/claude-code/CLAUDE.md` — orquestração, segurança (sem
`--dangerously-skip-permissions` por default), uso como executor.

## Capacidades (TOOLS)

Trabalho que exige ler arquivo ou rodar comando só vai para runner com
`TOOLS=1`. Claude Code tem `TOOLS=1` — laço agêntico com ferramentas.