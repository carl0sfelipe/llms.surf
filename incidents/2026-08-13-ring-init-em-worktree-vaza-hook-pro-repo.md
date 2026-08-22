---
id: 2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo
titulo: ring init em worktree vaza hook pro repo principal e nao resolve identidade vazia
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/oracfit-ring.sh (is_worktree + core.hooksPath --worktree + identidade local do run), pinado por tests/test-ring-runner.sh T15/T16
status: corrigido — working tree, aguardando commit
interage_com: "bin/critic-guard.sh arma core.hooksPath em escopo --local; config --worktree tem PRECEDÊNCIA sobre --local, então em alvo worktree com ring o hook do guard fica mascarado (o vigia por porcelain/HEAD do guard segue cobrindo). RESOLVIDO na rodada 2 do mesmo dia: 2026-08-13-hook-do-critic-guard-mascarado-em-alvo-w.md (cfg_scope no guard, pinado por tests/test-critic-guard.sh T14)."
interage_com: "2026-08-13-executor-duplicado-no-mesmo-worktree-ove.md (mesma noite, mesma classe worktree-como-alvo, evento distinto)"
---

# ring init em worktree vaza hook pro repo principal e não resolve identidade vazia

Consolida os débitos 1–3 reportados pelo executor de campo do run
`ananke-20260813-0347` (alvo em worktree, noite coordenada de 2026-08-13).

## Sintoma

**Débito 1 (P1) — hook vaza pro `.git` compartilhado.** `oracfit ring init`
num worktree instalou o guard no hooks do repo PRINCIPAL: o executor reportou
`hook instalado: <home-do-dono>/CanIRunIt/.git/hooks/pre-commit`. O hook é inerte
sem `ring/state.json` no toplevel da árvore corrente, mas passa a executar em
todo commit de TODOS os checkouts daquele repo, e nenhum teardown o remove ao
fim do run. Varredura de 2026-08-13 (para cada `<home-do-dono>/wt-*`, o common
dir correspondente com `pre-commit` contendo `oracfit-ring-guard`) achou 16
repos principais com hook vazado:

```
ai-usage-hub, BTC-Daytrade-Tycoon, CanIRunIt, clubsurf, epicure-lab,
poker-freeroll-radar, oracfit, primeiras-palavras, RadioStudio, relay-juggler,
research.ai, scentmatch, torlink, tripstory-mvp1, trisub, vagai
```

(cada um em `<repo>/.git/hooks/pre-commit`; `wt-leadher` tinha pre-commit
alheio, não nosso — o install recusa e não sobrescreve). Hooks NÃO removidos:
são inertes fora de árvore com ring aberto e a limpeza é decisão de dono.

**Débito 2 — flag `--auto` do runner opencode sob suspeita.** O executor
reportou que o opencode atual não documentaria mais `--auto`. NÃO CONFIRMADO:
`opencode run --help` da 1.18.16 instalada lista a flag ("auto-approve
permissions that are not explicitly denied (dangerous!)"). Verificado também o
comportamento com flag desconhecida: o yargs NÃO engole — imprime o help e sai
com exit 1 em <1s sem executar (medido com flag bogus + model bogus), então um
sumiço futuro da flag falharia alto, não silencioso.

**Débito 3 — preflight avisa identidade vazia, init não resolve.**
`bin/ring-preflight.sh` emite `WARN: identidade git ausente/default` mas
ninguém setava identidade: o commit de scaffold do init (e todo close) saía
com autoria default de host (`user@Mac-mini-de-mac.local`) — classe já vista
em pythia/autarca.

## Causa

**Débito 1:** `install_hook` em `bin/oracfit-ring.sh` resolvia o destino com
`git rev-parse --git-path hooks`, que num worktree aponta para o COMMON DIR
(o `.git` compartilhado do repo principal) — hooks são globais ao repo, não à
árvore. Evidência: em worktree de teste, `git rev-parse --git-path hooks` →
`<main>/.git/hooks`; a suíte nova reproduz (T15 falharia no código antigo:
hook aparecia em `t15-main/.git/hooks/pre-commit`).

**Débito 2:** reporte do executor não reproduzível na versão local — causa
provável: leitura de changelog/docs de outra versão, não do `--help` do
binário instalado. Nenhum defeito no runner.

**Débito 3:** lacuna de responsabilidade — o preflight só OBSERVA (warn) e o
init, único momento com contexto de escrita, não agia sobre a observação.

## Correção aplicada

Aplicada ATOMICAMENTE (cp pra `.new` no mesmo dir + `mv` por cima — ~10
sessões god-mode vivas leem os scripts do disco). Sem commit (decisão de dono).

- `bin/oracfit-ring.sh:175-181` — novo predicado `is_worktree()`: git-dir
  físico ≠ common-dir físico (ambos canonicalizados com `pwd -P`, imune a
  symlink `/tmp` do macOS).
- `bin/oracfit-ring.sh:183-201` — `install_hook` em worktree agora faz
  `git config extensions.worktreeConfig true` + `git config --worktree
  core.hooksPath <worktree>/ring/hooks` e instala o pre-commit lá dentro;
  `git worktree remove` descarta a config junto (teardown natural). Repo
  normal continua em `--git-path hooks`, sem mudança.
- `bin/oracfit-ring.sh:274-295` — init: quando a identidade EFETIVA
  (user.name/user.email) está vazia, seta a que faltar com identidade do run
  (`oracfit-ring` / `ring@oracfit.local`) em escopo `--worktree` quando
  worktreeConfig está ligada, senão `--local`; global do dono intocado. O
  hook por-worktree (`ring/hooks/pre-commit`) entra no commit de scaffold —
  senão a pós-condição de árvore limpa do close quebraria.
- `tests/test-ring-runner.sh` T15 — init em worktree: hooks do principal
  intocado, `core.hooksPath --worktree` apontando pra dentro do worktree,
  árvore limpa pós-init, hook DISPARA no worktree (commit fora do runner
  bloqueado) e o repo principal segue commitando livre. T16 — init com
  identidade efetiva vazia (HOME/XDG vazios + GIT_CONFIG_NOSYSTEM) grava
  identidade local e o commit de init sai com autoria do run. Suíte inteira:
  37 PASS, 0 FAIL.
- `adapters/opencode/runner.sh:79-85` — comentário do `--auto` atualizado com
  a verificação de versão (1.18.16, 2026-08-13) e o comportamento medido do
  yargs para flag desconhecida. Sem mudança funcional (RNF-04 preservado).
- (débito 4, cosmético, fora do escopo deste incidente:
  `core/critic-profiles/ananke-critic.md` enum do verdict alinhado aos 5
  valores de `bin/check-verdict.py`.)

## Pode acontecer de novo?

O vazamento de hook e a identidade vazia, não — mecanismo no código do init
(não em disciplina), pinado por T15/T16 em `tests/test-ring-runner.sh`.
Resíduo desta noite: os 16 hooks vazados listados acima continuam no disco
(inertes; remoção é decisão de dono — um `rm` cego apagaria hook legítimo em
repo que já tivesse pre-commit próprio). A interação registrada no
frontmatter (guard mascarado pelo escopo `--worktree`) foi FECHADA na rodada
2 do mesmo dia: o `do_arm` do `bin/critic-guard.sh` agora detecta o escopo
ativo do alvo e arma nele (ver
`2026-08-13-hook-do-critic-guard-mascarado-em-alvo-w.md`).
