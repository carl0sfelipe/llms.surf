---
id: 2026-08-13-gate-visual-exige-screenshot-de-diff-tes
titulo: gate visual exige screenshot de diff test-only e aborta anel inclosavel
data: 2026-08-13
recorrivel: sim
regra: mecanismo aplicado — bin/lib-oracfit-preflight.sh (exclusão de teste no default) + tests/test-gates-dispatch.sh (T1 pina)
status: aberto
interage_com: "2026-08-13-ananke-gate-visual-glob-tsx-casa-teste-e-anel-fica-inclosavel-sem-render"
---

# gate visual exige screenshot de diff test-only e aborta anel inclosavel

## Sintoma

Run `ananke-20260813-0321` (BTC-Daytrade-Tycoon, worktree `<home-do-dono>/wt-btc`),
RING-1: diff de UM arquivo — `src/components/trading/TradeControls.hedge.test.tsx`
(reativação de um `it.skip`, zero delta de UI) — e o `oracfit ring close`
recusou exigindo screenshot. Sessão overnight proibia next dev/playwright
(único render legítimo), então o anel ficou inclosável sem adulterar a trave
ou plantar evidência fake; o executor abortou. Evidência do ledger central
(`ledger/ledger.jsonl`, linhas 120 e 129):

    {"ts": "2026-08-13T06:31:01+00:00", ... "run": "ananke-20260813-0321", "ring": "RING-1", "event": "close_attempt", "reason": "visual_sem_screenshot"}
    {"ts": "2026-08-13T06:32:55+00:00", ... "run": "ananke-20260813-0321", "ring": "RING-1", "event": "abort", "reason": "visual gate false-positive: glob *.tsx casa arquivo de TESTE (diff test-only, zero delta de UI) e exige screenshot; regras da noite proíbem next dev/playwright (único render legítimo); sem válvula sancionada tipo oracle_change_approved para no-visual-delta — anel inclosável sem adulterar trave ou plantar evidência fake. ..."}

## Causa

Os globs default de `oracfit_visual_hits` em `bin/lib-oracfit-preflight.sh`
(`*.html *.css public/* *.svelte *.vue *.jsx *.tsx`) não excluíam caminho de
teste: fnmatch puro em path/basename, então `*.tsx` casa `*.test.tsx` do
mesmo jeito que casa componente. O predicado é compartilhado pelo close do
`bin/oracfit-ring.sh` (que lê `visual_globs` do state.json, semeado pelo
`ring init` com essa mesma lista) e pelo `gauntlet_visual_gate` de
`bin/dispatch-escalate.sh` — os dois caminhos tinham o mesmo falso-positivo.
Postmortem de campo completo:
`incidents/2026-08-13-ananke-gate-visual-glob-tsx-casa-teste-e-anel-fica-inclosavel-sem-render.md`.

## Correção aplicada

- `bin/lib-oracfit-preflight.sh` (`oracfit_visual_hits`): caminho de teste
  não é hit visual. Exclusão case-insensitive de diretórios
  `(^|/)(test|tests|__tests__|__mocks__|__snapshots__|spec)/` e basenames
  `^test_` / `.test.` / `.spec.` / `_test.`. A exclusão vale SÓ quando os
  globs efetivos são o default (inclusive vindos do state.json intocado);
  globs custom (`GAUNTLET_VISUAL_GLOBS` ou state.json editado) são
  respeitados ao pé da letra, sem exclusão. Decisão: `__snapshots__` também
  excluído — snapshot de teste é artefato de teste, não evidência de tela
  renderizada.
- `tests/test-gates-dispatch.sh` T1 pina: `.test.tsx` NÃO dispara, `.tsx`
  normal dispara, `tests/foo.spec.ts` NÃO dispara, `src/Button.css` dispara,
  `__tests__/page.html` NÃO dispara, e globs custom continuam sem exclusão.
- Suítes verdes após a correção: `tests/test-gates-dispatch.sh` 19 PASS /
  0 FAIL; `tests/test-ring-runner.sh` 29 PASS / 0 FAIL (T10, gate visual do
  ring com `index.html`, intacto).

## Pode acontecer de novo?

A ponta do gatilho sintático está fechada por código (diff test-only fecha
sem screenshot). As outras duas pontas do postmortem de campo continuam
abertas: válvula sancionada de no-visual-delta (declaração + julgamento do
critic) e guarda sha do state.json — sem elas, um falso-positivo de outra
classe (ex.: asset visual renomeado sem delta de render) recria o mesmo
beco. Regras candidatas seguem no incident interligado.
