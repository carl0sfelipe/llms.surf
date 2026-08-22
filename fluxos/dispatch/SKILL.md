# Dispatch — Fluxo de Orquestração Multi-Modelo

**Objetivo:** Executar um ciclo completo de dispatch — rotear, preparar, executar e verificar — usando o artefato como estado externalizado.

**CRITICAL:** Se um passo diz "leia integralmente e siga step-XX", você lê e segue step-XX. Sem exceções.

## Artefato

O estado do fluxo vive no frontmatter do artefato, baseado no template `fluxos/_comum/artefato-template.md`. Campos relevantes:

- `status`: draft | ready | in-progress | in-review | done | blocked
- `tentativas`: número de tentativas de execução (usado por step-04)
- `bloqueio`: razão do bloqueio, se houver

## HALT

Ao parar, SEMPRE grave o estado no artefato antes de sair:

1. Atualize o campo `status` no frontmatter com o estado terminal.
2. Se houver condição de bloqueio, atualize o campo `bloqueio` com a descrição.
3. Grave as alterações em disco.
4. Pare o fluxo.

Terminar sem deixar rastro é inaceitável — o próximo agente retoma pelo `status`.

## Convenções

- Caminhos nus (ex: `step-01-route.md`) resolvem a partir da raiz deste fluxo (`fluxos/dispatch/`).
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.
- Nenhum passo contém comando cru de CLI (`opencode run`, `claude -p`, `curl`, `hermes -z`). Sempre use os wrappers de `bin/`.

## Primeiro passo

Leia integralmente e siga: `./step-01-route.md` para iniciar o fluxo.
