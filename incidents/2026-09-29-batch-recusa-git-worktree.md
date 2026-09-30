---
status: fechado
---
# oracfit batch recusava git worktree ("workdir não é repo git")

Dispatch do adaptador cursor numa worktree (para não colidir com outro run no checkout principal)
foi recusado pelo gate: `dispatch-batch.sh` testava `[ -d "$dir/.git" ]`, e numa worktree `.git`
é um ARQUIVO. Nenhum token gasto, mas o dono ficou sem o run no painel.

## Correção (feita)
Gate usa `git -C "$dir" rev-parse --git-dir` (mesmo teste de ring-preflight.sh e oracfit-ring.sh).

## Melhoria proposta
Runs paralelos no mesmo repo deveriam nascer em worktree por padrão (`oracfit batch --worktree`),
para dois agentes nunca editarem a mesma árvore.
