# Incident — Fluxo de Transformação de Falha em Proteção

**Objetivo:** Transformar uma falha que pode se repetir em proteção real — seja um passo de fluxo, um trecho de código, ou uma regra nova. O ponto central: **regra nova é o último recurso, não o primeiro.**

**CRITICAL:** Se um passo diz "leia integralmente e siga step-XX", você lê e segue step-XX. Sem exceções.

## Quando usar

Use este fluxo sempre que um problema ocorrer e houver chance de repetição. O protocolo de feedback que rege este fluxo está detalhado em `core/feedback-protocol.md` — consulte para entender o ciclo completo, os campos do incidente e a relação com `lessons/`.

## Artefato

O estado do fluxo vive no frontmatter do artefato, baseado no template `fluxos/_comum/artefato-template.md`. Campos relevantes:

- `status`: draft | ready | in-progress | in-review | done | blocked
- `bloqueio`: razão do bloqueio, se houver
- `evidencia`: id do incidente criado

Além do artefato, o incidente tem seu próprio arquivo em `incidents/<id>.md`, gerenciado via `bin/incident.sh`.

## HALT

Ao parar, SEMPRE grave o estado no artefato antes de sair:

1. Atualize o campo `status` no frontmatter com o estado terminal.
2. Se houver condição de bloqueio, atualize o campo `bloqueio` com a descrição.
3. Grave as alterações em disco.
4. Pare o fluxo.

Terminar sem deixar rastro é inaceitável — o próximo agente retoma pelo `status`.

## Convenções

- Caminhos nus (ex: `step-01-registrar.md`) resolvem a partir da raiz deste fluxo (`fluxos/incident/`).
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.
- **HALT** significa: grave o artefato (frontmatter + resultado) e pare; o fluxo terminou.
- Nenhum passo contém comando cru de CLI (`opencode run`, `claude -p`, `curl`, `hermes -z`). Sempre use os wrappers de `bin/`.
- Consulte `core/feedback-protocol.md` para a especificação completa do protocolo de feedback — este fluxo implementa o ciclo descrito lá.

## Primeiro passo

Leia integralmente e siga: `./step-01-registrar.md` para iniciar o fluxo.