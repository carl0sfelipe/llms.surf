---
id: 2026-08-13-executor-duplicado-no-mesmo-worktree-ove
titulo: executor duplicado no mesmo worktree overnight
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — owner.lock (host+pid+run id) com claim atômico no ring runner
status: fechado
---

# executor duplicado no mesmo worktree overnight

## Sintoma

Na noite coordenada de 2026-08-13 (levas de executores overnight), um segundo
executor god-mode recebeu o MESMO brief do RadioStudio (worktree
`<home-do-dono>/wt-radiostudio`, branch `overnight/2026-08-13`, backlog ROADMAP
Áudio/TTS itens 1-4) enquanto um primeiro executor já estava no meio do run
`ananke-20260813-0323`. O passo 1 do setup do segundo executor falhou:

```
$ git -C <home-do-dono>/RadioStudio worktree add <home-do-dono>/wt-radiostudio -b overnight/2026-08-13
fatal: a branch named 'overnight/2026-08-13' already exists   (exit 255)
```

Ao inspecionar, o worktree já tinha RING-1 e RING-2 fechados (APPROVED 4.6 e
4.7) e RING-3 recém-aberto, com `app/core/radio_config.py` modificado 82 s
antes da checagem (`stat`: mtime 03:40:57, checado 03:42:19) — sessão viva em
pleno build.

## Causa

Coordenação da noite protegeu apenas a COLISÃO DE RUN ID (sleep de
espaçamento de init, porque o run id tem granularidade de minuto), mas nada
protegeu a COLISÃO DE ALVO: o coordenador despachou dois executores com o
mesmo target e o mesmo setup "crie o worktree e rode ring init". Evidência da
duplicação: o brief do segundo executor dizia "duas sessões iniciam antes de
você" e mandava criar o worktree — ou seja, o coordenador não esperava que o
alvo já estivesse ocupado — enquanto o ledger do ring
(`<home-do-dono>/wt-radiostudio/ring/ledger.jsonl`) mostra init às 03:23 e
progresso contínuo (RING-1 open 03:26, close 03:35; RING-2 open 03:36, close
03:39; RING-3 open 03:40). Detalhe que reforça a duplicação (e não reuso
deliberado): os briefs divergem — ceiling 3 no segundo executor vs ceiling 4
gravado em `ring/state.json`.

Nota: `bin/pre-dispatch-check.sh` (gate de concorrência) protege dispatch de
MODELO, não a atribuição de um executor-orquestrador a um target; `ring init`
não grava lock de dono no worktree.

## Correção aplicada

Nenhuma mudança de código. Mitigação operacional do segundo executor: detectou
a sessão viva por evidência (mtimes + ledger) ANTES de tocar qualquer arquivo,
ficou read-only, monitorou até o run fechar (3/4 anéis, backlog esgotado,
oráculo re-verificado independente: 113 passed) e registrou este incidente. O
dano foi zero porque o `worktree add` falhou alto e o segundo executor tratou
o exit 255 como sinal de investigação, não como obstáculo a contornar.

## Pode acontecer de novo?

Sim. Qualquer noite com N executores e atribuição manual de alvos repete o
risco, e o modo de falha ruim é o silencioso: dois executores editando a mesma
árvore não commitada, verdicts sobrescritos, close com pathspec misto.
Mecanismo candidato: `ring init` grava `ring/owner.lock` (host + pid + run id)
e `ring open`/`ring close` recusam quando o lock pertence a outro dono vivo;
executor que encontra branch/worktree existente PARA e verifica vida antes de
qualquer escrita (o que aqui foi julgamento, não mecanismo).

## Fechamento (2026-08-22)

O mecanismo candidato chegou pelo merge de overnight/2026-08-13 (commit
69ae767): `ring init` reivindica posse de forma atômica (flock) e grava
ring/owner.lock (host + pid + run id); init/open/close recusam quando o lock
pertence a um dono estrangeiro VIVO; pid morto é adotado com rotação auditada
de token; lock ilegível é tratado como QUEBRADO alto, não silenciosamente.
Código: bin/oracfit-ring.sh (owner_guard). Testes: tests/test-ring-runner.sh
T25 (dono vivo estrangeiro, adoção de pid morto, lock corrompido, lock
invisível ao porcelain). Nota honesta: a outra metade da proteção candidata
("executor que encontra branch/worktree existente PARA e verifica vida antes
de qualquer escrita") segue sendo protocolo de julgamento (SKILL.md), não
código — o lock cobre quem chega PELO runner.
