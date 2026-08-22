---
id: 2026-08-13-init-engole-recusa-de-hook-retest-anulad
titulo: init engole recusa de hook, retest anulado por cache e hook do dono escondido
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/oracfit-ring.sh (init fail-closed sob hook do alvo; durations_ms + retest_suspeito no close; chain do pre-commit do dono; DECLARACAO aceita heading), pinado por tests/test-ring-runner.sh T20-T23
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo.md — o débito 13 é efeito colateral do hooksPath --worktree de lá (escopo certo, mas ESCONDIA o pre-commit do dono no worktree); o chain fecha a lacuna"
interage_com: "regra do hook do ring (aion sintoma 4) — o chain preserva o bloqueio commit-só-via-runner e ACRESCENTA o gate do dono; o bypass ORACFIT_RING_COMMIT=1 pula só o bloqueio do ring, nunca o hook do dono (sem --no-verify em lugar nenhum)"
---

# init engole recusa de hook, retest anulado por cache e hook do dono escondido

Quatro débitos do executor do leadher (run `ananke-20260813-0412`, repo com
commitlint/lefthook + turbo), rodada 4 (última) da noite de 2026-08-13.

## Sintoma

**Débito 11 (P1) — commit do init falha em SILÊNCIO sob commitlint.** As
mensagens `ring:`/`ring(...)` violam o type-enum do alvo, o hook recusa, o
`|| true` do init engolia, e o scaffold ficava staged-mas-não-commitado. O
primeiro close recusava depois por `staging_com_resto_alheio` — sintoma longe
da causa, horas de diagnóstico do executor.

**Débito 12 (P1) — retest descorrelacionado ANULADO por cache do runner.**
No close do RING-1 do leadher a 2ª rodada do oráculo foi "FULL TURBO" em
77ms — no-op de cache do turbo, proteção anti-flake oca. Agravante: TODOS os
eventos close da noite gravam `"duration_s": 0` — `date +%s` tem
granularidade de segundo e qualquer suíte sub-segundo (ou cacheada) zera, o
que escondeu a rodada-espelho do próprio ledger.

**Débito 13 — hook do ring não coexistia com pre-commit alheio.** Em alvo
worktree, o `core.hooksPath --worktree` (rodada 1) faz git buscar TODOS os
hooks em `ring/hooks/` — o pre-commit do REPO (lefthook) deixava de disparar
naquele worktree: o gate do dono sumia em silêncio. Em alvo não-worktree com
pre-commit alheio, a recusa de instalar era uma linha fácil de perder.

**Débito 14 (doc) — `^DECLARACAO-ORACULO:` só casava âncora simples.** O
leadher escreveu a declaração como heading markdown
(`## DECLARACAO-ORACULO: …`) e perdeu 1 tentativa contável de close; a
mensagem de recusa não dizia o formato esperado.

## Causa

- 11: `|| true` no commit de scaffold — tolerância pensada para "nada a
  commitar" engolia QUALQUER falha, inclusive gate do dono recusando.
- 12: medição em segundos inteiros (`date +%s`) + nenhuma medição por rodada
  do retest — a única evidência que denunciaria a rodada-espelho não existia.
- 13: `core.hooksPath` redireciona TODOS os hooks, não adiciona — escopar o
  hook do ring por-worktree (correto) teve o efeito colateral de esconder os
  hooks originais do repo naquele worktree.
- 14: regex de âncora de linha exata, escrita antes de existir executor que
  formata notas em markdown.

## Correção aplicada

Aplicada ATOMICAMENTE (cp pra `.new` + `mv`; sessões vivas leem do disco).
Sem commit (decisão de dono). Tudo em `bin/oracfit-ring.sh` + testes.

- **11** `bin/oracfit-ring.sh:339-364` — commit do scaffold NUNCA engole
  falha: desfaz o staging (nada fica staged em silêncio), imprime o erro do
  hook, acrescenta a hipótese "hook do repo recusou a mensagem 'ring: …' —
  commitlint/lefthook?" quando há commit-msg/pre-commit não-nosso no
  hooksPath efetivo ou no common dir, e sai com exit 2 (QUEBRADO). SEM
  `--no-verify` — hook do alvo é gate do dono.
- **12a** `bin/oracfit-ring.sh:48` (`now_ms`), `:496-503` e `:513-521` —
  cada rodada do oráculo medida em ms; evento close ganha
  `oracle.durations_ms: [r1, r2, …]` e `duration_s` vira float com precisão
  de ms (fixture: `duration_s: 6.047` onde antes seria 0 ou 6).
- **12b** `bin/oracfit-ring.sh:526-541` — rodada-espelho: rodada1 ≥ 5000ms E
  rodada2 < 10% da rodada1 → `retest_suspeito: true` no evento close + WARN
  no stderr nomeando cache de runner (turbo/jest) e o remédio
  (`turbo run test --force` no oracle.sh). NÃO bloqueia — suíte legítima
  rápida nas duas rodadas seria falso positivo; a evidência no ledger é o
  mecanismo. Valores medidos do fixture (dorme 6s na 1ª, instantâneo na 2ª):
  `durations_ms=[6028, 19]`, `retest_suspeito=true`.
- **13** `bin/oracfit-ring.sh:205-233` e heredoc do hook — o pre-commit
  instalado em `ring/hooks` (worktree), depois do próprio check, ENCADEIA
  via `exec` o pre-commit original do common dir se existir e for executável
  (exit code propagado; hook vazado NOSSO da noite não é re-executado — grep
  pela assinatura). O bypass `ORACFIT_RING_COMMIT=1` pula só o bloqueio do
  ring: o hook do dono roda até nos commits do próprio runner. Em alvo
  não-worktree com pre-commit alheio, a recusa de instalar agora grita:
  "MECANISMO AUSENTE: commit-só-via-runner sem hook — pre-commit alheio
  presente" (`:226`).
- **14** `bin/oracfit-ring.sh:466-472` — aceita
  `^(DECLARACAO-ORACULO:|#{1,6}[[:space:]]*DECLARACAO-ORACULO)` e a recusa
  `oraculo_mudou_sem_declaracao` documenta o formato exato numa linha.
- **Testes** `tests/test-ring-runner.sh` T20 (commitlint fixture recusa
  `ring:` → init falha ALTO com diagnóstico e staging limpo), T21
  (durations_ms + retest_suspeito=true no fixture 6s/instantâneo; oráculo
  rápido nas duas rodadas do T14 sem flag), T22 (worktree com hook alheio no
  principal: guard do ring dispara primeiro, hook do dono roda via chain nos
  commits livres E nos do runner, exit code do dono propagado), T23 (heading
  markdown fecha; recusa documenta o formato). Suítes: test-ring-runner
  68 PASS/0 FAIL, test-critic-guard 44 PASS/0 FAIL.

## Pode acontecer de novo?

Os quatro pontos, não — mecanismo em código, pinado por T20-T23. Residual
declarado: (a) a detecção de espelho compara rodadas 1 e 2 — cache que só
aquece na rodada 3+ de `retest_runs` maiores não flagra (aceito: o default é
2 rodadas); (b) o chain cobre só `pre-commit` — em worktree com hooksPath,
os DEMAIS hooks do dono (commit-msg, pre-push) continuam escondidos e NÃO
rodam (nem recusam): um alvo que dependa de commitlint puro via commit-msg
fica sem esse gate dentro do worktree do run. Estender o chain a
commit-msg/pre-push é pendência de dono, fora do escopo fechado desta
rodada; em alvo NÃO-worktree todos os hooks do dono seguem intactos e uma
recusa deles agora falha ALTO no init (débito 11).
