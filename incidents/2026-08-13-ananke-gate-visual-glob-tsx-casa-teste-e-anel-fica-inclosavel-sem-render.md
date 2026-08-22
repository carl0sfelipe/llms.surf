---
id: 2026-08-13-ananke-gate-visual-glob-tsx-casa-teste-e-anel-fica-inclosavel-sem-render
titulo: ANANKE (god mode v4 beta, 1º field test real) gate visual com glob *.tsx casa arquivo de TESTE e o anel fica INCLOSÁVEL quando a sessão proíbe render — as únicas saídas eram adulterar a trave ou plantar evidência fake; o executor abortou e commitou fora do anel, quebrando a contabilidade que o modo existe para garantir
data: 2026-08-13
recorrivel: sim
regra: nao — 3 regras candidatas para a v4 no corpo
status: aberto
interage_com: "2026-08-12-godmode-btc-critic-read-only-commitou-o-trabalho-e-travou-2h-sem-relatorio"
interage_com: "2026-08-11-vision-gate-decorativo-run-passa-com-verdict-rejected"
interage_com: "2026-08-11-screenshot-fullpage-lazy-load-imagem-branca-falso-positivo-vision-gate"
interage_com: "2026-08-12-vision-gate-barra-inalcancavel-prompt-default-rejected"
---

# ANANKE — gate visual falso-positivo torna o anel inclosável (field test 1)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo | ananke (`core/modes/ananke.yaml`), run `ananke-20260813-0321`, teto 4 |
| Alvo | worktree `<home-do-dono>/wt-btc` (BTC-Daytrade-Tycoon, branch overnight/2026-08-13) |
| Duração / anéis | ~25 min de anel; 1 open, 0 close, 1 abort |
| Papéis | executor frontier (host Cursor); critic fresco despachado (deepseek-v4-flash-free via runner opencode) sob `bin/critic-guard.sh run` (budget 900s) |
| Oráculo | `npx vitest run` — 995/1 na abertura, 996/0 no fechamento tentado |
| Quem pegou o quê | oráculo e critic verdes (APPROVED 4.8, claims-check 3+ contra artefato); quem travou foi o PRÓPRIO GATE do close, num falso-positivo |

## Contexto

Primeiro field test real do `oracfit ring` v4 + `critic-guard` numa sessão
overnight com regras do dono: **sem next dev/build, sem playwright**
(browsers/build pesados à noite). Story do anel: reativar o último
`it.skip` da suíte unit — diff de UM arquivo, `*.test.tsx`, zero delta de
UI, zero código de produto.

## O que funcionou ANTES da falha (evidência)

1. **critic-guard em produção**: critic fresco leu diff, VERIFICOU claims
   (aritmética contra `src/lib/trading/margin.ts`, suíte re-rodada por ele:
   996/0, arquivo isolado 11/11), gravou `ring/verdicts/RING-1.json`
   APPROVED 4.8 — e o guard confirmou "árvore intacta, veredito foi o
   único write". A resposta mecânica ao incident do critic rogue de
   2026-08-12 funcionou na primeira exposição real.
2. **check-verdict fail-closed** aceitou o veredito (biggest_gap
   não-evasivo, YELLOW registrado).
3. **Oráculo monotônico** verde: 996 passed / 0 skipped.

## A falha

`oracfit ring close RING-1 -- src/components/trading/TradeControls.hedge.test.tsx CHECKPOINTS.md`
→ **RECUSADO (visual_sem_screenshot), tentativa 1/5**:

    diff tocou artefato visual:
    src/components/trading/TradeControls.hedge.test.tsx
    gate visual: coloque >=1 screenshot em .../ring/screens/RING-1/

Causa mecânica: `visual_globs` default do state.json inclui `*.tsx` e o
predicado (`oracfit_visual_hits`, fnmatch puro em `lib-oracfit-preflight.sh`)
não distingue `*.test.tsx` de componente — arquivo de TESTE conta como
"tela". O gate então exige um render real que:

- a sessão PROIBIA produzir (sem next dev/playwright, por regra do dono); e
- nem faria sentido: o diff não muda nenhum pixel.

## O beco (por que não havia saída limpa)

