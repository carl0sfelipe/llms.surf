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