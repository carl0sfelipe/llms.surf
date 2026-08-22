# Step 3.5: Escalation Loop (Mode 2)

## O que é

O loop entre "executa" e "verifica". No dispatch 1.0, o modelo executava e o
orquestrador verificava — sem retry, sem escalonamento. No 2.0, o próprio modelo
roda o oráculo e se auto-corrige. Mas e quando ele NÃO consegue?

O escalation loop resolve: **detecta travamento e escala pro próximo tier.**

## Os 3 modos

| Mode | Tiers | Quando usar |
|------|-------|-------------|
| 1 | Flash only | Transformações repetitivas, path único, padrão conhecido |
| 2 | Flash → DeepSeek V4 Pro | Default. Mesmo family, contexto acumulado, mais capacidade |
| 3 | Flash → DeepSeek V4 Pro → Opus | Tarefas complexas, multi-arquivo, julgamento |

## O loop (entre step-03 e step-04)

```
┌─────────────────────────────────────────────────────────────┐
│  ORACLE CHECK (antes de tudo)                               │
│  Se já passa → early exit, nada a fazer                     │
└────────────────────────┬────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  TIER N (ex: Flash)                                         │
│                                                             │
│  ┌─ attempt 1 ──────────────────────────────────────────┐   │
│  │ dispatch → run oracle                                │   │
│  │   ✅ passou → DONE (exit 0)                          │   │
│  │   ❌ falhou → capture error signature                │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ▼                                    │
│  ┌─ attempt 2 ──────────────────────────────────────────┐   │
│  │ dispatch com contexto do erro anterior               │   │
│  │ run oracle                                           │   │
│  │   ✅ passou → DONE                                   │   │
│  │   ❌ falhou → compare signatures                     │   │
│  │      similar? consecutive_similar++                  │   │
│  └──────────────────────────────────────────────────────┘   │
│                         ▼                                    │
│  ┌─ attempt 3 ──────────────────────────────────────────┐   │
│  │ ...                                                  │   │
│  │   ❌ + 3 erros similares → TRAVADO → ESCALA          │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  Condições de escala:                                       │
│    - max_per_tier tentativas esgotadas                      │
│    - N erros consecutivos similares (default: 3)            │
│    - rate-limit persistente (exit 2)                        │
│    - quota exausta (exit 4)                                 │
└────────────────────────┬────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  TIER N+1 (ex: DeepSeek V4 Pro)                             │
│  Mesmo loop, mesmo spec + contexto acumulado                │
│  Se falhar → TIER N+2 (Opus) ou BLOCKED                     │
└─────────────────────────────────────────────────────────────┘
```

## Detecção de travamento

"Travado" = o modelo produz o MESMO erro repetidamente. Não é que ele tenta
coisas diferentes e falha — ele está preso num loop.

Métrica: **similaridade de assinatura do erro.** A assinatura é a saída do
oráculo (primeiras 20 linhas). Se 3 assinaturas consecutivas são ≥70% similares
(mesmas linhas), o modelo está travado.

```
attempt 1: "grep: 4 refs restantes" → signature A
attempt 2: "grep: 4 refs restantes" → signature A (similar! consecutive=2)
attempt 3: "grep: 4 refs restantes" → signature A (similar! consecutive=3) → ESCALA
```

vs. progresso real:
```
attempt 1: "grep: 12 refs restantes" → signature A
attempt 2: "grep: 4 refs restantes"  → signature B (diferente! consecutive=1)
attempt 3: "grep: 0 refs, tsc erro"  → signature C (diferente! consecutive=1)
→ Não escala, continua tentando (está progredindo)
```

## Quem verifica o quê

| Verificação | Quem faz | Como |
|-------------|----------|------|
| "O trabalho foi feito?" | Oráculo (script) | Comando na spec, exit 0/1 |
| "O modelo está travado?" | dispatch-escalate.sh | Similaridade de assinaturas |
| "Devo escalar?" | dispatch-escalate.sh | Regra: N similares OU max tentativas |
| "Qual próximo tier?" | dispatch-escalate.sh | Lista fixa: flash → pro → opus |
| "O resultado final é bom?" | Oráculo (de novo) | Mesmo comando, no final |

Nenhum modelo verifica outro modelo. O oráculo é código. A decisão de escalar
é código. Modelos só executam.

## Contexto entre tentativas

Quando o oráculo falha, o tratamento depende de quantas falhas:

**Tentativa 1 falhou → contexto bruto:**
```markdown
## Contexto de falha (tentativa 1)
O oráculo falhou com esta saída: [saída do oráculo]
Corrija o que causou esta falha e tente novamente.
```

**Tentativa 2 falhou → refinamento do orquestrador:**
O script faz uma chamada META ao flash (não executor, diagnosticador):
- Input: spec original + erro do oráculo + últimas 30 linhas do log
- Output: 5 linhas de instrução imperativa de correção
- Custo: ~$0.001, ~5s

```markdown
## Correção do orquestrador (OBRIGATÓRIO seguir)
- O arquivo X deve ser criado em /caminho/absoluto/Y
- Não use sub-agents, faça direto
- O oráculo espera Z, não W

Siga as instruções acima EXATAMENTE. Não investigue, não use sub-agents. Execute direto.
```

**Tentativa 3 falhou → escala pro próximo tier** com o pacote completo:
spec original + erro 1 + erro 2 + refinamento do orquestrador.

O Pro recebe TUDO — não começa do zero.

## Uso

```bash
# Mode 1: só Flash (o que já provamos que funciona)
bin/dispatch-escalate.sh /tmp/spec.md minha-task --mode 1 --workdir /path/to/repo

# Mode 2: Flash + DeepSeek V4 Pro (default)
bin/dispatch-escalate.sh /tmp/spec.md minha-task --workdir /path/to/repo

# Mode 3: Flash + Pro + Opus
bin/dispatch-escalate.sh /tmp/spec.md minha-task --mode 3 --workdir /path/to/repo

# Custom: 5 tentativas por tier
bin/dispatch-escalate.sh /tmp/spec.md minha-task --mode 2 --max-per-tier 5
```

## Ledger

Cada dispatch-escalate grava uma linha em `.dispatch/logs/escalate-ledger.jsonl`:

```json
{"task_name":"debrand-sdk","mode":2,"result":"success","tier":"flash","model":"openrouter/deepseek/deepseek-v4-flash","attempt":1,"duration_s":62,"total_s":62,"runner_exit":0,"oracle_exit":0}
{"task_name":"tarefa-dificil","mode":2,"result":"success","tier":"pro","model":"openrouter/deepseek/deepseek-v4-pro","attempt":2,"duration_s":180,"total_s":420,"runner_exit":0,"oracle_exit":0}
{"task_name":"tarefa-impossivel","mode":3,"result":"blocked","tiers_used":3,"total_s":900,"last_error":"tsc: 14 errors"}
```

Com 20+ registros, o `dispatch-report.sh` responde:
- "Flash resolve X% das tasks sozinho"
- "Pro é necessário em Y% dos casos"
- "Tasks que precisam de Opus têm padrão Z"

## Relação com o dispatch 2.0

```
dispatch 1.0:  spec → modelo → "log não vazio? ok"
dispatch 2.0:  spec → gate → modelo → oráculo → ledger
dispatch 2.1:  spec → gate → modelo → oráculo → [loop de escalonamento] → ledger
               ↑                                                              ↑
               check-spec.sh                                    escalate-ledger.jsonl
```

O Mode 2 É o dispatch 2.0 + o loop. Não é um sistema separado — é a peça que
faltava entre "oráculo falhou" e "bloqueado, desista".