| Saída possível | Por que foi recusada |
|---|---|
| Editar `visual_globs` no state.json com o anel aberto | Adulterar a trave para passar — classe proibida pelo próprio modo; state.json não tem guarda sha (a trave do oráculo tem), então seria silencioso e IMPUNE: pior ainda |
| Plantar arquivo em `ring/screens/RING-1/` (o gate conta ARQUIVOS, não valida render) | Evidência fake — classe dos incidents de vision-gate de 2026-08-11/12; o executor estaria fabricando exatamente o que o gate quer provar |
| Screenshot real | Impossível sem servidor/browser (proibidos); e um render "de mentira" (HTML estático do componente) não é "a tela de verdade" |
| `ring abort` + commit fora do anel | **Foi a escolhida** — honesta, mas quebra a contabilidade: o trabalho existe no branch com o veredito anexado, porém SEM evento `close` no ledger, sem checkpoint mecânico, sem `ring score` possível (score exige close). O modo perde exatamente o que promete |

Nota dupla do falso-positivo: além de casar arquivo de teste, o gate conta
qualquer arquivo em `screens/` como prova (nshots é `ls | wc -l`) — o
mesmo gate que recusa um diff inocente aceitaria um `touch fake.png`. As
duas pontas convergem para a mesma lição dos vision-gates: gatilho e prova
precisam ambos ser semânticos, não sintáticos.

## Regras candidatas para a v4

1. **Excluir teste dos gatilhos visuais por default**: `visual_globs`
   defaults não devem casar `*.test.*` / `*.spec.*` / `__tests__/*` /
   `e2e/*` (o predicado já recebe globs por config; é mudança de default +
   negação no fnmatch). Diff test-only não é tela.
2. **Válvula sancionada de no-visual-delta, espelhando a da trave**:
   `DECLARACAO-VISUAL:` nas notas + `visual_change_approved: true|false`
   no veredito do critic (que é fresco e já verifica claims) — o executor
   DECLARA que o diff não altera render, o critic JULGA, o close valida
   mecanicamente. Sem isso, todo falso-positivo do gatilho força escolha
   entre trapaça e abort.
3. **`ring/state.json` sob a mesma guarda sha da trave**: a análise do
   beco revelou que editar `visual_globs` com anel aberto passaria em
   silêncio — o close não confere hash do state. Guardar o state fecha o
   buraco que este incident quase tornou tentador.

## Evidência preservada

- Ledger do anel (open / close_attempt visual_sem_screenshot / abort com
  motivo integral): `ring/ledger.jsonl` no branch `overnight/2026-08-13`
  do BTC-Daytrade-Tycoon (commit `60fb97d`, que carrega também
  `ring/notes/RING-1.md` e `ring/verdicts/RING-1.json` APPROVED 4.8).
- Recusa literal do close: saída no terminal do executor às 03:31 (tentativa
  1/5, oráculo verde 996/0 na mesma saída).
- Predicado do gate: `bin/lib-oracfit-preflight.sh` (fnmatch em basename,
  sem negação) e defaults em `bin/oracfit-ring.sh:242`.
- Guard limpo do critic: "LIMPO: dispatch terminou (rc=0), árvore de
  <home-do-dono>/wt-btc intacta" (stdout do critic-guard, 03:29).

## O que este incident PROVA pra v4

1. O caminho feliz do v4 funciona de ponta a ponta em campo (guard +
   veredito de arquivo + oráculo) — a primeira falha real veio de um GATE,
   não de um papel: o fail-closed está apontado na direção certa, mas
   gatilho sintático converte inocência em impasse.
2. Fail-closed sem válvula sancionada não elimina a trapaça — ela apenas
   muda de nome (adulterar trave, plantar evidência) e fica MAIS tentadora
   sob pressão de teto. A válvula com julgamento do critic é o que
   transforma "impossível honestamente" em "caro, auditado e possível".
3. Abort + commit fora do anel é a válvula de fato de hoje — e ela custa a
   contabilidade inteira (close, checkpoint, score). Toda sessão que cair
   no mesmo beco vai escolher entre mentir e sair do sistema de medição.

## Pode acontecer de novo?

Sim — qualquer anel test-only em repo React/TSX repete o beco enquanto os
defaults casarem `*.tsx` sem exclusão de teste, e qualquer sessão sem
render permitido (overnight, CI leve) fica sem saída sancionada. Até as
regras 1–2 existirem, o gate visual é uma armadilha determinística para a
classe de trabalho mais comum de god mode noturno: pagar dívida de teste.
