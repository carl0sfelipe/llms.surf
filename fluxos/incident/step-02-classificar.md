# Step 2: Classificar

## REGRAS

- Chegou aqui porque o incidente foi registrado. Agora você decide como transformá-lo em proteção.
- **Regra nova é o último recurso, não o primeiro.** Se der para virar passo ou código, vira passo ou código.
- A classificação usa o mesmo critério do mapa em `fluxos/_comum/mapa-regras.md`.
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.

## Pré-condição

Leia o artefato do fluxo. Confirme que `status: in-progress` e que o campo `evidencia` aponta para um incidente válido.

## INSTRUÇÕES

### 1. Como classificar

Leia o critério da poda D11 em `fluxos/_comum/mapa-regras.md`:

| Classe | Significado | Quando usar |
|--------|-------------|-------------|
| **P** | vira passo de fluxo | A proteção pode ser descrita como uma sequência de ações em um step existente ou novo. Use quando o agente precisa seguir uma sequência procedural para evitar o erro. |
| **C** | vira código | Existe ou pode existir um script, validação, gate ou mecanismo automatizado que impeça o erro. Use quando o erro pode ser detectado ou bloqueado mecanicamente. |
| **R** | permanece regra | Exige julgamento humano ou contextual, sem mecanismo automatizado possível hoje. Use quando não há script que detecte a condição preventivamente. |

### 2. Decidir a classe

Analise a causa do incidente e escolha a classe:

- A proteção pode ser automatizada (um script, um gate, uma validação)? → **C**
- A proteção é uma sequência de ações que um agente deve seguir? → **P**
- Não há mecanismo possível — exige decisão contextual toda vez? → **R**

**Se houver dúvida entre C e P, prefira C:** código executa sempre e independe de disciplina do agente. A experiência da poda D11 mostrou que toda regra R que podia virar mecanismo deveria ter virado.

### 3. Registrar a classificação

Atualize o frontmatter do artefato do fluxo:

Adicione um campo `classe` com o valor escolhido (`P`, `C` ou `R`).

### 4. Roteamento

As três classes convergem para o mesmo passo: **EARLY EXIT** → `./step-03-implementar.md`.

O que muda não é o destino, é o que se faz lá — o campo `classe` que você acabou de gravar decide se a implementação é passo, código ou regra.

## NEXT

Este passo sempre termina em EARLY EXIT. Nenhuma transição padrão.
