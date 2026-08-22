---
id: 2026-07-26-hermes-default-em-servidor-local-morto-d
titulo: hermes default em servidor local morto derruba sessao com erro sobre outro modelo
data: 2026-07-26
recorrivel: sim
regra: 34
status: promovido
interage_com: 18, 26
---

**Relação com a regra 18** (erro de provider não pode virar timeout mudo): a 34
reforça a 18 no mesmo eixo — mensagem de erro que aponta para a coisa errada. A
18 cobre o runtime (rate limit chegando como 124); a 34 cobre a config (default
morto chegando como erro sobre outro modelo). Nenhuma supera a outra: a 18 não
pega este caso porque não houve erro de provider, e sim eleição de fallback.

**Relação com a regra 26** (ausência só se provada): a 34 depende da 26. O
`preflight.sh` prova que o servidor local está fora do ar com `curl` ao
endpoint, em vez de deduzir do sintoma. Se um dia o check falhar, a 26 manda
dizer "não respondeu em 5s no endpoint X", não "não existe servidor".

**O que pode quebrar:** o `preflight.sh` lê `~/.hermes/config.yaml` por regex.
Mudança no formato da config do hermes derruba o check em silêncio (ele passaria
a não achar o bloco e a reprovar). Se isso ocorrer, o sintoma é o preflight
reclamar de config que está correta.


# hermes default em servidor local morto derruba sessao com erro sobre outro modelo

## Sintoma

`hermes -z "<prompt>"` abortou sem executar nada:

```
hermes -z: agent failed: Auxiliary compression model meta/llama-3.1-8b-instruct
has a context window of 16,000 tokens, which is below the minimum 64,000
required by Hermes Agent.
```

O erro nomeia `meta/llama-3.1-8b-instruct`, que não era o modelo pedido nem o
default configurado.

## Causa

Duas condições encadeadas.

1. `~/.hermes/config.yaml` tinha `model.provider: custom` com
   `base_url: http://localhost:8080/v1`. Servidor fora do ar:

   ```
   $ bash bin/with-timeout.sh 10 curl -s http://localhost:8080/v1/models
   (resposta vazia)
   ```

2. Sem o default, o hermes desceu para `fallback_providers`, cujo primeiro item
   era `nvidia / meta/llama-3.1-8b-instruct` (16k). Esse modelo foi eleito
   modelo de compressão auxiliar e reprovou no mínimo de 64k.

O erro exibido é sobre a consequência (2), não sobre a causa (1). Foi isso que
custou tempo de diagnóstico: a mensagem manda investigar o modelo errado.

## Correção aplicada

- `~/.hermes/config.yaml`: default passou a ser API free
  (`provider: opencode-zen`, `model: deepseek-v4-flash-free`), sem servidor
  local. Fallback de 16k removido. `auxiliary.compression` pinado com
  `context_length: 128000`. Backup em `~/.hermes/config.yaml.bak-20260726-121338`.
- `model-registry.json`: `cli_hints.hermes` adicionado a
  `deepseek-v4-flash-free` e `ling-3.0-flash-free`, com evidência do smoke test.
  Antes disso nenhum modelo tinha hint de hermes e o adapter sempre recusava
  com exit 3.
- `bin/check-cli-config.sh`: gate novo, agnóstico de CLI — roda
  `adapters/<cli>/preflight.sh` quando existe.
- `adapters/hermes/preflight.sh`: detecta base_url local fora do ar e
  compressão auxiliar não pinada, com o conserto no stderr.

Verificação:

```
$ source adapters/hermes/env.sh && bash bin/smoke-test.sh deepseek-v4-flash-free
✅ OK (5s) — disponível
$ HERMES_CONFIG=~/.hermes/config.yaml.bak-20260726-121338 bash adapters/hermes/preflight.sh
❌ hermes: model.base_url é local (http://localhost:8080/v1) e o servidor não responde.
```

## Pode acontecer de novo?

Sim. Vale para qualquer CLI, não só hermes: apontar o modelo default para um
servidor local torna o agente dependente de um processo que ninguém monitora, e
quando ele cai o erro que chega fala de outro modelo. O gate de config precisa
rodar antes de gastar tempo com o CLI.
