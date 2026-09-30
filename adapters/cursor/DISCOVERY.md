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
| FORMAT_JSON | 1 | `--output-format json` / `stream-json` |
| TOOLS | 1 | `-p` tem write/shell |
| STREAMS_OUTPUT | 0 | `json` entrega no fim; `stream-json` é NDJSON ao vivo (abaixo) |

## Tradução do contrato

```
runner.sh <model_id> <spec_file> [--session ID]
→ cursor-agent -p --force --model <cli_hints.cursor> [--resume ID] [--output-format stream-json] "$(cat spec)"
```

`DISPATCH_RUNNER_FORMAT_JSON=0` → sem `--output-format` (texto).
`--fork` → exit 3 (não suportado).

## stream-json verificado (cursor-agent 2026, Grok 4.6)

Amostra real: `tests/fixtures/cursor-stream-sample.jsonl`. Uma linha JSON por evento.
`--output-format stream-json` só com `-p/--print` (já no help de 2026-08-04).

| `type` / `subtype` | Campos verificados |
|---|---|
| `system` / `init` | `apiKeySource`, `cwd`, `session_id`, `model`, `permissionMode` |
| `user` | `message.role`, `message.content[]` (`type=text`, `text`), `session_id` |
| `thinking` / `delta` | `text`, `session_id`, `timestamp_ms` |
| `thinking` / `completed` | `session_id`, `timestamp_ms` (sem `text`) |
| `assistant` | `message.role`, `message.content[]` (`type=text`, `text`), `session_id`, `model_call_id` |
| `tool_call` / `started` | `call_id`, `tool_call.<x>ToolCall.args` (`readToolCall`/`editToolCall` + `args.path`), `session_id`, `timestamp_ms` |
| `tool_call` / `completed` | mesmo `call_id` + `tool_call.<x>ToolCall.result` |
| `result` | `subtype=success`, `duration_ms`, `duration_api_ms`, `is_error`, `result`, `session_id`, `request_id`, `usage.inputTokens`, `usage.outputTokens`, `usage.cacheReadTokens`, `usage.cacheWriteTokens` |

O runner usa `stream-json` (não `json`) quando `DISPATCH_RUNNER_FORMAT_JSON=1`. `adapters/cursor/stream-events.py` repassa cada linha ao stdout e, com `ORACFIT_RUN_ID`, emite `tool_call`/`thinking`/`metric` no envelope de `bin/lib-oracfit-events.sh`.

`system/init.apiKeySource` casa com a regex `api.?key` — detecção de auth no runner ignora linhas JSON, exceto o campo `result` de `{"type":"result","is_error":true}`.
