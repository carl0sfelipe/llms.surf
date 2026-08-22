# Step 3: Gravar com Dry-Run Aprovado

## REGRAS

- O dry-run já foi lido e aprovado no passo anterior.
- `suite_accuracy` igual a 0.0 impede a gravação (verificado no passo anterior) — se chegou aqui, o resultado é válido.
- `bin/verify-models.sh` recusa gravar quando `id_status` do modelo é FANTASMA ou NAO-VERIFICADO (verificado no passo 1).

## INSTRUÇÕES

### 1. Carregar estado

Leia o artefato. Confirme que `status: in-progress` e que o campo `evidencia` contém o resultado do dry-run.

### 2. Gravar no registry

Execute a medição com `--write` para carimbar o resultado no `model-registry.json`:

```bash
bin/verify-models.sh "<modelo>" --write
```

Interprete o exit code:

| Exit | Significado | Ação |
|------|-------------|------|
| 0 | Gravado com sucesso | Prossiga para o passo 3 |
| 1 | Modelo falhou | HALT com status `blocked` e bloqueio `verify-models.sh --write falhou — modelo não respondeu na gravação, apesar de ter respondido no dry-run` |
| 3 | Erro de uso | HALT com status `blocked` e bloqueio `verify-models.sh --write: erro de uso` |

### 3. Confirmar a gravação

Verifique se o registry foi atualizado:

```bash
grep -A5 '"verified_at"' model-registry.json | head -20
```

Confirme que o campo `measured.verified_at` do modelo alvo foi preenchido com um timestamp.

### 4. Marcar como concluído

Atualize o frontmatter do artefato:
- `status`: `done`
- `evidencia`: resultado final da medição com `--write`

Grave em disco.

HALT com status `done`.

## NEXT

Este passo sempre termina em HALT. Nenhuma transição padrão.
