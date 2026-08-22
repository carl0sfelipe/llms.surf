---
id: 2026-08-13-ruido-de-warn-de-identidade-specs-de-cri
titulo: ruido de warn de identidade, specs de critic orfas e abort sem motivo
data: 2026-08-13
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/ring-preflight.sh (identidade do run é válida), bin/oracfit-ring.sh (abort exige motivo ou notas), specs/dispatch-transientes/.gitignore; pinado por tests/test-ring-runner.sh T16/T19
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-13-ring-init-em-worktree-vaza-hook-pro-repo.md — o débito 8 é efeito colateral direto do débito 3 de lá: o init passou a setar ring@oracfit.local, que casa com o regex de default de host (`@.*\\.local$`) do preflight"
---

# ruído de warn de identidade, specs de critic órfãs e abort sem motivo

Três débitos MENORES reportados pelo executor do isef (run
`ananke-20260813-0421`), rodada 3 da noite de 2026-08-13.

## Sintoma

**Débito 8 — WARN de identidade contradiz o init.** A rodada 1 fez o init
setar identidade local do run (`oracfit-ring <ring@oracfit.local>`) quando a
efetiva estava vazia — mas o preflight continuava emitindo, a CADA open,
`preflight WARN: identidade git ausente/default: 'ring@oracfit.local'`. O
framework avisava sobre a identidade que ele mesmo colocou de propósito:
ruído que treina executor a ignorar warning.

**Débito 9 — specs de critic órfãs em `specs/`.** Todas as sessões da noite
despacharam critics com spec transiente escrita em `specs/` do oracfit, que
fica untracked e acumula. Contagem no momento da correção
(`git status --short specs/`): **5 órfãs** — `isef-ring1-critic.md`,
`vagai-ring1-critic.md`, `vagai-ring1-report.md`,
`vagai-ring2-adapters-inprocess.md`, `vagai-ring2-critic.md`. NÃO foram
movidas: são evidência das sessões vivas; a limpeza é decisão de dono.

**Débito 10 — `ring abort` não exigia registro do motivo em par com o
close.** O contrato do close exige `notes/<RING>.md`, mas o abort fechava o
anel com o motivo posicional como única exigência (e a ausência caía num
genérico "uso", exit 3, sem nomear o problema de auditoria). Um abort sem
motivo escrito em lugar nenhum vira buraco de auditoria no ledger.

## Causa

- Débito 8: o email do run termina em `.local` e casava com o regex
  `@.*\.local$` do check de default-de-host em `bin/ring-preflight.sh` — a
  exceção não foi criada quando a rodada 1 introduziu a identidade do run
  (correção de um gate sem varrer quem CONSOME o estado que ela cria; mesma
  família da interação guard×ring da rodada 2).
- Débito 9: nenhum lugar canônico para spec transiente de dispatch —
  `specs/` era o caminho de menor resistência e nada o gitignorava.
- Débito 10: assimetria de contrato — o close ganhou exigência de notas nos
  incidentes de 2026-08-12, o abort ficou para trás.

## Correção aplicada

Aplicada ATOMICAMENTE (cp pra `.new` + `mv`; sessões vivas leem do disco).
Sem commit (decisão de dono). Escopo fechado nos três itens.

- `bin/ring-preflight.sh:53-62` — identidade do run (`ring@oracfit.local` ou
  `user.name` = `oracfit-ring`, lidos do escopo efetivo do alvo) é VÁLIDA e
  silencia o WARN (também sob `--strict-identity`, pois é escolha deliberada
  do framework); identidade vazia de verdade continua avisando.
- `specs/dispatch-transientes/.gitignore` (novo: `*` + `!.gitignore`,
  commitável) — lugar canônico para spec transiente de dispatch; documentado
  em comentário curto no header de `bin/critic-guard.sh:40-42` (nascer lá ou
  em `$TMPDIR`).
- `bin/oracfit-ring.sh:574-588` — `ring abort` exige motivo não-vazio
  (whitespace não conta) OU `ring/notes/<RING>.md` existente; com notas e
  sem motivo, o `reason` do ledger aponta para as notas
  (`ver ring/notes/<RING>.md`); ambos ausentes → RECUSADO (exit 1) com
  mensagem que nomeia o buraco de auditoria. Aborts já gravados no ledger
  não são revalidados — nada quebra.
- `tests/test-ring-runner.sh` — T16 ganhou 3 asserts (preflight não avisa
  sobre a identidade do run, nomeia-a, e identidade vazia DE VERDADE segue
  avisando); T19 novo (abort mudo recusa com anel aberto; com motivo aceita
  e o ledger carrega o reason; sem motivo mas com notas aceita apontando
  para elas). Suítes: test-ring-runner 54 PASS/0 FAIL,
  test-critic-guard 44 PASS/0 FAIL.

## Pode acontecer de novo?

Os três, não, nos pontos corrigidos — mecanismo em código, pinado por
T16/T19 em `tests/test-ring-runner.sh` e pelo `.gitignore` de
`specs/dispatch-transientes/`. Resíduo: as 5 specs órfãs continuam em
`specs/` até decisão de dono, e o hábito de despachar spec para `specs/` só
morre quando os briefs/skills de dispatch apontarem o dir novo — o
comentário no critic-guard documenta, não força (forçar exigiria validar o
path da spec no dispatch, fora do escopo desta rodada).
