# Step 4: Resposta Perdida

## REGRAS

- Chegou aqui porque **sessões existem no banco mas NENHUM erro foi gravado**.
- O dispatch aparenta travado, mas pode ser que a resposta chegou em um campo diferente ou a captura do output está incorreta.
- Você vai investigar causas conhecidas de "resposta invisível".

## INSTRUÇÕES

### 1. Carregar estado

Leia o artefato apontado por `$DISPATCH_ARTEFATO`. Confirme que `status: in-progress`.

### 2. Verificar campo de reasoning

Alguns modelos de reasoning (como DeepSeek R1, QwQ, e variantes) retornam o conteúdo em `reasoning_content` em vez de `content`. O dispatch pode não estar lendo esse campo.

A seção 4 de `bin/diagnose-hang.sh` lista as respostas de assistente no período. Releia a saída — se não há erros, o banco tem respostas, mas podem estar em campo não esperado.

Para investigar, rode o diagnóstico com mais contexto:

```bash
bin/diagnose-hang.sh <model_id>
```

Se o modelo for de reasoning (ex: contém "deepseek", "qwq", "reasoning" no nome), considere que a resposta pode estar em `reasoning_content`.

Ação:
- Se o modelo é de reasoning: **HALT** com `conclusao: resposta-em-reasoning-content`, `bloqueio: "modelo de reasoning retornou resposta em reasoning_content, não em content — dispatch pode não estar lendo o campo"`
- Se o modelo não é de reasoning: prossiga

### 3. Verificar captura de output

O problema pode estar no pipeline de captura da resposta — o output foi gerado mas não foi corretamente registrado ou exibido.

Execute:

```bash
bin/session-health.sh
```

Este script verifica a saúde das sessões recentes. Interprete a saída:

| Indicador | Ação |
|-----------|------|
| Sessões marcadas como `completed` sem output registrado | **HALT** com `conclusao: captura-output-incorreta`, `bloqueio: "sessão completou mas output não foi capturado — investigar pipeline de captura"` |
| Sessões `in-progress` há muito tempo | **HALT** com `conclusao: sessão-stuck`, `bloqueio: "sessão em in-progress por tempo excessivo — pode ser loop ou deadlock no dispatch"` |
| Tudo saudável | Prossiga |

### 4. Conclusão: não determinado

Se nenhuma causa foi encontrada, o travamento com sessão ativa e sem erro requer investigação mais profunda. Faça HALT com:

- `conclusao: nao-determinado`
- `bloqueio: "sessão existe sem erro e sem causa identificada — investigar fluxo de resposta do dispatch, webhook, e conexão com provider"`
- Inclua a saída completa do `diagnose-hang.sh` como evidência

## Registro no artefato

Antes de HALT, atualize o frontmatter:

- `status`: `done` (se causa encontrada) ou `blocked` (se não determinado)
- `conclusao`: a causa identificada
- `bloqueio`: descrição da causa
- `evidencia`: caminho ou saída relevante

Grave em disco.

## NEXT

Este passo termina em HALT. Nenhuma transição padrão.
