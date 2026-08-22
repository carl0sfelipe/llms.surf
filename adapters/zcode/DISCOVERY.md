# DISCOVERY — zcode

Data: 2026-08-04
Binário: `<home-do-dono>/.local/bin/zcode` → `/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs`
Versão: `0.15.2` (`zcode --version`)

## Passo 0 (confirmado)

```
$ command -v zcode
<home-do-dono>/.local/bin/zcode

$ zcode --help
zcode 0.15.2
Usage: zcode [command] [options]
  --prompt <text>   Run a single prompt without opening the TUI
  -p, --print       Run a positional prompt without opening the TUI
  --mode <mode>     build | edit | plan | yolo (default yolo for --prompt)
  --resume <sessionId>   sess_...
  -c, --continue
  --json
  --cwd <path>
  --settings <path>
  --max-turns <n>
  --allowed-tools / --disallowed-tools
Slash: /model [list|main|lite|provider/model]  /fork ...
```

**Sem `--model` no CLI.** Modelo vem de `~/.zcode/cli/config.json`:

```json
{
  "model": { "main": "providerId/modelId" },
  "provider": {
    "providerId": {
      "kind": "anthropic|openai|openai-compatible",
      "options": { "baseURL": "https://...", "apiKey": "..." }
    }
  }
}
```

`kind` é obrigatório no bloco `provider.<id>`. `model.main` é string `provider/model` (não objeto).

Auth Z.ai: GUI usa OAuth em `~/.zcode/v2/credentials.json` (criptografado). CLI headless exige `apiKey` em `provider.*.options` **ou** `zcode login` que provisione chave legível para o CLI. Medido 2026-08-04: sem apiKey → `Model provider is missing an API key`; token `enc:v1:` cru → HTTP 401.

## Capacidades

| Capacidade | Valor | Base |
|---|---|---|
| DISPATCH | 1 | `--prompt` |
| SESSION_REUSE | 1 | `--resume sess_...` |
| FORK | 0 | `/fork` é slash TUI, não flag CLI |
| ATTACH_TUI | 0 | TUI fora do contrato runner |
| FORMAT_JSON | 1 | `--json` |
| TOOLS | 1 | agent loop com tools |
| STREAMS_OUTPUT | 0 | conservador (não medido streaming estável) |

Symlink instalado pelo Oracfit (se ausente):

```bash
ln -sfn "/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs" "$HOME/.local/bin/zcode"
```
