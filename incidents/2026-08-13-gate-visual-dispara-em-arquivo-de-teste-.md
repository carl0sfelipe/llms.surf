---
id: 2026-08-13-gate-visual-dispara-em-arquivo-de-teste-
titulo: gate visual dispara em arquivo de teste tsx e derruba anel test-only
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — exclusão de caminho de teste em oracfit_visual_hits (globs default)
status: fechado
---

# gate visual dispara em arquivo de teste tsx e derruba anel test-only

## Sintoma

Overnight 2026-08-13, run `ananke-20260813-0321` (BTC-Daytrade-Tycoon, worktree
`<home-do-dono>/wt-btc`): RING-1 era test-only — reativar o único `it.skip` de
`src/components/trading/TradeControls.hedge.test.tsx` (zero delta de UI). O
close foi recusado com `close_attempt reason=visual_sem_screenshot` e a sessão
abortou o anel pelo protocolo (3º close_attempt não chegou a ser necessário;
o executor julgou o gate insatisfazível para diff sem UI).

Eventos no ledger central (`ledger/ledger.jsonl`):

    {"run": "ananke-20260813-0321", "ring": "RING-1", "event": "close_attempt", "reason": "visual_sem_screenshot"}
    {"run": "ananke-20260813-0321", "ring": "RING-1", "event": "abort", "reason": "visual gate false-positive: glob *.tsx casa arquivo de TESTE (diff test-only, zero delta de UI) e exige screenshot; regr..."}

## Causa

`oracfit_visual_hits` (bin/lib-oracfit-preflight.sh) classifica por glob de
extensão (`*.tsx` etc.) sem excluir convenções de arquivo de teste
(`*.test.tsx`, `*.spec.tsx`, `__tests__/`). Um diff composto só de teste de
componente dispara o gate visual e o close exige screenshot de UI que não
mudou. Fail-closed correto na direção errada: o gate deveria olhar delta de
UI, não extensão crua.

## Correção aplicada

Nenhuma ainda (incident aberto durante a noite para não perder o achado; a
sessão dona do repo abortou o anel e parou — comportamento correto).
Mecanismo candidato: excluir `*.test.*`, `*.spec.*`, `__tests__/`,
`tests/` dos globs default de `oracfit_visual_hits`, com teste em
tests/test-gates-dispatch.sh cobrindo diff test-only → gate NÃO dispara.

## Pode acontecer de novo?

Sim — qualquer anel test-only em repo React/TSX vai bater no mesmo falso
positivo até o mecanismo ser corrigido. Deve virar correção de código (C),
não regra de protocolo: o glob é executável e testável.

## Fechamento (2026-08-22)

Implementado como o incidente pediu: oracfit_visual_hits exclui caminhos de
teste (*.test.*, *.spec.*, test_., _test., dirs test/tests/__tests__/__mocks__
/__snapshots__/spec) QUANDO os globs efetivos são o default (inclusive os
semeados no state.json pelo init) — globs custom são respeitados ao pé da
letra, decisão registrada no próprio código. Código:
bin/lib-oracfit-preflight.sh. Testes: tests/test-gates-dispatch.sh (default
exclui .test.tsx/tests//__tests__ e mantém tsx/css normais; globs custom não
sofrem exclusão). Recorrência declarada: sim — o corpo já dizia; o campo
seguiu "?" por descuido de quem abriu o incidente à noite.
