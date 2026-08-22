# Adapter cursor (cursor-agent)

Integração do Oracfit com o **Cursor Agent CLI** (`cursor-agent` / `agent` / `cursor agent`).

Flags citadas vêm de [`DISCOVERY.md`](DISCOVERY.md) (`cursor-agent --help`, 2026-08-04).

## Papel

**Executor** headless via `-p/--print`. Também serve de **host orquestrador** (skill thin em `SKILL.md`) quando o agente Cursor chama `bin/oracfit` via Shell.

## Setup

```bash
source adapters/cursor/env.sh
# auth (uma vez):
cursor-agent login
# ou: export CURSOR_API_KEY=...
```

## Tradução

```bash
cursor-agent -p --force --model <cli_hints.cursor> "$(cat <spec_file>)"
# opcional: --resume <chatId>  --output-format json
```

## Capacidades

Ver [`capabilities.env`](capabilities.env). `FORK=0` — sem `--fork` no CLI.

## Auth

Sem login/`CURSOR_API_KEY`, o runner falha com **exit 3** e mensagem clara (não inventa modelo nem tenta TUI).
