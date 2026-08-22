# Vision gate com "DEFAULT VERDICT: REJECTED" é barra inalcançável — juiz free nunca aprova e alucina defeito

- **Data**: 2026-08-12 (madrugada)
- **Modo afetado**: `core/modes/infografico_v3.yaml` (stage `vision_gate`)
- **Runs de evidência**: `3FB7FB72`, `9D9CCFA4`, `AA26BEB2`, `23A7E924`, `B30C09BD` (todos fail)
- **Status**: corrigido (prompt calibrado no yaml)

## Sintoma

5 runs do infografico_v3 terminaram `fail` no teto de loops. No run 4
(`B30C09BD`), com TODA a infra consertada (feedback cruzando stages,
sem estouro de contexto, builder aplicando o gap de verdade), o gauntlet
usou os 5 loops e o juiz rejeitou TODAS as versões — inclusive a final,
que a olho humano está sólida.

## Investigação (a artefato constante)

Mesma imagem (`/tmp/infografico-v3/story.png` pós-fix manual da rota),
julgada por prompts/modelos diferentes:

| Juiz | Prompt | Veredito | biggest_gap |
|---|---|---|---|
| gemma-4-26b free | MERCILESS/DEFAULT REJECTED (o do modo) | REJECTED | "insufficient contrast against map textures" (genérico) |
| nemotron-nano-12b-vl free | MERCILESS | REJECTED | "route lacks graded color transitions illustrating **elevation changes**" (absurdo) |
| gemma-4-26b free | calibrado (só defeito bloqueante) | REJECTED | "ESRI·MAPLIBRE glitched/overlapping characters" |
| gemma-4-26b free | calibrado + anti-alucinação | **APPROVED** | — (3/3 rodadas) |

Zoom no rodapé em resolução nativa (`footer-zoom.png`): texto
perfeitamente nítido — o "glitch" citado NÃO existe. É artefato do
downscale interno do modelo de visão: mono pequeno com letter-spacing
largo vira pixel ambíguo, e o prompt "ANY weakness = REJECTED" converte
incerteza em defeito inventado pra obedecer o formato.

## Causa raiz

1. **Prompt com viés estrutural**: "DEFAULT VERDICT: REJECTED" + "ANY
   weakness = REJECTED" instrui o modelo a ACHAR uma fraqueza. Modelo
   free obedece inventando uma (as queixas rotacionam entre chavões de
   crítica de design). A barra é inalcançável por construção → o
   gauntlet SEMPRE queima o teto de loops → fail garantido.
2. **Alucinação de glitch em texto pequeno**: 1080x1920 é reduzido no
   input do modelo; caption mono <14px vira mancha e o juiz reporta
   "caracteres quebrados" no rodapé (2 prompts diferentes citaram o
   mesmo fantasma).

## Fix aplicado

- `infografico_v3.yaml`: prompt do vision_gate trocado pelo calibrado —
  julga como espectador casual (2 s), rejeita SÓ defeito bloqueante de
  lista fechada (texto grande ilegível, colisão, rota invisível/blob,
  rota cortada, layout quebrado), com cláusula anti-alucinação explícita
  ("texto pequeno suave é artefato do teu downscale, não defeito").
  Validado 3/3 APPROVED no artefato bom.
- Artefato em si: rota consertada manualmente (casing 100px→13px, halo
  62→20, linha 27→7, core 16→2.5), rodapé enxugado (pill "Diário de
  viagem" removido, atribuição sem moldura), fontes da faixa de modais
  +2-3px. Screenshot final aprovado pelo juiz novo.

## Teste de falsificação (feito) — resultado NEGATIVO

Recriei a versão rota-blob (casing 100px) e julguei com o prompt
calibrado: **APPROVED 3/3** — o juiz aprovou um defeito grosseiro e
explicitamente listado como bloqueante ("route rendered as a giant
blob/smear"), inclusive com colisão de chips sobre a stats-bar na mesma
imagem.

**Conclusão honesta**: gemma-4-26b free não tem poder discriminativo
nesta tarefa. Com prompt duro rejeita TUDO (inventa fraqueza); com
prompt calibrado aprova TUDO (inclusive blob). O sinal do gate é ~zero
nos dois regimes. O prompt calibrado fica no yaml por ser o mal menor
(barra inalcançável = loop infinito garantido + custo), mas o gate deve
ser tratado como decorativo até trocar o juiz.

## Recomendação

- Decisão de release visual: juiz pago (gemini, que fechou o gauntlet
  bar-satellite 5/5) ou revisão humana. Vision QA free serve pra
  triagem de gap (o texto do biggest_gap ainda orienta o builder), não
  pra veredito.
- Qualquer modo novo com vision gate: nascer com prompt de lista
  fechada + juiz com poder discriminativo COMPROVADO por teste de
  falsificação (aprovar o bom E rejeitar o ruim conhecido).

## Regressão

Os 5 loops do run 4 não foram desperdiçados: o histórico de gaps guiou
os fixes de infra (feedback transfer, contexto, JSON cru). Mas qualquer
modo novo com vision gate deve nascer com prompt de lista fechada de
defeitos bloqueantes, nunca "default rejected".
## Decisão do fundador (2026-08-12 ~14h30)

Juiz de visão passa a ser o próprio Claude na sessão do Cursor (olha a
imagem, aplica a lista fechada de defeitos bloqueantes, veredito com
achados citáveis). Modelos free ficam só pra articular gap textual;
gemini pago é opção reserva se um dia precisar de gate headless sem
sessão. Primeira aplicação real no mesmo dia: infográfico aprovado
(1080x1920 + 390px) e wizard reprovado no passo 3 (overflow real de
input em 390px) → corrigido → aprovado. O juiz-em-sessão pegou defeito
verdadeiro que o gemma free nunca articulou — decisão validada.
