# Verify — Fluxo de Medição e Validação de Modelo

**Objetivo:** Medir um modelo real em sandbox e, somente após ler e aprovar o resultado do dry-run, gravar o resultado no `model-registry.json`. Nunca contaminar o registry com dado não verificado.

**CRITICAL:** Se um passo diz "leia integralmente e siga step-XX", você lê e segue step-XX. Sem exceções.

## Quando usar

Use este fluxo antes de confiar em um modelo para dispatch — especialmente modelos novos, modelos de provider novo, ou modelos cujo `verified_at` está ausente ou vencido. A medição roda em sandbox (`mktemp -d`), fora do repositório, e só toca o registry quando você explicitamente aprova.

## Artefato

O estado do fluxo vive no frontmatter do artefato, baseado no template `fluxos/_comum/artefato-template.md`. Campos relevantes:

- `status`: draft | ready | in-progress | in-review | done | blocked
- `modelo`: id do modelo sendo verificado
- `tentativas`: número de tentativas (usado por step-02)
- `bloqueio`: razão do bloqueio, se houver
- `evidencia`: resultado do dry-run (suite_accuracy, latency, etc.)

## HALT

Ao parar, SEMPRE grave o estado no artefato antes de sair:

1. Atualize o campo `status` no frontmatter com o estado terminal.
2. Se houver condição de bloqueio, atualize o campo `bloqueio` com a descrição.
3. Grave as alterações em disco.
4. Pare o fluxo.

Terminar sem deixar rastro é inaceitável — o próximo agente retoma pelo `status`.

## Convenções

- Caminhos nus (ex: `step-01-escolher-alvo.md`) resolvem a partir da raiz deste fluxo (`fluxos/verify/`).
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.
- **HALT** significa: grave o artefato (frontmatter + resultado) e pare; o fluxo terminou.
- Nenhum passo contém comando cru de CLI (`opencode run`, `claude -p`, `curl`, `hermes -z`). Sempre use os wrappers de `bin/`.

## Primeiro passo

Leia integralmente e siga: `./step-01-escolher-alvo.md` para iniciar o fluxo.