# Step 1: Triagem

## REGRAS

- Este passo NÃO diagnostica. Ele decide qual passo carregar em seguida.
- A decisão é baseada na saída de `bin/diagnose-hang.sh`.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.
- **Não troque de modelo antes de terminar este fluxo.** Escalar aqui esconde a causa.

## Antes de classificar: os três modos de falha

Silêncio não é um diagnóstico. A falha tem três modos, e só um deles justifica escalar para modelo maior:

| Modo | Sinal no log | Ação correta |
|---|---|---|
| **(a) Rate limit** | `429`, `rate limit exceeded` no stderr | esperar e repetir. **Rate limit não é incapacidade** — trocar de modelo aqui desperdiça o modelo bom |
| **(b) Erro de lógica** | produziu output, e o output está errado | escalar para modelo maior |
| **(c) Silêncio sem erro** | zero output, zero erro no stderr | **NÃO escale** — siga este fluxo até o fim |

Silêncio (modo c) já teve pelo menos três causas distintas com o mesmo sintoma: agente concorrente no mesmo repositório, id de modelo inexistente no catálogo do provider (pendura em vez de dar 404), e janela de contexto pequena demais para o prompt base do CLI. Nenhuma delas se resolve trocando de modelo.

**Output vazio por mais de 60s é investigação, não espera.** Incidentes: `incidents/2026-07-25-escalei-sem-checar-log-e-regra-de-subida.md` e `incidents/2026-07-25-travamento-tem-dois-modos-e-o-erro-fica-.md`.

## Pré-condição: artefato

1. Verifique se `$DISPATCH_ARTEFATO` está definido e se o arquivo apontado existe.
   - Se estiver definido e existir, use-o.
   - Se **não** estiver definido ou o arquivo não existir, crie um novo artefato de diagnóstico:
     - Copie o template de `fluxos/_comum/artefato-template.md`.
     - Gere um `id` no formato `diagnose-<YYYY-MM-DD>`.
     - Defina `status: in-progress` e `owner: "diagnose"`.
     - Adicione um campo `conclusao: ""` ao frontmatter.
     - Grave em `.dispatch/artefatos/diagnose-<YYYY-MM-DD>.md`.
     - Defina `DISPATCH_ARTEFATO` com o caminho.

## Roteamento principal

1. Execute o diagnóstico base:

   ```bash
   bin/diagnose-hang.sh
   ```

   Se você souber o `model_id` envolvido, passe-o como argumento:

   ```bash
   bin/diagnose-hang.sh <model_id>
   ```

2. Leia a saída completa. Foque nas seções 3 e 4:

   - **Seção 3 (Sessões criadas):** mostra se existem sessões no banco no período.
   - **Seção 4 (Erros gravados):** mostra se há erros registrados nas mensagens.

3. Roteie conforme o resultado:

   | Condição | Sessão existe no banco? | Erro gravado? | Ação |
   |----------|------------------------|---------------|------|
   | "NENHUMA sessão criada" aparece na seção 3 | **Não** | — | **EARLY EXIT** → `./step-02-antes-do-provider.md` |
   | Sessões existem e seção 4 mostra erros | **Sim** | **Sim** | **EARLY EXIT** → `./step-03-erro-no-banco.md` |
   | Sessões existem e seção 4 mostra "nenhum erro" | **Sim** | **Não** | **EARLY EXIT** → `./step-04-resposta-perdida.md` |

4. Se a saída do script for ambígua ou vazia (ex: banco não encontrado), registre `conclusao: nao-determinado` e `bloqueio: "diagnose-hang.sh não produziu saída classificável — banco pode estar inacessível"`, faça HALT com `status: blocked`.

## Registro no artefato

Antes de fazer EARLY EXIT, registre no artefato qual caminho foi seguido:

```yaml
bloqueio: "triagem → step-02 | step-03 | step-04"  # ajuste para o passo alvo
```

Atualize o frontmatter e grave em disco.

## NEXT

Este passo sempre termina em EARLY EXIT ou HALT. Nenhuma transição padrão.
