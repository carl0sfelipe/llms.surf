# DISCOVERY — cursor (cursor-agent)

Data: 2026-08-04
Binário: `<home-do-dono>/.local/bin/cursor-agent` → `~/.local/share/cursor-agent/versions/.../cursor-agent`
Alias: `agent` (mesmo binário). Também: `cursor agent` via Cursor.app.

Comando: `cursor-agent --help` (resumo das flags usadas pelo runner)

```
Usage: agent [options] [command] [prompt...]

Options:
  --api-key <key>           CURSOR_API_KEY / CURSOR_AUTH_TOKEN
  -p, --print               Headless: imprime resposta (tools + write + shell)
  --output-format <format>  text | json | stream-json (só com --print)
  --mode <mode>             plan | ask
  --resume [chatId]         Retoma sessão
  --continue                Continua sessão anterior
  --model <model>           ex.: gpt-5, sonnet-4-thinking
  -f, --force / --yolo      Auto-aprova comandos
  --workspace <path>        cwd do agente
  --list-models             Lista modelos (exige auth)

Auth: `cursor-agent status` → "Not logged in" até `cursor-agent login`
      ou env CURSOR_API_KEY / CURSOR_AUTH_TOKEN.
```

## Capacidades (contrato)

| Capacidade | Valor | Base |
|---|---|---|
| DISPATCH | 1 | `-p/--print` + prompt posicional |
| SESSION_REUSE | 1 | `--resume [chatId]` |
| FORK | 0 | sem `--fork` no help |
| ATTACH_TUI | 0 | headless only no runner |
| FORMAT_JSON | 1 | `--output-format json` |
| TOOLS | 1 | `-p` tem write/shell |
| STREAMS_OUTPUT | 0 | resposta completa no fim (como claude -p) |

## Tradução do contrato

```
runner.sh <model_id> <spec_file> [--session ID]
→ cursor-agent -p --force --model <cli_hints.cursor> [--resume ID] [--output-format json] "$(cat spec)"
```

`--fork` → exit 3 (não suportado).
