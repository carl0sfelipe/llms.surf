---
id: 2026-08-11-screenshot-fullpage-lazy-load-imagem-branca-falso-positivo-vision-gate
titulo: screenshot-fullpage-lazy-load-imagem-branca-falso-positivo-vision-gate
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): apps/storefront/scripts/screenshot-page.js (eager + scroll + espera de imagens + DOM check de img quebrada, exit 2) e stage render do content_factory.yaml usa o script em vez do CLI
status: promovido
---

# CLI full-page não dispara lazy-load → cards brancos → REJECTED fantasma

## Sintoma

Stage `render` do modo `content_factory` gerava screenshots full-page via
`playwright screenshot --full-page` (CLI). Imagens com `loading="lazy"` abaixo
do viewport — carrossel "Você também pode gostar" no rodapé dos posts do blog
— saíam em branco no PNG. A URL da imagem respondia 200 image/jpeg e o site
estava correto, mas o `vision_gate` recebia placeholders fantasmas de imagem
quebrada e reprovava com REJECTED.

## Causa

O CLI `playwright screenshot` não executa JavaScript de forma interativa: não
rola a página nem altera `loading="lazy"` para `eager`. O navegador só
renderiza o que entra no viewport inicial; conteúdo lazy abaixo da dobra fica
sem fetch e aparece como retângulo branco no screenshot full-page.

## Correção (aplicada)

1. Script Node
   `apps/storefront/scripts/screenshot-page.js` usando `@playwright/test`
   (chromium): `networkidle` + 3s, força `loading="eager"` em lazy imgs, scroll
   em passos de 1 viewport (~300ms), volta ao topo + 2s, espera imagens
   completarem (timeout 15s tolerante), screenshot `fullPage: true`.
2. Stage `render` em `core/modes/content_factory.yaml` trocado para
   `node scripts/screenshot-page.js` (desktop `--viewport 1440x900`, mobile
   `--device "Pixel 5"`).

## Prevenção

Qualquer stage `render` de gauntlet visual deve garantir que lazy-load foi
disparado antes do screenshot — scroll + eager ou equivalente. O CLI
`playwright screenshot --full-page` sozinho não basta para páginas com
`loading="lazy"` ou conteúdo que só carrega com scroll. Vale para modos novos
(ex.: `card_redesign`) e qualquer pipeline que alimente `vision_gate`.

## Evidência

- Diagnóstico: carrossel rodapé blog cf-<host-local>-radeon680m-v3 — cards brancos
  no PNG do CLI, fotos presentes no browser real.
- Pós-correção: crop rodapé de `/tmp/lazy-fix-desktop.png` mostra fotos de
  produto no carrossel; `vision_gate` com gemma-4-26b free → APPROVED.
