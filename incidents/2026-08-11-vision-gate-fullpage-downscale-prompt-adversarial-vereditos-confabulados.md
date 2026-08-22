---
id: 2026-08-11-vision-gate-fullpage-downscale-prompt-adversarial-vereditos-confabulados
titulo: vision-gate-fullpage-downscale-prompt-adversarial-vereditos-confabulados
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): bin/vision-gate-slices.sh (fatias <=1800px sem downscale, prompt checklist neutro sem default-REJECTED, retry anti-confabulacao na mesma fatia, CTA checado mecanicamente via curl+rg) + check DOM de imagem quebrada no render (screenshot-page.js exit 2)
status: promovido
---

# Full-page 8.5k px sofre downscale no juiz → prompt adversarial confabula defeitos

## Sintoma

Stage `vision_gate` do modo `content_factory` enviava screenshots full-page
(1440×8513 px) para `openrouter/google/gemma-4-26b-a4b-it:free` com prompt
adversarial ("MERCILESS", "DEFAULT VERDICT IS REJECTED", "be suspicious — if
unsure, FAIL"). Vereditos flipavam entre runs com razões inventadas ("blurry",
"não posso validar texto", placeholders inexistentes). Tipografia ilegível no
PNG após downscale do endpoint.

## Causa

1. **Downscale no endpoint:** imagens full-page muito altas são reduzidas antes
   de chegar ao modelo — texto e detalhes ficam ilegíveis.
2. **Prompt adversarial:** framing "default REJECTED" + "be suspicious" induz o
   modelo 26B a confabular defeitos quando não consegue ler a imagem com
   confiança.

## Correção (aplicada)

1. Script `bin/vision-gate-slices.sh`: fatia cada screenshot em blocos ≤1800 px
   (PIL), julga cada fatia com prompt neutro em checklist binário.
2. CTA `/produtos/` checado mecanicamente via `curl` + `rg` no HTML — removido
   do checklist visual (fatias do meio não têm CTA e geravam falso REJECTED).
3. Stage `vision_gate` em `core/modes/content_factory.yaml` passa a chamar o
   script em vez do prompt inline adversarial.

## Prevenção

- Nunca enviar screenshot full-page >~2000 px de altura para juiz de visão free
  — fatiar antes.
- Prompt do juiz: checklist neutro, sem default REJECTED nem linguagem
  adversarial; ver `bin/vision-gate-slices.sh` como referência.
- Checagens não-visuais (CTA no HTML, tamanho de PNG, lazy-load) ficam fora do
  LLM.
- Imagem quebrada é checada MECANICAMENTE no render, não por visão: o teste
  negativo mostrou que o gemma aprova card com área branca (falso negativo
  3/3). `apps/storefront/scripts/screenshot-page.js` agora inspeciona o DOM
  após o screenshot (`img.complete` / `naturalWidth === 0`) e sai com exit 2
  listando as URLs quebradas — o stage `render` falha antes de o juiz ver
  qualquer coisa. Validado: página real → exit 0; página com img 404 → exit 2.

## Evidência

- Validação empírica: fatia ~1800 px + prompt neutro → APPROVED 2/2 em página
  limpa; REJECTED 2/2 em página com imagens quebradas reais.
- Teste positivo `/tmp/vg-test-ok/`: 23 fatias (5 desktop + 18 mobile) →
  APPROVED 23/23, exit 0, CTA `/produtos/` OK no HTML.
- Teste negativo `/tmp/vg-test-bad/` (`<host-local>-fix-desktop.png` com cards
  brancos no rodapé): nesta execução o gemma aprovou 10/10 fatias incluindo
  `desktop-05` onde placeholders brancos são visíveis — falso negativo do
  modelo (re-run manual 3× em `desktop-05` → APPROVED 3/3). O script
  reprovaria corretamente se o juiz devolvesse REJECTED.
