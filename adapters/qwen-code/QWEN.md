# Adapter qwen-code

> ⚠️ **EXPERIMENTAL.** A CLI `qwen` não existe neste host — `command -v qwen` não retorna nada ([`DISCOVERY.md`](DISCOVERY.md), Passo 0). Conforme PRD seção 7, adapter sem CLI disponível é marcado experimental, e nenhuma flag pode ser documentada sem `--help` real (regra 11.1).

## Caminho suportado hoje

Modelos Qwen são acessíveis via **opencode**, pelo campo `cli_hints.opencode` do `model-registry.json`. Isso é coerente com o PRD seção 4.4: qwen code é **orquestrador**; o executor delega ao opencode.

```bash
source adapters/opencode/env.sh
bash bin/smoke-test.sh <model_id_qwen_do_registry>
```

Consulte quais ids Qwen existem no registry — nunca invente id (regra 11.2):

```bash
python3 -c "import json;[print(m['id'], m.get('cli_hints',{})) for m in json.load(open('model-registry.json'))['models'] if 'qwen' in m['id'].lower()]"
```

## Se/quando a CLI `qwen` existir

Ordem obrigatória (PRD seção 7, Passo 0 generalizado):

1. `qwen --help > adapters/qwen-code/DISCOVERY.md` (output bruto, com data e comando)
2. Preencher [`capabilities.env`](capabilities.env) citando as flags reais do DISCOVERY
3. Implementar a tradução em [`runner.sh`](runner.sh) — hoje ele falha com `exit 3` de propósito
4. Adicionar `cli_hints.qwen` no `model-registry.json` **só após smoke test passar** (PRD 4.3)

## Token plan (RF-05.2)

[`token-plan.sh`](token-plan.sh) implementa o semáforo semanal de `specs/free-model-ecosystem.md` seção 5.3, independente da CLI:

```bash
bash adapters/qwen-code/token-plan.sh status          # exit 0 = tem saldo, 4 = exausto
bash adapters/qwen-code/token-plan.sh consume 12000
bash adapters/qwen-code/token-plan.sh reset
```

Estado em `.dispatch/qwen-token-plan.json`; limite via `TOKEN_PLAN_LIMIT` (default 500000, de `free-model-ecosystem.md:206`).

## Capacidades

Todas `0` em [`capabilities.env`](capabilities.env) — sem `--help` real, nenhuma capacidade pode ser afirmada. `bin/` recusa a operação com `exit 3` em vez de tentar flag inventada (PRD seção 4.5: nunca degradar em silêncio).
