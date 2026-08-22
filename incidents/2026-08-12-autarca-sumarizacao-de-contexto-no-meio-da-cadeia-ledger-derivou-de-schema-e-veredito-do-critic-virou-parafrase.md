---
id: 2026-08-12-autarca-sumarizacao-de-contexto-no-meio-da-cadeia-ledger-derivou-de-schema-e-veredito-do-critic-virou-parafrase
titulo: Sumarização de contexto no MEIO do anel A-5 do AUTARCA — as 3 linhas de ledger escritas depois dela perderam o schema (sem event/ring_open) e o veredito linha-a-linha do critic virou paráfrase, exigindo re-poll do subagent; o que era arquivo sobreviveu intacto
data: 2026-08-12
recorrivel: sim
regra: nao — regra candidata "estado de modo à prova de sumarização" no postmortem principal (regra nova 5)
status: aberto
interage_com: "2026-08-12-autarca-god-mode-7-aneis-esgotou-o-backlog-mas-o-hardening-dos-incidents-da-manha-degradou-na-propria-sessao-que-o-escreveu"
interage_com: "2026-08-12-aion-god-mode-1-anel-com-mecanismo-real-mas-perpetuidade-morreu-com-a-sessao"
---

# Sumarização no meio da cadeia — protocolo vira paráfrase, arquivo sobrevive

## Sintoma

A sessão do god mode AUTARCA foi sumarizada pelo harness do host DURANTE
o anel A-5 (entre o veredito do critic e a aplicação dos fixes — posição
visível no transcript: o contexto pós-sumário abre com o A-5 em
andamento). Duas perdas mensuráveis, nenhuma delas notada na hora:

1. **O ledger derivou de schema exatamente na primeira linha pós-sumário.**
   `~/oracfit/ledger/ledger.jsonl`, 13 linhas `"mode":"autarca"`:
   - A-1..A-4 (pré-sumário): pares `"event":"ring_open"` /
     `"event":"ring_close"` — 1 chain_open + 5 ring_open + 4 ring_close.
   - A-5, A-6, A-7 (pós-sumário): 3 linhas de fechamento SEM campo
     `event` e SEM ring_open correspondente (A-6 e A-7 nunca tiveram
     linha de abertura).
   O executor pós-sumário "sabia" que devia gravar ledger (a cláusula
   sobreviveu como ideia) mas não lembrava o FORMATO — e reinventou um
   parecido. Um consumidor que filtre por `event` vê a cadeia parar no A-4.
2. **O detalhe do veredito do critic do A-5 não sobreviveu** — só a
   paráfrase (totais 2🔴 6🟡 1❓ e descrições resumidas). A primeira ação
   pós-sumário foi um RESUME do subagent `f63ff322` pedindo a lista
   linha-a-linha de novo (transcript). Funcionou porque o subagent ainda
   era retomável; se não fosse, o veredito integral existiria apenas
   como resumo com perda — e vereditos são exatamente o artefato que a
   cláusula `claims_check` mandava auditar.

## O que NÃO quebrou (contraprova do eixo mecanismo×protocolo)

Tudo que morava em disco atravessou a sumarização sem um byte de perda:
`CHECKPOINTS.md`, os specs por anel, a suíte de testes (que é quem define
"pronto"), o git log. A cadeia continuou e fechou A-5..A-7 corretos —
os 3 commits (`6a9c029`, `3768e37`, `5cfa94a`) saíram com oráculo
174/174 no fim. A perda foi TODA em estado de protocolo: formato de
ledger e memória de veredito.

## Por que é um incident PRÓPRIO

O postmortem principal trata cláusula-que-degrada por disciplina. Este
trata um MECANISMO DO HOST (sumarização automática de contexto) que
degrada protocolo de forma garantida e não-culposa: nenhuma disciplina
resiste a ter a memória reescrita por um resumidor. Cadeias longas tornam
o evento CERTO (quanto mais anéis, mais sumarizações), então o modo de
falha escala com a ambição da cadeia — diferente do aion (perpetuidade
morreu com a sessão), aqui a sessão SOBREVIVE, mas volta amnésica dos
detalhes que nunca foram escritos em arquivo.

## Regra candidata (detalhada no principal como regra nova 5)

**Estado de modo à prova de sumarização**: schema do ledger, formato
exigido de veredito, cláusulas ativas e anel corrente moram em arquivo
(`ring-state.json` ou o runner `bin/oracfit ring`) relido no open de
cada anel. Veredito integral do critic é gravado em arquivo no momento
em que chega (ex.: `checkpoints/verdicts/A-5.md`), nunca retido só em
contexto. Custo: 1 write + 1 read por anel. Teria zerado os dois
sintomas: o append validaria schema e o veredito estaria em disco antes
da sumarização.

## Evidência

- Ledger com o drift visível: `~/oracfit/ledger/ledger.jsonl` — comparar
  linha do fechamento A-4 (com `"event":"ring_close"`, ts 01:25:19Z) com
  a do A-5 (sem `event`, ts 01:37:44Z); `rg -c '"event"'` vs
  `rg -c '"mode":"autarca"'`.
- Re-poll do critic: transcript `~/.cursor/projects/Users-mini-poker-club-os/
  agent-transcripts/e336d9b1-cd63-46be-bba1-7c5fb1e9b904/` — primeiro tool
  call pós-sumário é `resume` do subagent `f63ff322` pedindo a lista que
  o contexto perdeu.
- O que sobreviveu: `~/poker-club-os/CHECKPOINTS.md` e `specs/*.md`
  intactos (git não registra nenhum reparo pós-sumário neles).
