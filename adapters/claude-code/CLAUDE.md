# CLAUDE.md — Claude Code como orquestrador do dispatch

Fonte: `specs/PRD-reformulacao-multi-cli.md` seção 4.4, `core/dispatch-spec.md`.

Claude Code é **orquestrador** — lê a skill (`SKILL.md`), escreve specs curtas e
grounded, e chama `bin/dispatch.sh`. O executor de fato (quem roda o modelo free)
é **opencode**, via `adapters/opencode/runner.sh`. `claude` CLI só executa
modelos Anthropic — se `model-registry.json` não tiver `cli_hints.claude` para
o modelo, `adapters/claude-code/runner.sh` recusa com `exit 3`.

## Fluxo (orquestrador)

```
source adapters/opencode/env.sh
bin/pre-dispatch-check.sh nvidia
bin/smoke-test.sh nemotron-3-ultra-free
bin/dispatch.sh nemotron-3-ultra-free specs/minha-tarefa.md minha-task
bin/poll-status.sh minha-task
```

Claude Code lê o output em `$LOG_DIR`, verifica contra o código real (grep/ls),
e despacha refinamento (DELETE/REESCREVA/ADICIONE) se necessário — nunca
reescreve o bulk manualmente (`core/dispatch-spec.md`).

## Rodando Claude Code como executor (modelos Anthropic)

```
source adapters/claude-code/env.sh
bin/dispatch.sh <model_id_anthropic> specs/minha-tarefa.md minha-task
```

Só funciona se `<model_id_anthropic>` tiver `cli_hints.claude` em
`model-registry.json` (RF-01, PRD 4.3). Desde 2026-07-27, `claude-sonnet-5` tem
`cli_hints.claude: sonnet` e a rota está **testada como executor real** —
`bin/smoke-test.sh claude-sonnet-5` responde em ~6s.

Dois cuidados descobertos nessa primeira execução real:

- **O detector de silêncio não vale aqui.** `claude -p` imprime a resposta inteira
  no fim, não durante. `adapters/claude-code/capabilities.env` declara
  `STREAMS_OUTPUT=0` e `bin/dispatch.sh` desliga o detector para este adapter —
  senão toda tarefa acima de 5 minutos morreria como se estivesse travada.
- **`--allowed-tools` vai depois do prompt.** É variádico: posto antes, engole o
  próprio prompt. Ver o bloco de segurança abaixo.

## Segurança — sem `--dangerously-skip-permissions` por default (RF-01.1)

`adapters/claude-code/runner.sh` **não** adiciona `--dangerously-skip-permissions`
a menos que `DISPATCH_UNSAFE=1` esteja setado no ambiente. Por default, rodar via
`-p` respeita o modo de permissão normal do Claude Code.

**Alternativa por dispatch: `DISPATCH_ALLOWED_TOOLS`.** Entre "nega tudo" e
"libera tudo" faltava o meio-termo. Um dispatch honesto que precise rodar
`python3` para no meio pedindo aprovação que ninguém vai dar — foi o que aconteceu
em 2026-07-27 — e a saída fácil (ligar `DISPATCH_UNSAFE=1`) concede muito mais do
que a tarefa pede.

```bash
export DISPATCH_ALLOWED_TOOLS="Read,Write,Edit,Grep,Glob,Bash(python3:*),Bash(git:*)"
bin/dispatch.sh claude-sonnet-5 spec.md minha-task
```

O runner passa isso em `--allowed-tools` **depois** do prompt. Confira
`permission_denials` no JSON de saída: se vier não-vazio, a allowlist ficou
estreita demais para a tarefa.

**Alternativa persistente:** allowlist de ferramentas em
`.claude/settings.local.json` do projeto, em vez de pular permissões:

```json
{
  "permissions": {
    "allow": [
      "Bash(git status)",
      "Bash(git diff)",
      "Read",
      "Edit"
    ]
  }
}
```

Isso evita `--dangerously-skip-permissions` (flag real confirmada em
`adapters/claude-code/DISCOVERY.md`, recomendada pelo próprio `claude --help`
"apenas para sandboxes sem acesso à internet") mantendo dispatch não-interativo
funcional para os comandos já permitidos.
