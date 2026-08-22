# Dispatch — zcode

```bash
source adapters/zcode/env.sh
bin/smoke-test.sh glm-5.2-zcode
bin/dispatch.sh glm-5.2-zcode specs/minha-tarefa.md minha-task
```

Exporta `DISPATCH_RUNNER` → `adapters/zcode/runner.sh`.

Detalhes: `adapters/zcode/ZCODE.md` + `adapters/zcode/DISCOVERY.md` (CLI 0.15.2 via ZCode.app, `--prompt`, model em `~/.zcode/cli/config.json`).

Auth: `zcode login` (apiKey no cli config). `TOOLS=1`.

## Pelo celular (GUI remota)

`oracfit gui-tunnel --auth-token <token> --enable-dispatch` sobe a GUI com
link https autenticado — dá pra despachar o zcode pela página Dispatches e
acompanhar ao vivo. Detalhes: `docs/gui-remote.md`.
