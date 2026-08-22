# Step 1: Route

## REGRAS

- Este passo NÃO executa trabalho. Ele decide qual passo carregar em seguida.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.

## Pré-condição: DISPATCH_RUNNER

Verifique se a variável de ambiente `DISPATCH_RUNNER` está definida:

```bash
echo "${DISPATCH_RUNNER:-NÃO DEFINIDA}"
```

Se estiver vazia ou "NÃO DEFINIDA", HALT com status `blocked` e bloqueio `DISPATCH_RUNNER não definida. Rode: source adapters/<cli>/env.sh`.

## Roteamento principal

1. Localize o artefato. Verifique se `$DISPATCH_ARTEFATO` está definido e se o arquivo apontado existe.
   - Se `$DISPATCH_ARTEFATO` não estiver definido, procure por arquivos `.md` com frontmatter contendo `status:` no diretório `.dispatch/`.
   - Se nenhum artefato for encontrado, crie um novo a partir do template `fluxos/_comum/artefato-template.md`, gere um `id` único, defina `status: draft`, grave em `.dispatch/` e defina `DISPATCH_ARTEFATO` com o caminho.

2. Leia o campo `status` do frontmatter do artefato.

3. Roteie conforme o status:

   | status | ação |
   |--------|------|
   | `draft` | **EARLY EXIT** → `./step-02-prepare.md` |
   | `ready` | **EARLY EXIT** → `./step-03-execute.md` |
   | `in-progress` | **EARLY EXIT** → `./step-03-execute.md` |
   | `in-review` | **EARLY EXIT** → `./step-04-verify.md` |
   | `blocked` | HALT com status `blocked` e bloqueio atual do artefato |
   | `done` | HALT com status `done` — trabalho concluído |

## NEXT

Este passo sempre termina em EARLY EXIT ou HALT. Nenhuma transição padrão.
