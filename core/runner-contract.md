# Contrato DISPATCH_RUNNER

Fonte: `specs/PRD-reformulacao-multi-cli.md` seção 4.2. Este documento não adiciona regra nova — só torna explícito o contrato já definido no PRD.

## Problema que o contrato resolve

`DISPATCH_RUNNER` como env var com comando cru não resolve: a ordem de argumentos difere entre CLIs (`opencode run --model X 'prompt'` vs `claude -p 'prompt' --model X`). Não dá para montar uma linha de comando genérica por concatenação de string.

## Interface fixa

`DISPATCH_RUNNER` aponta para um executável `adapters/<cli>/runner.sh` com interface fixa:

```
runner.sh <model_id> <spec_file> [--session ID] [--fork]
```

- `<model_id>` — id do modelo, copiado de `model-registry.json` (nunca inventado, nunca concatenado com prefixo às cegas).

**Resolução do model_id é responsabilidade do `runner.sh`.** Quem chama passa o `id` do registry; o runner traduz para a sintaxe do seu CLI lendo `cli_hints.<cli>` em `$MODEL_REGISTRY`. Regras:

- `id` presente com `cli_hints.<cli>` → usa o hint (aceitar o próprio hint como entrada também, para ser idempotente)
- `id` presente sem hint para aquele CLI → `exit 3` (modelo indisponível ali; ver PRD 4.3)
- `id` ausente do registry → `exit 3` (PRD seção 11, regra 2: nunca inventar model id)

Passar o `id` cru para o CLI é bug: `opencode run --model nemotron-3-ultra-free` retorna erro de servidor, enquanto o hint `opencode/nemotron-3-ultra-free` funciona.
- `<spec_file>` — caminho para arquivo com o spec/prompt.
- `--session ID` — opcional. Reusa/forka sessão existente.
- `--fork` — opcional. Junto com `--session`, cria fork em vez de reusar.

Cada `runner.sh` traduz esses argumentos para a sintaxe real do seu CLI. Exemplos do PRD:

- `adapters/opencode/runner.sh` monta `opencode run --model "$1" "$(cat "$2")"`
- `adapters/claude-code/runner.sh` monta `claude -p "$(cat "$2")" --model "$1"`

(Nenhum `runner.sh` é criado em F1 — isso é escopo de F2+. Este documento só fixa o contrato que os scripts em `bin/` já assumem.)

## Exit codes (RNF-04)

| Exit | Significado |
|------|-------------|
| 0 | ok |
| 1 | erro |
| 2 | rate-limit / switch |
| 3 | erro de uso |
| 4 | quota exausta |

Todo script em `bin/` que invoca `$DISPATCH_RUNNER` deve propagar ou interpretar esses exit codes — nunca inventar um novo significado para um código existente.

## Flag não suportada pelo CLI

Se o CLI alvo não suporta uma flag do contrato (ex: `--fork`), `runner.sh` falha com `exit 3` e mensagem clara no stderr, por exemplo:

```
zcode não suporta --fork
```

Nunca inventa flag equivalente nem tenta simular o comportamento.

## Capacidades

Scripts em `bin/` que dependem de uma capacidade opcional (fork, session-reuse, attach TUI, format json) devem checar `adapters/<cli>/capabilities.env` antes de assumir que o `runner.sh` ativo suporta aquela flag. Capacidade ausente = `exit 3`, nunca degradação silenciosa. `capabilities.env` é escrito pela etapa de Descoberta (seção 7, Passo 0 do PRD) — fora do escopo F1.
