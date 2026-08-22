---
name: dispatch-claude-code
description: Orquestrar dispatch de modelos free (via opencode) a partir de Claude Code. Use sempre que for gerar >20 linhas de código/doc/output — nunca escreva bulk manualmente.
---

# dispatch (Claude Code)

Fonte: `core/dispatch-spec.md`, `adapters/claude-code/CLAUDE.md`.

Regra de ouro: acima de ~20 linhas de output, despache para um modelo free em
vez de escrever manualmente.

## Setup

```
source adapters/opencode/env.sh
```

(opencode é o executor default — ver `adapters/claude-code/CLAUDE.md`, papel
orquestrador vs executor.)

## Fluxo

```
1. Investigar (grep/read/ls o repo)
2. Escrever spec grounded (10-30 linhas, caminhos exatos) em specs/
3. bin/pre-dispatch-check.sh <provider_id>
4. bin/smoke-test.sh <model_id>
5. bin/dispatch.sh <model_id> <spec_file> <task_name>
6. bin/poll-status.sh <task_name>
7. Ler output, verificar contra código real (grep/ls)
8. Se errado: novo spec DELETE/REESCREVA/ADICIONE, repetir 5-7
9. Commit + push
```

Todos os `<model_id>` vêm de `model-registry.json` — nunca inventados.

## Instalação em `~/.claude/skills/`

Preferred Oracfit root: `$ORACFIT_ROOT` (default `~/.oracfit/current`).

```
adapters/claude-code/install.sh
```
