---
id: 2026-08-13-hook-do-critic-guard-mascarado-em-alvo-w
titulo: hook do critic-guard mascarado em alvo worktree com ring
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/critic-guard.sh (cfg_scope: arma/lê/restaura no escopo ativo do alvo, --worktree quando worktreeConfig), pinado por tests/test-critic-guard.sh T14
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo.md — foi a correção de lá (core.hooksPath --worktree do ring) que criou esta janela; o frontmatter daquele incidente já registrava a interação e mandava revisar o do_arm, o que esta correção fecha"
---

# hook do critic-guard mascarado em alvo worktree com ring

## Sintoma

Em alvo worktree onde o ring armou `core.hooksPath --worktree` (mecanismo da
rodada 1 de 2026-08-13, incidente
`2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo.md`), o `arm` do
`bin/critic-guard.sh` — que gravava `core.hooksPath --local` — não tinha
efeito: a camada de hook fail-closed do guard (pre-commit/pre-push que marcam
violação e recusam) ficava CEGA. Um critic podia tentar `git commit` sem o
hook do guard disparar; restava só a camada de vigia (porcelain/HEAD), que
detecta e mata, mas não recusa o commit na hora nem marca `violation` pelo
canal do hook.

Antes da correção, o cenário do T14 novo reproduzia: hooksPath EFETIVO no
worktree continuava apontando para `ring/hooks` (o valor `--worktree` do
ring), não para os hooks da janela do guard.

## Causa

Precedência de escopo do git config: worktree > local. O
`2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo.md` introduziu
`extensions.worktreeConfig` + `core.hooksPath --worktree` para escopar o hook
do ring por-worktree (correto para aquele problema), e o frontmatter daquele
incidente já declarava a interação: "config --worktree tem PRECEDÊNCIA sobre
--local, então em alvo worktree com ring o hook do guard fica mascarado (o
vigia por porcelain/HEAD do guard segue cobrindo). Revisar se o do_arm deve
detectar worktreeConfig e armar em --worktree." O `do_arm`, o `cfg_get` e o
`cfg_restore` do guard eram todos fixos em `--local`.

## Correção aplicada

Aplicada ATOMICAMENTE (cp pra `.new` + `mv`). Sem commit (decisão de dono).

- `bin/critic-guard.sh:128-153` — novo `cfg_scope()`: se o alvo é worktree
  (git-dir físico ≠ common-dir físico) E `extensions.worktreeConfig` está
  ligada, o escopo é `--worktree`; senão `--local` (worktree SEM
  worktreeConfig não aceita `--worktree`, e nele o `--local` funciona porque
  nada o mascara). `CFG_SCOPE` é derivado deterministicamente a cada
  invocação — arm e check recomputam o mesmo valor do mesmo alvo.
- `cfg_get`/`cfg_restore` e os três writes do `do_arm` (`core.hooksPath`,
  `user.name`, `user.email`) usam `$CFG_SCOPE` — o guard salva o valor
  anterior DO ESCOPO CERTO no arm (ex.: o `ring/hooks` do ring) e o restaura
  no desarme, então a janela não desliga o guard do ring ao fechar.
- `tests/test-critic-guard.sh` T14 — alvo worktree com `core.hooksPath
  --worktree` apontando para hooks do ring: após `arm`, o hooksPath EFETIVO
  aponta para a janela do guard (não mascarado); commit do critic é RECUSADO
  pelo hook com HEAD intacto; `check` devolve violação (exit 5); e o
  hooksPath do ring é restaurado no desarme. Suíte inteira: 44 PASS, 0 FAIL.

## Pode acontecer de novo?

Este mascaramento específico, não — o guard arma no escopo que estiver ativo
e T14 pina o cenário worktree-com-ring de ponta a ponta. A classe geral
(nova camada de config com precedência maior mascarando um guard armado em
camada menor) permanece possível para escopos que o git venha a ganhar ou
para outros guards fixos em `--local`; a lição operacional é a do frontmatter
da rodada 1: toda mudança de escopo de config em um mecanismo DEVE varrer os
demais mecanismos que tocam as mesmas chaves (aqui: `core.hooksPath`,
`user.name`, `user.email`).
