---
id: 2026-08-13-ring-init-nao-atomico-sobre-ring-gitignored
titulo: ring init não-atômico sobre alvo com ring/ no .gitignore
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — preflight git check-ignore no init recusa antes de escrever qualquer coisa
status: fechado
---

# ring init não-atômico sobre alvo com ring/ no .gitignore

## Sintoma

No setup do run overnight `ananke-20260813-0400` (alvo: o próprio oracfit,
worktree <home-do-dono>/wt-oracfit), o primeiro `oracfit ring init` saiu com
exit 1 no `git add` do scaffold e deixou o alvo PELA METADE: `ring/state.json`,
`ring/oracle.sh` e `ring/ledger.jsonl` criados no disco, nada commitado, hook
instalado. O contrato do init ("scaffold commitado, árvore limpa" — protegido
pelo T1 da suíte) foi violado sem rollback.

## Causa

`ring/` estava no `.gitignore` do repo (chore `f458e8f`): o `git add ring/`
do init não adiciona nada e o runner segue até falhar adiante, sem desfazer o
que já escreveu. O init de `bin/oracfit-ring.sh` não é transacional: cada
passo (mkdir, state, oracle, hook, git add, commit) muda estado real e não há
trap de limpeza em caso de erro no meio.

## Correção aplicada (neste run)

Manual: `rm -rf ring/` no alvo, remoção da linha `ring/` do `.gitignore` do
worktree (commit `cd475fd`), segundo init limpo (commit `42c88ca`).

## Proteção pendente (candidata a anel futuro)

1. Pré-checagem no init: `git check-ignore ring/` no alvo → recusa ANTES de
   escrever qualquer coisa, com mensagem apontando a linha do .gitignore.
2. Ou init transacional: trap que remove o scaffold recém-criado quando
   qualquer passo falha (só quando o ring/ não existia antes).

Nenhuma das duas foi implementada neste run (backlog da noite era fixo:
RING-1/2/3); fica registrado como débito.

## Fechamento (2026-08-22)

Candidata 1 implementada: o init faz `git check-ignore` no alvo (duas formas
de caminho — padrão "ring/" com barra final não casa caminho inexistente dado
sem barra) e recusa apontando a linha do .gitignore ANTES de criar qualquer
coisa — nem run id é reservado no ledger central. Código: bin/oracfit-ring.sh
(bloco init, preflight de ignore). Teste: tests/test-ring-runner.sh T27
(recusa com diagnóstico + scaffold zerado + central intocado). Para ESTE modo
de falha a candidata 2 (trap transacional) deixa de ser necessária: o caminho
que escrevia antes de falhar foi eliminado pela recusa antecipada; a falha
tardia de hook do commit do scaffold (débito 11, ananke-20260813-0412) é
família distinta e tem handling próprio no mesmo init.
