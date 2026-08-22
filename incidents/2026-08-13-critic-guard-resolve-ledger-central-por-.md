---
id: 2026-08-13-critic-guard-resolve-ledger-central-por-
titulo: critic-guard resolve ledger central por env em runtime e o daemon do prime-agent é cápsula de env — guard_armed/guard_clean do RING-2 desviados para o ledger de debug de ontem
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — bin/critic-guard.sh (resolve_central_from_state: STATE do alvo vence env) + tests/test-critic-guard.sh T13
status: aberto
interage_com: "2026-08-13-ring-ledger-central-dividido-por-env-herdado-de-shell"
interage_com: "2026-08-13-prime-agent-campo-v4-substrato-real-2-an"
---

# critic-guard desviado por env de cápsula de daemon — 2ª ocorrência da classe NO MESMO DIA

## Sintoma

No teste de campo do RING-2 (substrato prime-agent), o gate despachou o
critic fresco sob `bin/critic-guard.sh run` e tudo terminou verde — mas
`rg "critic-guard-v1" ledger/ledger.jsonl` no central oficial devolveu
ZERO linhas. Os eventos `guard_armed` e `guard_clean` existiam, íntegros,
em `/tmp/central-dbg.jsonl` — o MESMO arquivo de debug do satélite da
madrugada.

## Causa

Com EVIDÊNCIA (probe de gate que despeja o próprio env):

```
prime-agent -p --autonomous --autonomous-gate /tmp/pa-envprobe-gate.sh …
# /tmp/pa-envprobe.out:
#   ORACFIT_CENTRAL_LEDGER=/tmp/central-dbg.jsonl   ← NÃO está no shell do orquestrador
#   DISPATCH_RUNNER=…/adapters/prime-agent/runner.sh ← este SIM está no shell atual
#   probe ppid → worker filho do daemon pid 17860
```

O env do processo que executa o gate é uma MISTURA: variáveis do cliente
atual + variáveis do DAEMON do prime-agent. O daemon é uma cápsula de
env: herdou `ORACFIT_CENTRAL_LEDGER=/tmp/central-dbg.jsonl` do terminal
em que foi iniciado (sessão do dono às 01:18, num shell que ainda
carregava o override de debug da smoke de 2026-08-12 23:59 — o mesmo
`/tmp/central-dbg.jsonl` tem o open V-1 da smoke e o open A-1 do
split-brain da madrugada). Todo gate/subprocesso do daemon carrega esse
env pela VIDA INTEIRA do daemon, invisível para o operador.

O `bin/critic-guard.sh` resolvia o central por
`${ORACFIT_CENTRAL_LEDGER:-…}` em RUNTIME — exatamente o padrão que o
satélite da madrugada declarou como classe ("generalizar a auditoria
para outros scripts do bin/ que leem env ambiente em runtime"). A
auditoria não foi feita; a classe cobrou no mesmo dia, por um vetor novo
(cápsula de daemon, não shell reciclado).

## Correção aplicada

- `bin/critic-guard.sh`: `resolve_central_from_state()` — quando o alvo
  tem `ring/state.json` com `central_ledger`, o STATE vence o env (mesma
  correção do `bin/oracfit-ring.sh`); env segue como fallback para alvo
  sem ring (contrato das suítes preservado).
- `tests/test-critic-guard.sh` T13 (2 asserts): alvo com state + env
  sujo → eventos no central do state, central do env intocado. Suíte
  completa: 39 PASS, 0 FAIL.
- Backfill honesto: as 2 linhas (`guard_armed`, `guard_clean` do
  critic-ring2) copiadas de `/tmp/central-dbg.jsonl` para
  `ledger/ledger.jsonl` com campo `backfilled` apontando para este
  incident.
- NÃO corrigido (DO-DONO): o daemon 17860 continua cápsula do env sujo —
  reiniciá-lo (`prime-agent shutdown` + próxima chamada re-sobe limpo)
  derruba os agents vivos do dono; decisão de quando é do dono.

## Pode acontecer de novo?

Sim, por DUAS rotas: (a) outro script do bin/ que resolva recurso
compartilhado por env em runtime — a auditoria prometida pela candidata 2
do postmortem da madrugada continua pendente (rg por
`ORACFIT_CENTRAL_LEDGER|MODEL_REGISTRY|:-.*ledger` no bin/ e revisar um a
um); (b) qualquer daemon persistente (prime-agent, launchd, colima) como
cápsula de env de bootstrap — env de debug NUNCA deve ser exportado em
shell interativo sem prefixo de comando único (`VAR=x cmd`, não
`export VAR=x`). A rota (a) tem mecanismo pontual aplicado aqui para o
critic-guard; a auditoria geral é a pendência.
