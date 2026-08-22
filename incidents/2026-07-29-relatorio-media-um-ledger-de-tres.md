---
id: 2026-07-29-relatorio-media-um-ledger-de-tres
titulo: relatorio de dispatch media um ledger de tres
data: 2026-07-29
recorrivel: sim
regra: 38
  deve ler todas elas, e cada seção do relatório deve identificar
  explicitamente qual fonte está sendo reportada
status: promovido
---

# relatorio de dispatch media um ledger de tres

## Sintoma

O relatório gerado por `bin/dispatch-report.sh` lia apenas
`ledger/ledger.jsonl` — que tem 120 registros, todos com `exit_status: "ok"`,
mas só 4 com o campo `oracle_status` (3 `passou`, 1 `falhou`). Os outros 116
registros não tinham `oracle_status` por serem anteriores ao oráculo do
dispatch 2.0. Com isso, o relatório imprimia um placar "3 passou / 1 falhou /
0 morto" que descrevia exclusivamente os 4 runs de dispatch simples com
oráculo, mas era apresentado como se fosse o placar do framework inteiro.
Enquanto isso, `.dispatch/logs/escalate-ledger.jsonl` tinha 11 registros (10
`success`, 1 `blocked`) — runs do dispatch 2.1 — que nunca apareciam em
relatório nenhum.

## Causa

`bin/dispatch-report.sh` definia a fonte de dados com
`LEDGER="${LEDGER_FILE:-$REPO_ROOT/ledger/ledger.jsonl}"` e não continha
nenhuma referência a `escalate-ledger.jsonl` nem a `batch-ledger.jsonl`. Como
o framework passou a ter três ledgers (dispatch simples, escalonamento 2.1 e
lotes 2.2) mas o relatório só foi atualizado para ler um deles, o relatório
media uma fonte de três e apresentava o resultado como total.

## Correção aplicada

`bin/dispatch-report.sh` ganhou um segundo bloco Python que lê
`.dispatch/logs/escalate-ledger.jsonl` e `.dispatch/logs/batch-ledger.jsonl`
e imprime as seções `── 2.1 escalonamento ──` e `── 2.2 lotes ──`. Quando
nenhum dos dois existe, imprime `── nenhum run de 2.1/2.2 registrado em
.dispatch/logs ──`.

## Pode acontecer de novo?

Sim. A correção é manual (editar um shell script) e não há proteção
automática que force todo novo ledger a ser incluído no relatório. Se um
dispatch 2.3 surgir e `bin/dispatch-report.sh` não for atualizado, o mesmo
padrão se repete.

É da mesma classe dos incidentes
`incidents/2026-07-25-captura-de-resultado-mentiu-3x.md` e
`incidents/2026-07-29-detector-de-travamento-cego-a-oraculo-si.md` — os três
são erros de observação que escondem a presença ou o resultado de trabalho
real. Mas há uma diferença conceitual: os dois anteriores mediam a coisa
errada no mesmo arquivo (captura de `$?` depois de pipe; assinatura de erro
só de stdout); este olhava o arquivo errado — ignorava dois ledgers inteiros
e media uma fonte de três como se fosse o total.