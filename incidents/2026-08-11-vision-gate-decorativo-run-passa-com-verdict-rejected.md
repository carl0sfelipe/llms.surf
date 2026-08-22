---
id: 2026-08-11-vision-gate-decorativo-run-passa-com-verdict-rejected
titulo: vision-gate-decorativo-run-passa-com-verdict-rejected
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/vision-gate-slices.sh decide o exit pelo veredito parseado (REJECTED ou parse-fail vira exit 1, ativa loop_target) e emite linha VISION GATE REJECTED para o extrator de gap
status: promovido
---

# vision gate decorativo: run passou com verdict REJECTED

## Sintoma

Piloto e2e content_factory (run CB3F8DB7) terminou `status: pass`, mas o
`mech-1.log` do vision_gate continha `"verdict": "REJECTED"` do juiz de visão.
Falso positivo: o pipeline declarou entrega com a página reprovada.

## Causa

O stage `vision_gate` em `core/modes/content_factory.yaml` era só a chamada
`opencode run -m <modelo> ... -f screenshots`. Com `oracle: true` e sem
`stage_oracle`, o critério de aprovação era o exit code do comando — e o
opencode sai com 0 sempre que a chamada de API funciona, independente do
conteúdo do veredito. O gate só falhava em erro de transporte (CreditsError,
timeout), nunca em REJECTED. Gate declarado, mecanismo ausente.

## Correção (aplicada)

`core/modes/content_factory.yaml`, stage vision_gate:

1. saída do juiz persistida em `$SCREENSHOTS/vision-verdict.txt`;
2. `grep -Eq '"verdict"...APPROVED'` decide o exit — REJECTED (ou resposta
   vazia/malformada) vira exit 1 e ativa o `loop_target: export`;
3. linha `VISION GATE REJECTED: <biggest_gap>` emitida para o extrator de gap
   do gauntlet;
4. modelo trocado para `openrouter/google/gemma-4-26b-a4b-it:free` (gemini
   pago caiu por CreditsError; visão NVIDIA e nemotron-vl travam com imagem)
   embrulhado em `with-timeout 240`.

Validação: run FF56021F passou com APPROVED real após 2 loops em que o
endpoint free devolveu resposta vazia — o gate reprovou as vazias e o loop
export→render→vision_gate funcionou como projetado.

## Prevenção

1. Stage cujo veredito vem no CONTEÚDO da saída de um LLM nunca pode usar só
   exit code de CLI como oráculo — exigir parse mecânico do veredito.
2. Falha de parse (JSON ausente/vazio) deve reprovar o stage, não passar.

## Evidência

- falso positivo: run CB3F8DB7 `status: pass` + mech-1.log com REJECTED
  (`.dispatch/logs/inbox/CB3F8DB7-*.vision_gate.gauntlet/`)
- pass honesto: run FF56021F, `vision-verdict.txt` com APPROVED
