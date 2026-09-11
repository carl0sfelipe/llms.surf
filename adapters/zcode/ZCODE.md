# Adapter zcode

Integração do Oracfit com o **ZCode CLI** (`zcode` 0.15.2 via ZCode.app).

Flags e schema de config: [`DISCOVERY.md`](DISCOVERY.md) (Passo 0, 2026-08-04).

## Papel

**Executor** headless via `--prompt`. Modelo selecionado por `cli_hints.zcode` (`providerId/modelId`) gravado em `~/.zcode/cli/config.json` a cada run.

## Setup

**macOS** (App bundle):

```bash
# symlink (idempotente) — também feito por env.sh / install
ln -sfn "/Applications/ZCode.app/Contents/Resources/glm/zcode.cjs" ~/.local/bin/zcode
```

**Linux** (AppImage extraído — wrapper em `~/.local/bin/zcode`):

```bash
# nada a linkar: env.sh detecta Linux e adiciona ~/.local/bin ao PATH
# (se o CLI não estiver em ~/.local/bin, exporte ZCODE_BIN=/caminho/do/zcode)
```

Ambos os SOs, depois:

```bash
source adapters/zcode/env.sh
zcode login   # OAuth Z.ai — necessário para apiKey no CLI
```

## Tradução

```bash
# runner atualiza model.main no cli config, depois:
zcode --prompt "$(cat <spec>)" --mode yolo [--resume sess_...] [--json] [--cwd DIR]
```

## Auth

Sem `apiKey` em `provider.<id>.options` (ou login CLI válido), o runner devolve **exit 3** com instrução — não inventa token a partir de `~/.zcode/v2/credentials.json` (lá os valores são `enc:v1:`).

## Capacidades

Ver [`capabilities.env`](capabilities.env). `FORK=0`.
