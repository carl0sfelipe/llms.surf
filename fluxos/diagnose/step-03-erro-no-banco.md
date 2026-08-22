# Step 3: Erro no Banco

## REGRAS

- Chegou aqui porque **sessões existem no banco E erros estão gravados nas mensagens**.
- O erro está no banco de dados, NÃO aparece no stderr — `--print-logs` não mostra. Foi isso que tornou o sintoma opaco por horas no incidente de 2026-07-24.
- Você vai ler o erro da saída de `bin/diagnose-hang.sh` e classificá-lo.

## INSTRUÇÕES

### 1. Carregar estado

Leia o artefato apontado por `$DISPATCH_ARTEFATO`. Confirme que `status: in-progress`.

### 2. Extrair a mensagem de erro

Releia a seção 4 da saída de `bin/diagnose-hang.sh`. (Rode novamente se necessário, com o `model_id` se souber.)

```bash
bin/diagnose-hang.sh <model_id>
```

A saída mostra linhas como:

```
  ❌ 3x openrouter/groq/llama-3.3-70b-versatile [chat]
       429 Too Many Requests — rate limit exceeded
```

O formato é: `❌ <contagem>x <provider>/<modelo> [<mode>]` seguido da mensagem de erro.

### 3. Classificar o erro

Mapeie a mensagem de erro para uma causa conhecida:

| Padrão na mensagem | Conclusão | Explicação |
|--------------------|-----------|------------|
| `429` ou `rate limit` ou `Too Many Requests` | `rate-limit` | Provider devolveu rate limit. O dispatch não trata isso como erro fatal — a mensagem fica no banco mas o dispatch continua tentando. O sintoma de travamento é o usuário vendo "pendurado" enquanto as tentativas se acumulam. |
| `insufficient` ou `balance` ou `quota` ou `insuficiente` ou `saldo` | `saldo-insuficiente` | Saldo insuficiente no provider. O dispatch não pode prosseguir sem recarga. |
| `ContextOverflowError` ou `context overflow` ou `context_window` | `context-overflow` | O prompt base do opencode (sistema + ferramentas) não cabe no contexto do modelo. **Não é incapacidade do modelo** — é incompatibilidade com o harness. Confirmado em 2026-07-25 com groq/llama-3.3-70b-versatile (6K de contexto). O modelo pode ser perfeitamente capaz para outras tarefas, mas o prompt base do opencode exige mais contexto do que o modelo declara. |
| `timeout` ou `timed out` | `timeout` | O provider não respondeu dentro do limite de tempo. |
| Qualquer outro padrão | `erro-desconhecido` | Erro não catalogado. Inclua a mensagem original no `bloqueio`. |

### 4. Validar contexto do modelo (se aplicável)

Se o erro for `context-overflow` ou se você suspeitar de problema de contexto, rode a verificação específica (a seção 5 do `diagnose-hang.sh` já faz isso se você passar o model_id):

```bash
bin/diagnose-hang.sh <model_id>
```

Veja na seção 5 se o contexto declarado é menor que 16000. Se for, a conclusão `context-overflow` está confirmada.

### 5. Registrar e HALT

Atualize o frontmatter do artefato:

- `status`: `done`
- `conclusao`: a causa identificada (rate-limit | saldo-insuficiente | context-overflow | timeout | erro-desconhecido)
- `bloqueio`: descrição do erro encontrado (copie a mensagem original do banco)
- `evidencia`: "seção 4 de bin/diagnose-hang.sh"

Inclua no corpo do artefato a linha de erro exata como foi exibida pelo script.

Grave em disco e faça HALT.

## NEXT

Este passo termina em HALT. Nenhuma transição padrão.
