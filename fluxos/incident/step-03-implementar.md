# Step 3: Implementar

## REGRAS

- Chegou aqui com a classe definida. Implemente conforme o caminho correspondente.
- Cada classe tem uma implementação diferente. Siga **apenas** a seção correspondente à classe.
- O incidente só pode ser encerrado quando a proteção estiver no lugar.

## Pré-condição

Leia o artefato do fluxo. Confirme que `campo classe` está preenchido com `P`, `C` ou `R`.

Leia o arquivo do incidente apontado por `evidencia` para relembrar a causa e a correção.

## INSTRUÇÕES

### Caminho P — Criar passo de fluxo

A proteção vira um passo de fluxo (novo ou adicionado a um step existente).

1. Identifique qual fluxo recebe o passo. Quando o incidente se refere a uma etapa do dispatch, o passo vai em `fluxos/dispatch/`. Quando é sobre diagnóstico, vai em `fluxos/diagnose/`. Quando é novo, crie em `fluxos/verify/` ou `fluxos/incident/`.

2. Crie ou edite o arquivo seguindo as convenções dos fluxos:
   - Termine com seção `## NEXT`
   - Use **EARLY EXIT** e **HALT** na formatação dos fluxos existentes
   - Nenhum comando cru de CLI

3. Atualize o mapa em `fluxos/_comum/mapa-regras.md` se a proteção substituir uma regra R existente (mude a classe para P e registre o destino).

4. Atualize o frontmatter do incidente: marque `status: promovido` e preencha `regra` com o destino do passo (`fluxos/<fluxo>/step-XX-<nome>.md`).

5. Grave em disco.

### Caminho C — Criar código

A proteção vira um script, validação ou gate em `bin/`.

1. Crie o script seguindo o padrão dos existentes em `bin/`:
   - `set -uo pipefail` no início
   - Exit codes documentados
   - Comentário sobre qual incidente originou o mecanismo

2. Se for uma validação nova, considere adicionar a chamada ao step de fluxo correspondente para que o agente execute automaticamente.

3. Atualize o frontmatter do incidente: marque `status: promovido` e preencha `regra` com o caminho do script recém-criado.

4. Grave em disco.

### Caminho R — Promover a regra

A proteção vira uma regra numerada no `SKILL.md`. Use este caminho **apenas** quando não houver mecanismo automatizado possível.

1. Confirme que não há mecanismo viável. Leia o critério da poda em `fluxos/_comum/mapa-regras.md`: se a proteção exigir julgamento contextual que nenhum script pode capturar, siga.

2. Promova o incidente a regra:

   ```bash
   bin/incident.sh promote <id> "<texto da regra>"
   ```

   O comando lê o marcador HTML `ultimo-numero-de-regra` no `SKILL.md`, gera o próximo número, insere a regra e atualiza o marcador.

3. Confirme que a regra foi inserida:

   ```bash
   grep "regra [0-9]*" fluxos/dispatch/SKILL.md
   ```

4. Atualize o frontmatter do incidente: o comando `promote` já marca `status: promovido` e preenche `regra`.

5. Grave em disco.

### 4. Registrar no artefato do fluxo

Atualize o artefato do fluxo:
- `status`: `done`
- `evidencia`: caminho do incidente + classe aplicada + resultado

Grave em disco.

HALT com status `done`.

## NEXT

Este passo sempre termina em HALT. Nenhuma transição padrão.
