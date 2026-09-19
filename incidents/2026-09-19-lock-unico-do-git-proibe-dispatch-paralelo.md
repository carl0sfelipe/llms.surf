---
id: 2026-09-19-lock-unico-do-git-proibe-dispatch-paralelo
titulo: lock unico do .git proibe dispatch paralelo e a bateria P1 de 10 specs nao roda pelo caminho E5
data: 2026-09-19
recorrivel: sim
regra: 8
status: promovido
---

# lock unico do .git proibe dispatch paralelo e a bateria P1 de 10 specs nao roda pelo caminho E5

## Sintoma

A bateria P1 (`kernel/test-specs/README.md`, 10 specs T01–T10) é definida
para rodar em paralelo — "Specs are independent; run them in parallel" — e
pela própria regra 2 do README ela tem de correr PELO produto: cada spec
vira um `bin/dispatch.sh tier:cheap kernel/test-specs/<ID>-*.md p1-<ID>`
com oráculo mecânico, porque a bateria "is research §6 E5's shape (10
tasks, cheap tier, fast judge)" (E5 = "o experimento central":
`docs/research/bend2-convergence-2026-09-19.md`, 10 tarefas despachadas,
taxa de fechamento/retries/custo medidos via ledger).

Orquestrar as 10 specs assim exige 10 `bin/dispatch.sh` simultâneos. O
produto recusa o 2º em diante ANTES de chamar qualquer modelo:

```
❌ Erro: já existe um dispatch em andamento neste repositório (PID: ...).
   Aguarde terminar ou verifique $LOCK_FILE.
```

com exit 3 — e o caminho E5 (bateria medida no ledger, 10 despachos
concorrentes) não existe enquanto o lock for único por repositório. O
achado veio da bateria e foi promovido por decisão do dono:
`kernel/test-specs/DECISIONS-wave1-2.md` (D-DISPATCH item 2, 2026-09-19):
"Single `.git` lock forbids parallel dispatch → backlog line
('per-worktree lock'), not fixed now."

## Causa

O lock anti-concorrência de `bin/dispatch.sh` é granulado no repositório
inteiro, não no workdir da tarefa:

- linha 50: `# RNF-07: recusa 2 dispatches simultâneos no mesmo .git` —
  é o mecanismo da regra 8 ("nunca 2 agentes no mesmo `.git`",
  `fluxos/_comum/mapa-regras.md`);
- linha 51: `GIT_ROOT="$(git rev-parse --show-toplevel ...)"`;
- linha 52: `LOCK_HASH` = sha1 (fallback md5) do `GIT_ROOT`;
- linha 53: `LOCK_FILE="$PID_DIR/dispatch-repo-${LOCK_HASH}.lock"`;
- linhas 55–61: gate — lock existente com PID vivo ⇒ mensagem (linha 58)
  e `exit 3` (linha 59).

A chave do lock é a raiz do repositório onde o dispatch roda, NÃO o
`TASK_NAME`: dois despachos simultâneos com tarefas diferentes na mesma
árvore disputam o MESMO `dispatch-repo-<hash>.lock`, e o segundo sempre
morre. A regra 8 nasceu para evitar corrida real (três despachos no mesmo
workdir — `incidents/2026-08-27-dogfooding-tres-despachos-no-mesmo-workdir-e-veredito-lido-grepa-crud.md`),
mas o mesmo mecanismo que protege proíbe o paralelismo legítimo do
produto: a bateria pede 10 despachos concorrentes e recebe 1.

Reprodução do gate de leitura (2026-09-19, worktree `p1-inc-2` @
`87a12a1`, SEM despachar nada — nenhum runner chamado, nenhum token):
bloco das linhas 50–61 extraído VERBATIM para script temporário com
`PID_DIR` de teste. Lock com PID vivo ⇒ exit 3 para dois `TASK_NAME`
diferentes (task-AAA e task-BBB caem no mesmo arquivo
`dispatch-repo-0264d3a718c504bebf6415ba8cba82855974cead.lock`, hash do
root do worktree pela expressão da linha 52); lock órfão (PID morto) ⇒
gate passa (rc=0), confirmando que a recusa é por repositório e não por
tarefa.

## Correção proposta (não aplicada — backlog, decisão D-DISPATCH 2)

Nada aplicado agora: a decisão de 2026-09-19 é "backlog line
('per-worktree lock'), not fixed now" — o lock NÃO foi tocado nesta
sessão.

Linha de backlog: trocar a granularidade do lock de repositório para
worktree/workdir da tarefa, de forma que N despachos simultâneos (a
bateria E5 inteira) coexistam e a garantia da regra 8 continue valendo
onde a corrida real aconteceu (dois despachos no MESMO workdir). O
formato já existe dentro do oracfit: regra 53 construiu single-flight
portátil por workdir (`oracfit_run_lock_acquire/release`,
`bin/lib-oracfit-root.sh`, exit 6 + takeover de lock órfão) — o lock
RNF-07 do `dispatch.sh` é o que ficou para trás, repo-wide. Quem for
implementar precisa também resolver o choque de semântica do exit 3:
hoje o mesmo código significa "uso" (preflight, linha 41) e "lock
ocupado" (linha 59) — o chamador não distingue.

## Pode acontecer de novo?

Sim — todo uso paralelo do caminho canônico de dispatch bate no mesmo
muro até o lock por worktree existir: o E5 ("o experimento central",
10 tarefas), qualquer orquestrador que respeite o teto de concorrência
do próprio DECISIONS ("Keep ≤ 3 concurrent subagents") e despache 2+
tarefas ao mesmo tempo; o 2º sempre morre com exit 3 antes de gastar
token. Enquanto isso, o E5 segue não-medido por duas razões empilhadas
no mesmo documento de decisão: falta o modo YAML (T20) e falta o lock
por worktree — ou a bateria roda serializada, fora do formato do
experimento, ou fora do produto (o que a regra 2 do README proíbe:
"Run it through llms.surf, not beside it").
