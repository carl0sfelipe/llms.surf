---
id: 2026-08-12-runner-herda-cwd-do-lancador-modelo-desp
titulo: runner herda cwd do lancador — modelo despachado edita o repo errado apesar do --workdir
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): adapters/opencode/runner.sh canonicaliza a spec e faz cd em ORACFIT_WORKDIR antes de subir o opencode; divida multi-adapter PAGA em 2026-08-12 (v3.5) — mesmo bloco em claude-code, hermes, cursor e qwen-code; zcode ja cobria via --cwd derivado de ORACFIT_WORKDIR
status: promovido
interage_com: "regra 48 (o dano se materializou como edicao in-place de script com run vivo)"
interage_com: "2026-08-12-dispatch-de-shell-de-agente-morre-com-o-.md (mesmo run 36E63816, evento distinto)"
---

# runner herda cwd do lançador — modelo despachado edita o repo errado

## Sintoma

Run `36E63816` (mode overlay glm_mecanismo, modelo z-ai/glm-5.2): lançado de
`<home-do-dono>/oracfit` com `--workdir /tmp/oracfit-override` (git worktree
criado JUSTAMENTE para isolar as edições do repo vivo). O worktree ficou
limpo; `git status` do repo REAL mostrou `M bin/dispatch-*.sh` — o modelo
editou o repo vivo, incluindo `bin/dispatch-mode.sh`, que estava sendo
executado naquele momento pelo run de fornecedores (bash 64732, fd 255).

## Causa

EVIDÊNCIA: `rg -o '"filePath":"[^"]*"' runner-1.log | sort -u` → todos os
paths em `<home-do-dono>/oracfit/...`, nenhum em `/tmp/oracfit-override`.

`--workdir` seta `ORACFIT_WORKDIR`, que governa eventos, ledger, oráculo e
overlay de modos — mas NÃO o cwd do runner. `adapters/opencode/runner.sh`
herdava o cwd do lançador e o opencode edita arquivos relativos ao CWD DELE.
O isolamento por worktree era ilusório: o contrato do workdir não chegava ao
processo que faz as edições.

## Correção aplicada

`adapters/opencode/runner.sh`: canonicaliza `SPEC_FILE` para caminho absoluto
e faz `cd "$ORACFIT_WORKDIR"` (quando definida) antes de montar a chamada do
opencode — workdir inexistente é exit 3. Aplicado via temp + mv (regra 48:
o runner.sh tinha leitor vivo, PID 64894).

Contenção do dano no repo vivo: `bin/dispatch-mode.sh` foi restaurado
byte-idêntico NO MESMO inode (cat original > arquivo) para realinhar os
offsets do leitor vivo; os demais scripts editados não tinham leitor.

## Pode acontecer de novo?

No opencode, não — o cd é incondicional quando há workdir. Os outros
adapters com TOOLS=1 (claude-code, hermes, qwen-code, zcode) têm o mesmo
gap e precisam do mesmo cd quando forem usados com `--workdir` — dívida
declarada aqui; o mecanismo é o mesmo (3 linhas no runner de cada um).
