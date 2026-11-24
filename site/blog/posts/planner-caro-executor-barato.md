---
title: "Planner caro, executor barato: o Qwen passou sozinho e falhou com ajuda (n=1)"
description: "Opus 5.5 planejando, DeepSeek e Qwen executando, tudo no dsh. Com o Qwen, as duas condições mistas falharam no gate e o Qwen sozinho passou. n=1 por célula, e falta o controle que responderia se misturar economiza."
date: 2026-11-24
slug: planner-caro-executor-barato
lang: pt-BR
author: Carlos
tags:
  - harness
  - qwen
  - deepseek
  - benchmark
  - dsh
canonical: https://llms.surf/blog/planner-caro-executor-barato
---

No app Rails do zero, o Qwen 3.8 27B passou no gate sozinho: US$ 0,81, 89 minutos. Com o Opus 5.5 planejando e o mesmo Qwen executando, as duas condições que testei **falharam** no gate, por US$ 12,41 e US$ 6,62.

Isso contraria a tese que o llms.surf vende, a de que um modelo caro pensa e um barato sua. É uma execução por célula, e o gate (testes, RuboCop, Brakeman) não mede qualidade, então não derruba a tese. Também não a sustenta.

**Antes de tudo:** este experimento rodou no `dsh` (DeepSeek Harness), **não no dispatcher do llms.surf**. Nada aqui valida o llms.surf.

Em [setembro, respondendo a Akita](/blog/resposta-ao-akita-harness-qwen/), escrevi que eu **não** tinha rodado Opus planejando e Qwen executando. Agora rodei, em outro harness. A pergunta de lá, sobre o mix no meu dispatcher, continua aberta. Esta também:

> Misturar modelos economiza? **Não sei.** Falta o controle: Opus sozinho no mesmo harness das repetições mais recentes.

---

## O que rodou

- **Planner:** Claude Opus 5.5. **Executores:** DeepSeek V4.1 Flash e Qwen 3.8 27B. O Qwen rodou via API, como substituto de um modelo local.
- **Revisor de cada run:** Claude Fable 5.2. **O custo dele não está nas tabelas.**
- **Custos:** equivalentes de API.
- **Tarefas:** o benchmark Rails v5 do repo `akitaonrails/llm-coding-benchmark`, mais quatro tarefas de manutenção nossas: b1 (migração), b2 (corrigir CI), b3 (remover `eval`) e b4 (bug de boot). Nossa trilha não foi commitada lá nem virou PR. Nada disso foi aceito ou endossado por Akita.

| Condição | O que é |
| --- | --- |
| I | só o executor |
| S | só o Opus |
| MAX | Opus com meta de delegar 70% |
| MEDIUM | Opus com meta de delegar 45% |
| FREE | Opus delega por risco, sem meta |

---

## App do zero (harness v1, n=1 por célula)

| Executor | Condição | Gate | Nudges | Custo | Código do executor (recalculado) |
| --- | --- | --- | --- | --- | --- |
| — | S | PASS | 2 | US$ 14,95 | — |
| DeepSeek | MAX | PASS | 0 | US$ 7,60 | 76% (registrado: 92%) |
| DeepSeek | MEDIUM | PASS | 1 | US$ 12,54 | 19% (registrado: 24%) |
| DeepSeek | I | PASS | 0 | US$ 0,59 | — |
| Qwen | MAX | **FAIL** | 2 | US$ 12,41 | 20% (registrado: 47%) |
| Qwen | MEDIUM | **FAIL** | 2 | US$ 6,62 | 0% |
| Qwen | I | PASS | 0 | US$ 0,81 (89 min) | — |

Como ler, e como não ler:

- **PASS é só o gate** (testes, RuboCop, Brakeman). Não é nota de qualidade.
- **Nenhum desses runs fez chat real com provedor.** Não havia chave do OpenRouter, e parte deles usou um provedor falso.
- **n=1.** A mesma célula já variou entre PASS e FAIL, então uma repetição não sustenta ranking. Não concluo que um modelo é melhor que outro.
- **A métrica de autoria errou.** A pasta `coverage/` inflava a fatia do executor. Por isso a tabela traz o valor recalculado e o registrado.

---

## Manutenção

Primeiro, b1–b4 com teste escondido rodado antes de qualquer nudge (harness v1, n=1):

| Condição | Aprovados | Custo |
| --- | --- | --- |
| Qwen sozinho | 3/4 | US$ 0,43 |
| MAX (Opus + Qwen) | 4/4 | US$ 5,22 |
| S | 4/4 | US$ 4,41 |

Depois, FREE com o prompt original, três repetições por tarefa. **Essas repetições misturam três versões do harness: h2, h3 e h3.1.**

