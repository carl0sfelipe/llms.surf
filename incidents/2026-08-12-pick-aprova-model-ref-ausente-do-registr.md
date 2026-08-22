---
id: 2026-08-12-pick-aprova-model-ref-ausente-do-registr
titulo: pick aprova model ref ausente do registry e batch queima teto em attempts de 0s
data: 2026-08-12
recorrivel: nao
regra: mecanismo
status: fechado
---

# pick aprova model ref ausente do registry e batch queima teto em attempts de 0s

## Sintoma

Batch baseline da release v3.5 (batch-20260812-142919, 2 itens) fechou com
`timeout 600 / timeout 600`. No log de cada item: attempts do gauntlet
falhando em **0s** (`❌ oráculo FALHOU | 0s | tentativa N/3`), e o log do tier
(`.dispatch/logs/baseline-bytes-tier-2.log`) com uma única linha:

    modelo deepseek-direct/deepseek-chat ausente do model-registry.json

Os 600s de cada item foram queimados quase inteiramente pelos critics do
gauntlet (2 chamadas × teto de 300s, contra o zen que estava rate-limitado),
não por trabalho de modelo.

## Causa

Duas camadas, cada uma com evidência própria:

1. **O orquestrador inventou o ref.** `pick --tiers` recebeu
   `deepseek-direct/deepseek-chat` — ref composto de cabeça (o vocabulário
   certo no registry era `deepseek/deepseek-v4-flash-direct`, com
   `cli_hints.opencode: deepseek-direct/deepseek-v4-flash`). Regra 11.2 já
   dizia: o catálogo é o registry, nunca se inventa id.

2. **`pick` não vetava ref fora do registry.** Em `bin/usage-hub.py::pick`,
   `registry_entry(ref)` retornava `None` e `(entry or {}).get("id_status")`
   virava `""` — que não casa com nenhum `DEAD_STATUS` — então o ref seguia
   para o `recommend` do provider (inferido por prefixo) e era APROVADO.
   Evidência: `pick --tiers "deepseek-direct/deepseek-chat …" --json`
   retornava `picked: deepseek-direct/deepseek-chat` antes do fix; o runner
   (que resolve pelo registry) rejeitava o mesmo ref em ~0s.

O par "pick aprova / runner rejeita em 0s" é a mesma família do incidente
2026-08-12-dispatch-escalate-chama-opencode-cru-sem (id inválido → falha
instantânea disfarçada de modelo ruim), agora na porta de entrada do hub.

## Correção aplicada

- `bin/usage-hub.py::pick`: `entry is None` → skip com motivo explícito no
  trail (`ausente do model-registry (runner rejeitaria — regra 11.2)`).
  Verificado: o mesmo `pick` que aprovava o fantasma agora o pula e escolhe
  `deepseek/deepseek-v4-flash-direct`.
- `tests/test-usage-hub.sh`: caso novo `pick pula ref ausente do registry`
  (16/16 pass).

## Pode acontecer de novo?

Não como classe: qualquer ref fora do registry agora é vetado na entrada do
`pick` com motivo no trail — o erro humano (inventar ref) continua possível,
mas morre no primeiro gate com mensagem clara, em vez de queimar 2×600s de
batch. Coberto pela regra 11.2 existente (catálogo = registry); mecanismo é
a aplicação dela no hub. Sem regra nova.
