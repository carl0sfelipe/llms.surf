---
id: 2026-08-12-run-marcado-fail-com-oraculo-verde-no-di
titulo: run marcado fail com oraculo verde no disco — gauntlet avaliou antes do ultimo write do modelo
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (classe C, 2026-08-12 v3.5): dispatch-mode.sh reavalia o oraculo sobre o estado FINAL do disco antes de fechar run como fail (evento oracle_final_recheck; oraculo verde no fechamento vira pass e oracle_exit=0 no ledger — ADR-0002, o ledger mede o disco); de quebra o epilogo pos-loop virou melhor-esforco (set +e) para run_finished/ledger nunca morrerem mudos (incidente 2026-08-10-dispatch-mode-run-finished)
status: promovido
---

# run marcado fail com oraculo verde no disco — gauntlet avaliou antes do ultimo write do modelo

## Sintoma

Run `8BC4469E-2EEE-4FFF-B244-68F2EFECDD0E` (workdir `<home-do-dono>/poker-club-os`,
mode `normal`, spec `specs/clock-engine-core.md`, task `clock-engine-core`)
terminou com `status: fail, attempts: 5, oracle_exit: 1` no ledger
(`<home-do-dono>/poker-club-os/.dispatch/ledger/mode.jsonl`), mas o oráculo da
spec, rodado verbatim pelo orquestrador logo em seguida no mesmo workdir,
retornou exit 0:

```
cd <home-do-dono>/poker-club-os && npx tsc --noEmit -p packages/clock-engine \
  && npx vitest run --reporter=basic 2>&1 | grep -qiE '[0-9]+ passed' \
  && grep -q 'class TournamentClock' packages/clock-engine/src/index.ts \
  && grep -q 'fromJSON' packages/clock-engine/src/index.ts \
  && ! grep -qE 'Date\.now|setInterval|setTimeout' packages/clock-engine/src/index.ts
# → exit 0; vitest: "Tests  11 passed (11)"; tsc: exit 0
```

O trabalho estava completo e verde no disco; o ledger diz que falhou.
Falso-fail: inverso do falso-sucesso das regras 24/31/44, mesma família
(sinal do sistema diverge do estado real do artefato).

## Causa

Não determinada com precisão de linha, mas a sequência no log do run mostra:
na última tentativa o modelo rodou o oráculo com typo próprio
(`--reporter=basics`), viu falha, corrigiu para `--reporter=basic` e obteve
`ORACLE_EXIT=0` — tudo DENTRO da mesma attempt, depois do ponto em que o
gauntlet já tinha avaliado o oráculo daquela attempt (ou a attempt 5 estourou
o teto `safety_ceiling: 5` do mode `normal.yaml` com a avaliação do gauntlet
feita sobre um estado anterior ao último write/fix do modelo). O gauntlet
gravou `oracle_exit: 1` e fechou o run como fail sem reavaliar o oráculo
sobre o estado FINAL do disco antes de finalizar o ledger.

## Correção aplicada

Nenhuma no código ainda. O orquestrador validou o oráculo manualmente
(exit 0) e seguiu com o trabalho — o dano foi só o registro incorreto no
ledger (dado falso em store de decisão, ver regra 25).

Correção sugerida: em `bin/dispatch-mode.sh` / `bin/lib-oracfit-gauntlet.sh`,
antes de finalizar o run como fail por esgotar tentativas, rodar o oráculo
UMA última vez sobre o estado final do disco e usar ESSE exit no ledger
(ADR-0002: artefato em disco é a fonte única de conclusão — o ledger deve
medir o disco, não a memória da última avaliação).

## Pode acontecer de novo?

Sim — sempre que o modelo corrigir o trabalho depois da avaliação do oráculo
da última attempt (típico quando o próprio modelo roda o oráculo no fim da
resposta e se autocorrige). Enquanto o fechamento do run não reavaliar o
disco, todo run nessa janela grava fail falso no ledger e pode disparar
retrabalho/rollback de trabalho bom (mesmo custo da regra 39).
Promover quando o fix entrar:
  bin/incident.sh promote 2026-08-12-run-marcado-fail-com-oraculo-verde-no-di "<texto da regra>"