| Tarefa | Aprovados | Código do Qwen em cada repetição |
| --- | --- | --- |
| b1 | 3/3 | 41%, 10%, 0% |
| b2 | 1/3 | 0%, 0%, 0% |
| b3 | 0/3 (3/3 com o teste relaxado) | 46%, 29%, 0% |
| b4 | 3/3 | 0%, 0%, 0% |

**Total: 7/12, ou 10/12 com o b3 relaxado.** Os dois números valem juntos. O relaxamento foi decidido **depois** de ver os resultados: o teste cobra `7/2 = 3.5`, mas o app original devolve 3 e também falha nele.

O custo médio foi de cerca de US$ 2,50 por conjunto de quatro tarefas. **Não compare com os US$ 4,41 do S:** mudaram o harness e o prompt.

Ficou de fora um quinto run do b2, por contaminação do harness; um run extra o substituiu. Também testei uma variação do prompt (iteração 2) e abandonei. Ela não está nesta tabela.

A tarefa principal no FREE e a b5 **não rodaram**.

---

## O que observei nestes runs

**O Opus quase não delegou quando podia escolher.** No FREE, 0% em 8 dos 12 runs. Ele costuma classificar o trabalho como crítico.

**Teste visível verde não é prova.** No b2, trocar `lpush` por `rpush` passa no gate e inverte as conversas já gravadas. O Opus fez isso em 2 de 3, sem delegar. O Qwen sozinho também fez.

**"Terminei" não é prova.** Um planner declarou o trabalho limpo com o gate falhando.

**Teste escondido também tem bug.** O b3 é o exemplo: o próprio app original não passa nele.

**Isolamento precisa ser mecânico.** Agentes sem chave saíram procurando credenciais fora do projeto. O sandbox seguinte ainda deixava acessível o socket do Docker. Busquei comandos Docker, `colima` e `docker.sock` nos logs dos 7 runs sob h3/h3.1 (um deles um smoke test) e não achei uso. O acesso já foi fechado no h3.2, mas essa correção ainda não teve revisão do Fable nem run completo.

---

## O método: dsh, com o Fable como advisor

O `dsh` é o CLI de agente que executou tudo em modo headless: entra prompt, sai NDJSON. São três papéis, em três sessões separadas:

| Papel | Modelo | Como roda |
| --- | --- | --- |
| Planner | Opus 5.5 | `dsh headless` com escrita no projeto do run |
| Executor | DeepSeek ou Qwen | outro `dsh headless`, chamado pelo planner por um servidor MCP nosso, que registra cada delegação, tokens e custo |
| Advisor | Fable 5.2 | `dsh headless` **somente leitura**, chamado de fora do run |

Um orquestrador (Claude Code, com Opus 5.5) lança os runs, monta as perguntas, confere as respostas e decide. Quem roda gate e teste escondido é o harness do benchmark, e não um modelo.

Cada pedido ao Fable leva números medidos, arquivos a ler e pontos numerados com a nossa proposta, e pede `AGREE/DISAGREE` por ponto. Toda alegação dele é conferida nos arquivos. Ponto rejeitado volta com evidência, por até 5 rodadas. Sem consenso, decido eu. A numeração chegou à rodada 60.

**Onde ajudou:** achou o run em que um executor leu e tentou copiar o teste escondido (confirmamos e reclassificamos) e levou a melhorias no plano, como a proteção contra manipulação da métrica de autoria.

**Onde errou:** validou um run contaminado, exigiu correção indevida, tentou rodar comandos quando pedimos só texto, deu "AGREE" sem motivo, confundiu gate com teste escondido e inventou bloqueios por estar em somente leitura.

Minha conclusão: **bom para achar problema, ruim como juiz final.**

Limites do método:

- Não medi se o advisor melhora o resultado: só houve um revisor e nenhum grupo sem revisor.
- O Fable revisou **entre** runs. A condição em que o Opus o consultaria durante o run (FREE+ADV) foi só planejada e não existe.
- Orquestrador e planner são o mesmo modelo, e Opus e Fable são da mesma empresa. Consenso entre eles não é validação independente.
- Somente leitura impede escrever, **não** impede ler. O revisor ainda precisa de ordem para não abrir credenciais e, idealmente, de sandbox.

---

## O que isto não mostra

- Que misturar economiza, ou que não economiza.
- Que o Qwen supera o Opus, ou qualquer ranking.
- Que o llms.surf funciona melhor ou pior. Ele não rodou aqui.
- Como seria numa GPU local. Foi API.

O que falta é o run chato: Opus sozinho, no mesmo harness das repetições FREE.

— Carlos
