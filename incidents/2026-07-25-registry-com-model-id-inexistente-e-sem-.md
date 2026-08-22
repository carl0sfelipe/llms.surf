---
id: 2026-07-25-registry-com-model-id-inexistente-e-sem-
titulo: Registry com model id inexistente e sem provider observado/quantização
data: 2026-07-25
recorrivel: sim
regra: 20
status: promovido
---

# Registry com model id inexistente e sem provider observado/quantização

## Sintoma

Dois problemas, mesma raiz (o registry descreve o que a spec *disse*, não o que o provider *serve*):

1. `mistral-small-4-119b-2603` pendurava 40s+ sem emitir erro nenhum. Diagnostiquei como "free tier em fila" — **errado**.
2. O benchmark do dia comparou modelos sem registrar quem serviu nem em que precisão.

## Causa

**(1) O id não existe.** Catálogo real (`GET https://openrouter.ai/api/v1/models`, 345 modelos):

```
mistralai/mistral-small-2603
mistralai/mistral-small-3.2-24b-instruct
mistralai/mistral-small-3.1-24b-instruct
mistralai/mistral-small-24b-instruct-2501
```

Nenhum `mistral-small-4-119b-2603`. O id veio de `specs/free-model-ecosystem.md` e nunca foi conferido contra provider nenhum. Pior: recebeu `cli_hints.opencode` **sem smoke test passar**, violando o PRD 4.3 ("hint só após smoke test real"). Modelo inexistente **pendura** em vez de dar 404, e o sintoma imita rate limit.

**(2) Faltam campos.** O registry tem `provider` (declarado, de spec) e `verified_by` (o CLI, não quem serviu). **Não há campo de quantização.** Mas o dado existe e é decisivo — `GET /api/v1/models/<slug>/endpoints`:

```
mistralai/mistral-small-2603
  provider=Mistral   quant=unknown  ctx=262144
  provider=Venice    quant=fp8      ctx=256000
```

Mesmo id → provider diferente, **quantização diferente**, contexto diferente. Medir `suite_accuracy` sem registrar isso compara coisas distintas sob o mesmo nome, e explica variação de resultado entre rodadas.

## Correção aplicada

- `cli_hints` removido de `mistral-small-4-119b-2603`; campo `id_status` marca o id como NÃO-VERIFICADO, lista os candidatos reais e deixa `TODO-VERIFICAR`. **Não remapeado por chute** (regras 11.2 e 11.5).

Pendente: adicionar `provider_observed` e `quantization` ao schema, populados via API do provider quando existir.

**Limite conhecido:** o Zen (opencode) não publica quantização. Para `deepseek-v4-flash-free` — o único usável hoje — esses campos ficarão `unknown`, e isso precisa aparecer como `unknown` **explícito**, nunca como ausência silenciosa.

## Pode acontecer de novo?

**Sim.** 28 dos 31 modelos seguem com números herdados de spec e `verified_at` nulo — qualquer um pode ser id fantasma. E toda comparação futura sem quantização registrada repete o erro de medir maçã contra laranja.
