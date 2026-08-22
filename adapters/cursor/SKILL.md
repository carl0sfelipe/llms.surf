---
name: oracfit-cursor
description: Oracfit via Shell — thin skill for Cursor. Set ORACFIT_ROOT and call bin/ scripts. Use when dispatching bulk work or when WhatsApp/Hermes handoff needs oracfit.
---

# Oracfit (Cursor)

Thin skill: Oracfit core is invoked via shell. Cursor can be **host** (this skill) or **executor** (`source adapters/cursor/env.sh`).

## Setup

```bash
export ORACFIT_ROOT="${ORACFIT_ROOT:-$HOME/.oracfit/current}"
export DISPATCH_ROOT="$ORACFIT_ROOT"
```

## Usage (orquestrador → flash/outros)

```bash
source "$ORACFIT_ROOT/adapters/opencode/env.sh"   # executor default free
$ORACFIT_ROOT/bin/oracfit run normal specs/tarefa.md minha-task
# legado: $ORACFIT_ROOT/bin/dispatch-mode.sh normal specs/tarefa.md minha-task
```

## Usage (Cursor como executor)

```bash
source "$ORACFIT_ROOT/adapters/cursor/env.sh"
# requer: cursor-agent login  OU  CURSOR_API_KEY
$ORACFIT_ROOT/bin/dispatch.sh <model_id_com_cli_hints.cursor> specs/tarefa.md minha-task
```

## Trocar executor

| Executor | source |
|---|---|
| opencode (free) | `adapters/opencode/env.sh` |
| claude | `adapters/claude-code/env.sh` |
| zcode | `adapters/zcode/env.sh` |
| cursor | `adapters/cursor/env.sh` |
| hermes | `adapters/hermes/env.sh` |
| stub | `export DISPATCH_RUNNER=$ORACFIT_ROOT/adapters/stub/runner.sh` |

Oracfit — Carlos Felipe
