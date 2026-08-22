---
id: 2026-08-13-ring-ledger-central-dividido-por-env-herdado-de-shell
titulo: ledger central do ring dividido — ORACFIT_CENTRAL_LEDGER herdado de shell de smoke antiga desviou o open do A-1
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — bin/oracfit-ring.sh (central resolvido do state.json; env só no init)
status: aberto
interage_com: "2026-08-13-ananke-god-mode-v4-teste-de-campo-3-aneis-mecanismos-pegaram-executor-e-runner"
---

# ledger central dividido por env ambiente em runtime

## Sintoma

No fechamento do teste de campo ananke, a contagem de eventos divergiu:
ledger do workdir com `{open: 3, close: 3}` e ledger central com
`{open: 2, close: 3}` para o MESMO run — o open do A-1 não estava no
central oficial.

## Causa

Com EVIDÊNCIA: a linha faltante foi encontrada em `/tmp/central-dbg.jsonl`
(`rg 'ananke-20260813-0011' /tmp/central-dbg.jsonl` → o open do A-1
completo). Esse arquivo era o override `ORACFIT_CENTRAL_LEDGER` de uma
sessão de DEBUG anterior no mesmo shell persistente; o runner resolvia o
caminho do central por env ambiente A CADA comando, então o comando de
open rodado num shell com env sujo escreveu no central errado — e os
comandos seguintes (shell reciclado, env limpo) escreveram no certo.
Split-brain silencioso: nenhum dos dois lados é detectavelmente "errado"
sozinho. Mesma família do satélite do aion (ledger local vs central) e do
schema drift do autarca.

## Correção aplicada

- `bin/oracfit-ring.sh`: `ring init` grava `central_ledger` no
  `ring/state.json` (capturando o env DAQUELE momento, que é o contrato de
  teste); `require_state` passa a resolver o central do STATE — env
  ambiente deixa de ter efeito em open/close/score/abort.
- Backfill honesto: a linha do open A-1 foi copiada de
  `/tmp/central-dbg.jsonl` para `ledger/ledger.jsonl` (append, timestamp
  original preservado), documentado aqui.
- Suíte re-rodada após a mudança: 29 PASS, 0 FAIL (os testes setam o env
  antes do init e o state o captura — contrato preservado).

## Pode acontecer de novo?

Sim, como CLASSE: qualquer script do bin/ que resolva RECURSO
COMPARTILHADO (ledger, registry, hub) por env ambiente em RUNTIME está
sujeito a shell com env herdado de outra tarefa — agentes reusam shells
persistentes o tempo todo. Regra candidata (no postmortem principal):
recurso compartilhado resolve por state/config gravado, env só em
init/bootstrap explícito.
