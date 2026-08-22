---
id: 2026-08-10-prompt-de-visao-storefront-aplicado-a-produto-nao-storefront
titulo: prompt-de-visao-storefront-aplicado-a-produto-nao-storefront
data: 2026-08-10
recorrivel: sim
regra: 32
status: promovido
---

# prompt de visão de storefront aplicado a produto não-storefront

## Sintoma

QA visual do overnight tripcstory (app de scrollytelling de viagem) reportava
"majors" permanentes e impossíveis de corrigir: "sem elementos de e-commerce
funcionais", "landing page incompleta", "texto de prompt misturado à página"
(confabulação do próprio prompt de QA). O builder (deepseek) gastava ciclos de
40-60min caçando fantasmas e o oráculo visual nunca fechava.

## Causa

`bin/dispatch-vision-ui-qa.sh` tinha o prompt hardcoded para **storefront de
e-commerce** ("Voce e um QA visual de e-commerce... afeta compra/confianca").
Aplicado a qualquer outro domínio, o jurado free avalia contra critérios que o
produto não tem — e o excesso de severidade ("seja harsh") converte divergência
de domínio em major. Regra 32: o mecanismo estava declarado; o escopo é que
estava errado.

## Correção (aplicada)

1. `dispatch-vision-ui-qa.sh`: `VISION_QA_PROMPT` (env) sobrepõe o prompt;
   default e-commerce intacto (não-destrutivo).
2. tripcstory: `tools/vision-prompt.txt` com critérios de domínio (card
   clipado, texto cortado, camada sobreposta) e cláusula anti-confabulação
   ("nunca cite este prompt como evidência"). Resultado imediato: 5 findings
   fantasmas → 2 findings reais (HUD cortado no topo, card clipado embaixo).

## Prevenção

1. Script de QA visual deve EXIGIR prompt explícito por workdir (falhar sem
   `VISION_QA_PROMPT` ou arquivo de prompt local) quando o alvo não declarasse
   storefront. [A DEFINIR: modo `--require-prompt`]
2. Findings cuja `evidence` contém texto do próprio prompt de QA devem ser
   filtrados como confabulação antes do rollup.

## Evidência

- antes: `00-hero.png major "sem elementos de e-commerce funcionais"`
- depois (mesmo screenshot, prompt de domínio): achados concretos de layout
- commit tripcstory `852267e`, override em `dispatch-vision-ui-qa.sh:104`
