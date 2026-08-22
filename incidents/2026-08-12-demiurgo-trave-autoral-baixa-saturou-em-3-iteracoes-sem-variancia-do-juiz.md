---
id: 2026-08-12-demiurgo-trave-autoral-baixa-saturou-em-3-iteracoes-sem-variancia-do-juiz
titulo: DEMIURGO (god mode v3.5) satélite — oráculo congelado porém AUTORAL saturou em 3 iterações (65/80→78/80) com baseline já em 8.1, respostas simuladas em vez de agente real, e ganhos de 1–2 pontos em 80 aceitos sem nenhuma variância de juiz medida
data: 2026-08-12
recorrivel: sim
regra: nao — 4 regras candidatas para a v4 no corpo (todas novas; evidência só desta sessão)
status: aberto
interage_com: "2026-08-12-demiurgo-god-mode-convergiu-sem-reversao-mas-o-unico-mecanismo-era-o-sha256-da-trave"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-07-26-spec-sem-clausula-anti-invencao-gera-num"
---

# DEMIURGO satélite — validade do oráculo (não confundir com a falha de contrato do principal)

## Contexto

O postmortem principal do demiurgo trata de falha de CONTRATO (spec que
declara mecanismos inexistentes). Este satélite trata de falha de VALIDADE:
mesmo que todos os mecanismos existissem, o que o oráculo mede não sustenta
a conclusão "a skill melhorou". Separado porque a correção é outra — não é
runner/ledger/hook, é desenho de eval.

Números do run (fontes: `checkpoints/checkpoint-0{0..3}.md`, branch
demiurgo do tdah-loops-repo): baseline 65/80 (8.1), it. 01 75/80 (+1.25 de
média), it. 02 77/80 (+0.25), it. 03 78/80 (+0.125, declarado 9.8 por
arredondamento de 9.75). Trave: 8 casos (`wc -l evals/casos.jsonl` → 8),
5 dimensões e 6 hard-fails (`rg -c` na rubrica), congelada às 16:27
(commit `df83fac`), escrita entre 16:21 e 16:27 pelo orquestrador.

## Sintomas (com evidência e classe)

1. **Trave autoral** (classe: desenho de eval, sem mecanismo possível de
   auto-defesa). Os 8 casos e a rubrica foram escritos pelo mesmo frontier
   que orquestrou o run, minutos antes do congelamento (16:21→16:27,
   `df83fac`), sem validação externa de dificuldade. O sha256 impede mover
   a trave — não impede a trave nascer na altura que o chutador alcança.
   Evidência de trave baixa: a skill original pontuou 9–10 em 7 dos 8 casos
   da baseline (`checkpoint-00.md`); o único zero veio do único gatilho que
   a skill nem mencionava (H5/cron).
2. **Saturação em 3 iterações e ~5 minutos** (classe: esgotamento do
   caso-set). 78/80 no checkpoint-03 (commits 16:35→16:40); os 2 pontos
   restantes (D3=1 em `pivo-com-entrega-aberta` e `hiperfoco-na-entrega`)
   foram diagnosticados pelo próprio executor como "falha de execução
   pontual, não gap de texto da skill" — ou seja, o oráculo não tinha mais
   nada a medir. A parada foi rotulada "convergência"; o rótulo honesto
   seria "oráculo saturado".
3. **Ganhos aceitos sem variância medida** (classe: estatística ausente).
   It. 02 = +2 pontos em 80; it. 03 = +1 ponto em 80. O juiz é um LLM
   não-determinístico; a baseline nunca foi re-julgada, então não existe
   estimativa de σ do julgamento — ganhos dessa magnitude são
   indistinguíveis de ruído. O limiar de convergência (0.3) foi arbitrado
   pelo mesmo modelo, sem base em variância. Nenhum número do run tem barra
   de erro.
