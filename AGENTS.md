# Dispatch — opencode

Este repositório é um framework de orquestração de trabalho entre vários modelos
de IA, usável a partir de vários CLIs.

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
source adapters/opencode/env.sh
```

Exporta `DISPATCH_RUNNER` → `adapters/opencode/runner.sh`.

## Documentação

`adapters/opencode/AGENTS.md` — setup, fork, attach TUI, contrato do runner.

## Capacidades (TOOLS)

Trabalho que exige ler arquivo ou rodar comando só vai para runner com
`TOOLS=1`. opencode tem `TOOLS=1` — laço agêntico com read/write/bash.