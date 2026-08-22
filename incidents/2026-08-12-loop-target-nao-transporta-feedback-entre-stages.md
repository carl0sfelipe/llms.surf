---
id: 2026-08-12-loop-target-nao-transporta-feedback-entre-stages
titulo: "loop_target volta o índice mas não transporta o feedback: accum é por-stage e truncado na reentrada — builder reedita cego e queima o ceiling inteiro"
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo (classe C): no loop-back, transferir o feedback do stage que falhou para o accum do stage alvo + truncar o accum só na PRIMEIRA entrada do stage (fix em bin/dispatch-stages.sh; testes na seção §Teste)
status: corrigido — working tree, aguardando commit
interage_com: "2026-08-11-vision-gate-gap-nao-injetado-no-feedback-do-gauntlet"
interage_com: "2026-08-12-biggest-gap-heuristic-pega-boilerplate-em-vez-do-gap-real"
---

# `loop_target` não transporta feedback entre stages — o loop multi-stage roda cego

## Sintoma

Run `9D9CCFA4-9BDA-4460-BA94-CBAC1D56C484` (modo `infografico_v3`, workdir
`~/tripstory-mvp1`, 2026-08-12 05:27–05:59): primeiro run após os fixes do
`biggest_gap` (34a707d + 995ff67 + de116af). A extração do gap FUNCIONOU —
o accum do vision_gate continha a crítica real do juiz:

```
Single biggest remaining gap: text legibility and visual clutter: the footer
text is overlapping and contains garbled characters, [...]
```

Mesmo assim o run queimou **5/5 loops** (20 attempts, 1943s) e morreu
`run_finished status=fail`. As críticas do juiz mudavam de fraseado a cada
ciclo (o HTML mudava ao acaso) em vez de convergir.

## Evidência de que o builder nunca viu o gap

1. `<run>.vision_gate.gauntlet/feedback.md` — 848 bytes, gap correto. ✓
2. `<run>.run.gauntlet/feedback.md` — **0 bytes**. ✗
3. `<run>.run.gauntlet/runner-1.log` (log da sessão opencode do builder,
   3.3MB) — `rg -c 'GAUNTLET FEEDBACK|garbled|biggest remaining gap'`
   retorna **zero**. O prompt composto do builder era o spec original puro.

## Causa raiz (duas metades no `bin/dispatch-stages.sh`)

**Metade 1 — o loop-back não transporta nada** (linhas ~445-465): quando um
stage com `loop_target` falha, o código só faz `i="$loop_i"; continue`. O
accum do stage que falhou (onde o gap foi escrito por
`oracfit_gauntlet_append_feedback`) fica para trás. Detalhe agravante: o
vision_gate é mecânico (command, sem model_ref) — o accum dele não é lido
por ninguém; o único consumidor útil do gap seria o spec composto do stage
`run`, que nunca o recebe.

**Metade 2 — o truncate na entrada do stage** (linhas ~202-205):

```bash
accum="${gauntlet_dir}/feedback.md"
: >"$accum"
```

Roda a CADA entrada do stage, inclusive reentrada via loop-back. Mesmo que
algo escrevesse o gap no accum do `run`, a reentrada zeraria o arquivo antes
do compose. (É também por isso que o accum do vision_gate só tinha o bloco
do ciclo corrente.)

## Por que passou despercebido até agora

O incidente 2026-08-11 (gap não injetado) foi diagnosticado e corrigido na
camada de EXTRAÇÃO (`oracfit_gauntlet_biggest_gap` pegava boilerplate). Eram
dois bugs empilhados: com a extração quebrada, o transporte quebrado era
invisível — o que chegasse ao builder seria lixo de qualquer forma. O run
`9D9CCFA4` foi o primeiro com a extração sã, e expôs a camada de baixo.

Nota: o feedback intra-stage (attempt 1 → attempt 2 do MESMO stage) sempre
funcionou — é o caso coberto por `dispatch-mode.sh` (single-stage) e pelos
testes existentes. O buraco é exclusivo do salto entre stages do
`dispatch-stages.sh` (v3).

## Correção (aplicada na sequência deste registro; ver diff no working tree)

