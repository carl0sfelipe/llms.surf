---
id: 2026-08-30-fallback-do-registry-aponta-endpoint-sus
titulo: fallback do registry aponta endpoint suspenso e rate limit temporario vira run morto
data: 2026-08-30
recorrivel: sim
regra: pendente
status: aberto
---

# fallback do registry aponta endpoint suspenso e rate limit temporario vira run morto

## Sintoma

Dispatch `webnext-02` (dogfooding 2026-08-30): o modelo principal
`cheaperinference/gpt-5.6-luna` bateu rate limit no meio do trabalho (447KB
de log, modelo produtivo). O runner sinalizou exit 2 corretamente, a cadeia
RF-08 assumiu e tentou o fallback `qwen38-flashnext-125b` — que aponta para
`http://127.0.0.1:8019/v1` (endpoint local da 3090, túnel Vast SUSPENDIDO).
O opencode ficou em retry mudo (`isRetryable: true`, "Unable to connect"),
o log parou de crescer, e o watchdog de silêncio (300s) matou o run inteiro
— com o trabalho parcial perdido fora de commit. Ledger: runner_exit 1,
oracle_status "falhou", 121s.

## Causa

Campo `fallback` do `model-registry.json` é estático e NÃO é validado contra
o estado vivo do provider no momento do encadeamento. O fallback foi
gravado quando o endpoint 3090 existia (2026-08-27) e a suspensão da Vast
(2026-08-30) não propagou para o registry. Resultado: a proteção contra
rate limit (RF-08) vira o PRÓPRIO mecanismo de morte — o run não falha
rápido, fica mudo. Evidência: cauda do log dispatch-webnext-02.log
("RATE LIMIT — exit 2" → "tentando: qwen38-flashnext-125b" → APIError
"Cannot connect ... 127.0.0.1:8019" repetido até o watchdog).

## Correção aplicada

- `model-registry.json`: `gpt-5.6-luna` com `fallback: []` (sem fallback
  melhor que fallback morto: exit 2 superfície na hora, operador decide).
- Correção estrutural pendente (proposta): `run-with-fallback.sh` deve
  smoke-check rápido (ou consultar usage-hub/observations) do próximo modelo
  da cadeia ANTES de entregar o run a ele; endpoint morto = pular e tentar o
  próximo, cadeia vazia = exit 2 limpo. Alternativa: `bin/pre-dispatch-check.sh`
  para o fallback no momento do dispatch.

## Auditoria da escala (mesma noite, depois da pergunta do dono)

Varredura de TODOS os fallbacks do registry (resolução por id OU hint):

- 7 FANTASMAS (nem id nem hint existe): `deepseek-v4-flash-free`
  (referenciado 4×: glm-5.2, deepseek-v4-flash-openrouter, claude-sonnet-5,
  deepseek-v4-pro), `mistral-small-4-119b-2603` (qwen38),
  `nemotron-3-super-120b-a12b` (glm-5.2, bare name — id real é
  `nvidia/nemotron-3-super-120b-a12b:free`), `nemotron-3-ultra-550b-a55b`
  (bare name — id real tem sufixo `-openrouter`). Classe: id renomeado no
  registry, fallback apodreceu silenciosamente.
- 1 ENDPOINT MORTO: ornith-1.5-35b-a3b → qwen38-flashnext-125b (túneis
  8019/8020 e IP público da Vast testados: todos mortos).
- 3 VIÁVEIS: deepseek/deepseek-v4-flash-0731 → deepseek-v4-flash-openrouter
  (registry, cloud vivo); gemini-3.6-flash → openrouter/google/gemma-4-26b-a4b-it:free
  (via hint, cloud vivo).

Conclusão: dos 11 refs de fallback, só 3 chains funcionariam hoje. Fantasma
falha rápido (exit 3 do runner); endpoint morto é o caso letal (retry mudo).
A correção estrutural proposta cobre os dois: validar ref E sanidade do
endpoint antes de entregar o run ao fallback.

## Pode acontecer de novo?

Sim — TODO modelo do registry cujo fallback aponte para provider suspenso/
morto tem a mesma bomba (checar: fallbacks para vast3090*/ornith em outros
entries). A correção aplicada fecha só o caso do luna. Família: regra 12
(comando sem teto), 42 (morte silenciosa), 24 (captura mente) — aqui o
watchdog salvou o teto, mas o trabalho parcial se perdeu; a lição adicional
é o runner falhar rápido quando o fallback não responde.