4. **Respostas simuladas, não agente real** (classe: validade externa nula
   por construção). A "fase de geração" escreve a resposta que um agente
   seguindo a skill DARIA — a skill candidata nunca foi instalada nem
   executada por um agente em sessão limpa. O eval mede "o modelo consegue
   redigir respostas conformes com o texto da skill na mão", não "a skill
   instalada muda o comportamento de um agente real". A melhoria pode ser
   real e mesmo assim não transferir.

## Causa raiz

**O congelamento garante consistência interna (a prova não muda), e o modo
tratou isso como se fosse validade (a prova mede o fenômeno certo, com
dificuldade suficiente e medição estável).** Consistência ≠ validade: o
demiurgo otimizou com precisão a propriedade errada — conformidade simulada
contra uma trave que o próprio otimizador escreveu e que ele esgotou em
três chutes.

## Regras candidatas para a v4 (todas novas)

1. **Calibração de trave antes do run abrir**: rodar a baseline; se ≥ 8/10
   (ou N% do teto), a trave é baixa por definição e o run NÃO abre — os
   casos voltam para endurecimento e re-congelamento com aprovação humana
   da nova trave. Cobre sintoma 1. Custo: 1 rodada de baseline + ~10 min de
   revisão humana de 8 casos.
2. **Variância como pré-condição do rótulo "convergência"**: re-julgar a
   baseline k≥2 vezes para estimar σ; iteração só é aceita se ganho > 2σ;
   sem σ medido, o run pode parar mas o rótulo obrigatório é "parado por
   limiar arbitrário", nunca "convergido". Cobre sintoma 3. Custo: +k
   rodadas de julgamento (no demiurgo, ~2×5 min de parede).
3. **Eval de skill contra agente real**: casos respondidos por sessão limpa
   com a skill candidata INSTALADA (sandbox de skills, ex. cópia de
   `~/.claude/skills/` de teste), não por simulação no contexto do
   executor. Cobre sintoma 4. Custo: 1 subagent por rodada com setup de
   sandbox (~minutos).
4. **Sinal de saturação explícito**: score ≥ 95% do teto com iterações
   restantes encerra o run com status `SATURADO — oráculo esgotado` (nunca
   "convergido") e dispara automaticamente a regra 1 do próximo run (trave
   mais dura, re-congelada, com aprovação humana). Cobre sintoma 2. Custo:
   1 condicional no protocolo/futuro runner.

## Evidência preservada

- Scores e vereditos por rodada: `~/tdah-loops-repo/checkpoints/checkpoint-0{0..3}.md`
  (commits `1677375`, `61f3141`, `151ee1c`, `5476346`).
- Trave e autoria/horários: `~/tdah-loops-repo/evals/` (commit `df83fac`,
  16:27); autoria do orquestrador na mesma conversa (transcript da sessão
  do coach, 2026-08-12, 16:21–16:27).
- Diagnóstico "falha de execução, não gap de texto" dos 2 pontos restantes:
  `checkpoints/checkpoint-03.md` + relato final do subagent executor.
- Contagens da trave: `wc -l evals/casos.jsonl` → 8; `rg -c '^\- \*\*H\d'
  evals/rubrica.md` → 6; `rg -c '^\| D\d' evals/rubrica.md` → 5.

## O que este incident PROVA pra v4

1. Trave congelada sem calibração externa mede a generosidade do autor, não
   a qualidade do artefato — e quando autor, otimizador e juiz são o mesmo
   modelo, a trave nasce alcançável.
2. Sem barra de erro, "média subiu" não é evidência: metade dos aceites
   deste run (+2 e +1 pontos em 80) está abaixo de qualquer σ plausível de
   um juiz LLM não re-amostrado.

## Pode acontecer de novo?

Sim — qualquer eval congelada escrita pelo próprio otimizador minutos antes
do run repete os 4 sintomas, e o formato "score subiu, zero hard-fail"
continuará parecendo vitória limpa em relatório. A recorrência só quebra
quando calibração de trave e variância medida forem pré-condições de abrir
e fechar o run (regras 1 e 2).
