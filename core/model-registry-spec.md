# Schema — model-registry.json

Fonte: `specs/PRD-reformulacao-multi-cli.md` seção 4.3. Descreve os campos de cada entrada em `model-registry.json`, a fonte única de catálogo de modelos que substitui as tabelas duplicadas em `specs/free-model-ecosystem.md` e `specs/expanded-free-models.md`.

## Estrutura do arquivo

```json
{
  "$schema": "core/model-registry-spec.md",
  "version": 1,
  "models": [ { ... } ]
}
```

## Campos por modelo

| Campo | Tipo | Obrigatório | Descrição |
|-------|------|-------------|-----------|
| `id` | string | sim | Id do modelo, exatamente como aparece na spec de origem. Nunca inventado. |
| `provider` | string | sim | Provedor/canal (ex: `nvidia`, `groq`, `zen`, `qwen-token-plan`, `local`). |
| `tier` | string | sim | `free`, `token-plan`, `paid` ou `local`. |
| `accuracy` | number \| null | sim | Fração 0-1. `null` se a spec só dá um intervalo (ex: "50-60%") — não se aproxima um único número quando a fonte é uma faixa. |
| `latency_ms` | number \| null | sim | Latência em milissegundos. `null` quando a fonte mede em outra unidade incompatível (ex: ms/token para modelos locais) e não dá para converter sem inventar uma suposição de tamanho de resposta. |
| `context_window` | number \| null | sim | Janela de contexto em tokens (conversão direta de "64K" → 64000 etc). `null` se a fonte não informa contexto para esse modelo (ex: modelos de visão/áudio só descritos por nome). |
| `rate_limit` | string \| null | sim | Rótulo da spec de origem (`Leve`, `Moderado`, `Alto`, `Semanal`). `null` se a fonte não lista rate limit para esse modelo (ex: modelos pagos, visão). |
| `best_for` | array de string | sim | Casos de uso, extraídos da coluna "Melhor pra"/"Ideal p/"/"Descrição" da fonte. |
| `source` | string | sim | `specs/<arquivo>:<linha>` — rastreabilidade obrigatória de onde os números numéricos (`accuracy`, `latency_ms`, `context_window`) vieram. |
| `verified_at` | string (data) \| null | sim | Data do último smoke test real que validou os números. `null` na ausência de evidência — não se assume verificação. |
| `cli_hints` | objeto | sim | Mapa `<cli>: <hint>`. Em F1, só `opencode` é preenchido — os demais CLIs entram em fases futuras de Descoberta (PRD seção 7, Passo 0). Regra: `cli_hints` só é preenchido APÓS smoke test real passar naquele CLI. Ausência de hint = modelo indisponível ali, não presumir cobertura. |
| `fallback` | array de string | sim | Ids de modelos para tentar em cascata, na ordem descrita em `specs/free-model-ecosystem.md` seção 5.1/5.2. Array vazio quando a spec não descreve encadeamento explícito para esse modelo (não se infere cascata que o texto não afirma). |

## Regras anti-alucinação aplicadas ao registry

1. Nenhum modelo entra sem `source` rastreável (arquivo:linha real, verificado por leitura/grep do arquivo).
2. `verified_at` só é preenchido com evidência concreta (ex: registro real em `ledger/ledger.jsonl` com `finished_at`).
3. `fallback` só lista o que a seção 5.1/5.2 de `free-model-ecosystem.md` afirma explicitamente para aquele modelo — nunca cascata inferida por analogia.
4. `cli_hints` só recebe entradas de CLIs já testados. Em F1, isso é só `opencode`, já em uso ativo (ver `ledger/ledger.jsonl`).


## Campos de proveniência da medição (incidente incidents/2026-07-25-registry-com-model-id-inexistente-e-sem-.md)

Adicionados após o incidente `2026-07-25-registry-com-model-id-inexistente-e-sem-`.

| Campo | Onde | Significado |
|---|---|---|
| `provider` | raiz | provider **declarado** pela spec de origem. Não é evidência de quem serviu |
| `verified_by` | raiz | o **CLI** que executou a medição (opencode/hermes), não o provider |
| `measured.provider_observed` | measured | quem **realmente** serviu a requisição. `unknown` explícito quando o provider não publica |
| `measured.quantization` | measured | precisão dos pesos servidos (`fp8`, `fp16`, `unknown`). `unknown` explícito, nunca omitido |
| `id_status` | raiz | marca id não confirmado no catálogo real do provider, com candidatos e `TODO-VERIFICAR` |

**Por que importa:** o mesmo `id` roteia para backends diferentes. Medido em 2026-07-25 via `GET /api/v1/models/mistralai/mistral-small-2603/endpoints`:

```
provider=Mistral   quant=unknown  ctx=262144
provider=Venice    quant=fp8      ctx=256000
```

Provider, quantização **e** contexto diferem sob o mesmo nome. `suite_accuracy` sem esses campos compara coisas distintas e explica variação entre rodadas.

**Limite:** o Zen (opencode) não publica quantização — para `nemotron-3-ultra-free` os dois campos são `unknown`. Ausência silenciosa é proibida; `unknown` é a resposta honesta.
