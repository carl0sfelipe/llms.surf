---
id: 2026-08-12-autarca-oraculo-verde-2x-no-mesmo-minuto-aprovou-assercao-flaky-que-o-anel-seguinte-estourou
titulo: Oráculo do AUTARCA rodou a suíte 2x verde (148/148, rodadas a ~3s de distância) e fechou o anel A-5 com uma asserção flaky de corrida dentro — o anel A-6 a estourou na primeira rodada (1 failed/158 passed); "verde 2x no mesmo minuto" é amostra correlacionada, não prova de determinismo
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata: re-rodar os testes NOVOS do anel de forma descorrelacionada no ring close (regra nova 6 do postmortem principal)
status: aberto
interage_com: "2026-08-12-autarca-god-mode-7-aneis-esgotou-o-backlog-mas-o-hardening-dos-incidents-da-manha-degradou-na-propria-sessao-que-o-escreveu"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
---

# Verde 2x aprovou flaky — a bomba explodiu um anel depois, por sorte

## Sintoma

No anel A-5 (Story 5.1, mesas de cash), o critic pediu um teste de
CORRIDA fechar×sentar concorrentes (`Promise.all`). O executor escreveu a
prova comparando timestamps do banco: "se sentou, `seated_at` ≤
`closed_at`". O oráculo do fechamento rodou a suíte completa 2x —
148/148 verde nas duas (terminal: rodadas iniciando 22:36:44 e ~22:36:47,
~3s de distância) — e o anel fechou (commit `6a9c029`).

A asserção era flaky por construção: `now()` do Postgres congela no
INÍCIO da transação, não na aquisição do lock `FOR UPDATE`. Quando a
transação de fechar começa antes mas executa depois da de sentar,
`closed_at` < `seated_at` mesmo com a serialização correta — o teste
reprova um comportamento CERTO dependendo do escalonamento. Passou 2x
no A-5; na PRIMEIRA rodada do oráculo do anel A-6 (22:42:45), estourou:
`Tests 1 failed | 158 passed (159)` apontando exatamente a comparação de
datas (terminal). O fix (trocar timestamps por prova de consistência
resposta↔banco: 201 ⟺ 1 assento, 409 ⟺ 0) saiu no commit `3768e37`
(diff em `apps/realtime/test/cash.test.ts`).

## Por que é um incident PRÓPRIO

Não é cláusula degradando (o oráculo RODOU como mandado) nem julgamento
ruim do critic (o pedido de teste concorrente era correto). É desenho de
oráculo: **duas rodadas consecutivas na mesma máquina, no mesmo minuto,
com o mesmo estado de banco e a mesma carga, são uma amostra
correlacionada** — para asserções sensíveis a escalonamento, verde-2x
tem poder estatístico próximo de verde-1x. A cadeia foi salva por ter um
anel seguinte que re-rodou a suíte 6 minutos depois; numa cadeia que
terminasse no A-5, a flaky entraria no repo com selo verde e taxaria
TODO fechamento futuro (e a primeira vítima teria sido a sessão paralela
ou o dono, não o autor).

Nota de honestidade: o bug estava no TESTE, não no produto — o custo
real medido foi 1 rodada vermelha + diagnóstico + fix no A-6. Mas o
mecanismo de aprovação não distingue: uma flaky de produto teria passado
pelo mesmo buraco.

## Regra candidata (detalhada no principal como regra nova 6)

**Ring close re-roda os testes NOVOS do anel de forma descorrelacionada**:
o runner identifica os arquivos de teste tocados no diff do anel e os
re-executa N vezes isolados (vitest aceita pathspec; N=5 custa segundos)
— idealmente intercalando com carga ou variando ordem. Falhou 1 de N →
anel não fecha. Cobre exatamente a classe: asserções novas sensíveis a
concorrência ganham amostra com variância de verdade antes do selo.

## Evidência

- Rodadas verdes do A-5: terminal da sessão (148/148 2x, inícios 22:36:44
  e ~3s depois; transcript `e336d9b1-...`).
- Estouro no A-6: terminal (Start at 22:42:45, `1 failed | 158 passed
  (159)`, stack apontando a comparação `new Date(sentadoEm) <=
  new Date(fechadaEm)` em `apps/realtime/test/cash.test.ts`).
- Asserção flaky e fix: `git show 6a9c029 -- apps/realtime/test/cash.test.ts`
  (introdução) e `git show 3768e37 -- apps/realtime/test/cash.test.ts`
  (troca por consistência resposta↔banco, com o comentário explicando o
  congelamento de `now()`).
- Registro no fechamento do A-6: `~/poker-club-os/CHECKPOINTS.md`, bloco
  A-6, item "Corrida fechar×sentar (herança A-5)".
