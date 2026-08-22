# Diagnose — Fluxo de Diagnóstico de Travamento

**Objetivo:** Classificar um travamento de dispatch em vez de adivinhar a causa. Em 2026-07-24/25 o mesmo sintoma ("pendura, sem erro no stderr") teve pelo menos TRÊS causas diferentes — agente concorrente, id de modelo fantasma, e contexto do modelo pequeno demais para o prompt base. Este fluxo separa os casos por uma pergunta objetiva: **a sessão existe no banco?**

**CRITICAL:** Se um passo diz "leia integralmente e siga step-XX", você lê e segue step-XX. Sem exceções.

## Quando usar

Use este fluxo quando um dispatch aparenta estar travado: pendura sem resposta, não produz erro no stderr, ou o usuário reporta que "não acontece nada". Este fluxo pode ser chamado SEM artefato existente — quando algo trava do nada ele cria um artefato próprio.

## Artefato

O estado do fluxo vive no frontmatter do artefato, baseado no template `fluxos/_comum/artefato-template.md`. Quando não há artefato prévio (travamento espontâneo), este fluxo cria um arquivo em `.dispatch/artefatos/diagnose-<data>.md`.

O campo `conclusao` no frontmatter registra a causa identificada:

```yaml
conclusao: "agente-concorrente" | "processo-orfao" | "modelo-fantasma" | "runtime-agentico-travado" | "context-overflow" | "rate-limit" | "saldo-insuficiente" | "resposta-em-reasoning-content" | "captura-output-incorreta" | "nao-determinado"
```

## HALT

Ao parar, SEMPRE grave a conclusão no artefato antes de sair:

1. Atualize o campo `status` no frontmatter com o estado terminal.
2. Atualize o campo `conclusao` com a causa identificada (ou `nao-determinado`).
3. Se houver condição de bloqueio, atualize o campo `bloqueio` com a descrição.
4. Grave as alterações em disco.
5. Pare o fluxo.

Terminar sem deixar rastro é inaceitável — o próximo agente retoma pelo `status`.

## Convenções

- Caminhos nus (ex: `step-01-triagem.md`) resolvem a partir da raiz deste fluxo (`fluxos/diagnose/`).
- **EARLY EXIT** significa: pare este passo imediatamente, leia e siga o arquivo alvo.
- **HALT** significa: grave o artefato (frontmatter + resultado) e pare; o fluxo terminou.
- Nenhum passo contém comando cru de CLI (`opencode run`, `claude -p`, `curl`, `hermes -z`). Sempre use os wrappers de `bin/`.

## Primeiro passo

Leia integralmente e siga: `./step-01-triagem.md` para iniciar o fluxo.
