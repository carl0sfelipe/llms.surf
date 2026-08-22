# AGENTS.md — opencode como executor do dispatch

Fonte: `core/dispatch-spec.md`, `core/runner-contract.md`. opencode é hoje o único
CLI orquestrador+executor (PRD seção 4.4) — roda os modelos free de fato.

## Setup

```
source adapters/opencode/env.sh
```

Isso exporta `DISPATCH_RUNNER` (aponta para `adapters/opencode/runner.sh`),
`DISPATCH_RUNNER_NAME=opencode`, `DB_PATH`, `LOG_DIR`, `PID_DIR`,
`MODEL_REGISTRY`, `CAPABILITIES_FILE`.

## Uso a partir do dispatch core

```
bin/pre-dispatch-check.sh nvidia
bin/smoke-test.sh deepseek-v4-flash-free
bin/dispatch.sh deepseek-v4-flash-free specs/minha-tarefa.md minha-task
```

`bin/dispatch.sh` chama `$DISPATCH_RUNNER` (`adapters/opencode/runner.sh`) em
background, que por sua vez monta `opencode run --model "$MODEL_ID" --format json
"$(cat spec_file)"` (sintaxe verificada em `adapters/opencode/DISCOVERY.md`).

## Fork de sessão

```
BASE=$(bin/new-session.sh mistral-small-4-119b-2603 specs/mapeamento.md)
bin/parallel-dispatch.sh "$BASE" specs/tasks.txt mistral-small-4-119b-2603
```

`runner.sh` traduz `--session ID --fork` para `opencode run --session ID --fork`.

## Attach TUI

```
bin/attach.sh minha-task
```

Usa `opencode -s <session_id>` (capacidade `ATTACH_TUI=1`, ver `capabilities.env`).