1. **Transporte no loop-back**: antes do `continue`, o accum do stage que
   falhou é anexado ao accum do stage alvo
   (`${RUN_ID}.${loop_target}.gauntlet/feedback.md`) e zerado na origem; se
   o accum da origem estiver vazio (falha no attempt == max_attempts não
   passa pelo append do attempt-loop), o bloco de feedback é gerado na hora
   a partir do último `oracle_log`.
2. **Truncate só na 1ª entrada**: o `: >"$accum"` passa a rodar só na
   primeira visita do stage no run (rastreado em `seen_stage_roles`,
   compatível com bash 3.2 — sem array associativo). Na reentrada, o accum
   preserva o feedback transferido.
3. **Bônus (pendência P1 do painel)**: `export ORACFIT_EVENTS_FILE` junto do
   `ORACFIT_RUN_ID` — o tee do runner opencode exige as DUAS envs para
   emitir `thinking`/`tool_call`; `dispatch-mode.sh:363` exporta, o
   `dispatch-stages.sh` não exportava → todo run multi-stage ficava mudo no
   feed do Mission Control.

## Análise de regressão

### Caso 1: modo multi-stage sem loop_target
Loop-back nunca dispara; truncate na 1ª entrada é idêntico ao comportamento
antigo (cada stage entra 1 vez). ✓ Sem mudança.

### Caso 2: stage falha TODOS os attempts sem loop_target (on_fail halt)
Não passa pelo bloco de loop-back; nada transferido. ✓ Sem mudança.

### Caso 3: loop_target aponta para o próprio stage ou stage à frente
Guarda existente `[ "$loop_i" -lt "$i" ]` impede o loop; transferência fica
dentro desse guard. ✓ Sem mudança.

### Caso 4: múltiplos ciclos de loop-back
Accum do alvo ACUMULA um bloco de feedback por ciclo (comportamento
desejado — histórico de críticas no prompt). Origem é zerada após
transferir → sem duplicação. Crescimento: ~10 linhas/ciclo × ceiling 5. ✓

### Caso 5: falha no attempt == max_attempts (accum origem vazio)
Antes do fix o gap desse attempt se perdia por completo; agora
`oracfit_gauntlet_append_feedback` gera o bloco direto no accum do alvo a
partir do último oracle_log. ✓ Melhoria.

### Caso 6: stage run falha o próprio oracle e volta pra si mesmo
`loop_i == i` → guard barra (comportamento antigo). ✓ Sem mudança.

## Teste (executado 2026-08-12 ~06:20)

Suítes existentes, todas verdes pós-fix: **stage-runner 16/16 · feedback 8/8
· critic 10/10** — sem regressão.

Teste funcional do transporte (fixture novo, padrão test-stage-runner):
modo 2-stages `run` (runner fake grava o spec composto de cada invocação) +
`vision_gate` mecânico que sempre rejeita com
`VISION GATE REJECTED: o botao esta invisivel no mobile`, `loop_target: run`,
ceiling 1.

- `spec-1.md` (builder ciclo 1): spec base, **sem** feedback. ✓
- `spec-2.md` (builder ciclo 2, pós loop-back): contém
  `## GAUNTLET FEEDBACK (attempt 1)` +
  `Single biggest remaining gap: VISION GATE REJECTED: o botao esta invisivel no mobile`. ✓
- rc final 1 (ceiling exaurido) — esperado. ✓

Antes do fix, o mesmo cenário deixava `spec-2.md` idêntico ao base (provado
no run real `9D9CCFA4`: runner log sem nenhuma ocorrência de GAUNTLET
FEEDBACK).

**Prova em produção (run real `AA26BEB2`, pós-fix):** no primeiro loop-back o
`<run>.run.gauntlet/feedback.md` tinha 5649 bytes; ao final, 17291 bytes com
5 blocos `GAUNTLET FEEDBACK` acumulados (vigia automatizado confirmou). O run
falhou por outra causa (estouro de contexto do builder — ver incidente
2026-08-12-gap-heuristico-injeta-stream-json-cru), mas o transporte funcionou.

## O que falta

1. Rodar suítes existentes + teste funcional do transporte.
2. Relançar `infografico_v3` e confirmar `GAUNTLET FEEDBACK` no runner-N.log
   do builder (prova de ponta a ponta).
3. Commit (aguardando ordem do usuário — working tree suja por regra).
