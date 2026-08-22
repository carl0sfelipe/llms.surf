# Step 1: Escolher Alvo

## REGRAS

- Este passo NÃO mede. Ele decide qual modelo verificar e se o id do modelo existe no catálogo.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.

## Pré-condição: DISPATCH_RUNNER

Verifique se a variável de ambiente `DISPATCH_RUNNER` está definida:

```bash
echo "${DISPATCH_RUNNER:-NÃO DEFINIDA}"
```

Se estiver vazia ou "NÃO DEFINIDA", HALT com status `blocked` e bloqueio `DISPATCH_RUNNER não definida. Rode: source adapters/<cli>/env.sh`.

## INSTRUÇÕES

### 1. Definir o alvo

O modelo a verificar pode vir de:

- Uma solicitação direta: `model_id` informado pelo usuário.
- Um modelo candidato identificado em `fluxos/` pendente de verificação.
- Todo o registry: quando a intenção é verificar todos os modelos de uma vez.

Se não houver alvo definido, leia `model-registry.json` e liste os modelos com `verified_at` ausente ou vazio:

```bash
grep -B5 '"verified_at": ""' model-registry.json || echo "Nenhum modelo pendente de verificação."
```

Se nenhum modelo precisar de verificação, HALT com status `done` e bloqueio `nenhum modelo pendente de verificação`.

Se houver alvo, prossiga.

### 2. Auditar o id do modelo

Antes de gastar tempo medindo um id que não existe, confira se o modelo consta no catálogo do provider:

```bash
bin/audit-registry-ids.sh
```

Interprete a saída:

| Resultado | Significado | Ação |
|-----------|-------------|------|
| "FANTASMA" para o modelo alvo | Id de modelo que não existe em catálogo nenhum | HALT com status `blocked` e bloqueio `modelo fantasma — id sem correspondência em catálogo. Use bin/incident.sh new para registrar.` |
| "NAO-ENCONTRADO" para o modelo alvo | Não encontrado, mas pode ser provider sem catálogo público | Prossiga — falso positivo possível |
| Exit 0 (tudo OK) | Nenhum problema de catálogo | Prossiga |

### 3. Marcar estado

Atualize o frontmatter do artefato:
- `status`: `in-progress`
- `modelo`: o id do modelo a verificar

Grave em disco.

## NEXT

Leia integralmente e siga `./step-02-medir-em-sandbox.md`.
