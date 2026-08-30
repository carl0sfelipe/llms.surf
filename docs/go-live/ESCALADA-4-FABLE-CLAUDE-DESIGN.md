# ESCALADA-4 — Fable: prompt-mestre Claude Design (Opus) para os 2 sites

> Pedido do dono, 2026-08-31. Os protótipos de landing do bestmodel foram
> REPROVADOS ("uma bosta" — literal `Designed for wide screens · min
> 1024px`, não responsivo). Nada de redigir copy aqui: o Fable entrega o
> PROMPT + instruções para o Claude Design (Opus) gerar o site inteiro.

## O que o Fable entrega (entregáveis)

1. **Prompt único e fechado** para o Claude Design (Opus) construir o site
   completo dos DOIS produtos — todas as páginas, responsive (mobile
   first), design de UX profissional, tom de cada marca:
   - llms.surf: sarcástico, afiado ("Victory is a green oracle — not 'I
     tried 8 times'"), The Lineup com a jornada de tiers **Haole → (meio com você: sementes Grom, Local) → The Legend** — haole = o outsider havaiano que chega sem conhecer as regras do surf; a fila transforma haole em lenda, e a moeda é contribuição.
   - bestmodel.run: profissional, sóbrio,Gamificação própria (nome e
     desenho dele), botão "denunciar run irreal" em cada linha da
     leaderboard, badges de source-class visíveis.
2. **Mapa de páginas** (mínimo, não é teto): llms.surf — home, The
   Lineup, confirm/thanks do funil, incidents, v4/readme; bestmodel —
   landing (substitui os protótipos reprovados), leaderboard + run
   detail, hardware, página da gamificação profissional, aviso de
   proveniência (community pool via localmaxxing.com public API).
3. **Instruções de uso**: como iterar no Claude Design (o que pedir por
   rodada, o que colar de volta no repo — apps/web/site/ do bestmodel,
   site/ do llms.surf — e quais arquivos são gerados vs fonte).
4. **Critérios de aceite** (o que o dono confere antes de aprovar).

## Dados verificados (o prompt não inventa)

- Dado vivo do bestmodel: leaderboard derivada das runs (S26), badges
  source_class (S24: 626/626 classificadas na harvest), pool de 1310
  células de localmaxxing.com public API (snapshot 2026-08-13) entrando
  como classe `reported` (S28 em curso) + botão de denúncia.
- Máquina do Lineup no llms.surf: data/lineup.json (S13) + template com
  `referred by:` + checkbox A3. Copy do tiers/pontos = APROVADA (tabela
  no data/lineup-points.json).
- Restrições duras de honestidade: NUNCA preço/data/quantia; futuro como
  gated; A3 opt-out transparente; bad sources nunca escondidas.
- Protótipos reprovados (NÃO evoluir, substituir):
  ~/Work/bestmodel/apps/web/prototypes/{goal-first,hardware-first,
  mobile-landing}.html — falha fatal: min-width 1024px.
- Site de produção servido de apps/web/site/ (vercel.json); llms.surf de
  site/ (GitHub Pages + CNAME llms.surf).

## Contexto nos arquivos (ler nesta ordem, nada além disso)

1. docs/go-live/ESTADO-SESSAO.md (estado dos 2 produtos, hoje)
2. docs/go-live/pesquisa-gamificacao-whitelist.md (base de neuromarketing)
3. docs/go-live/PLANO-LINEUP-2-GOLIVES.md (mecânica aprovada)

## Já resolvido fora desta escalada (não reabrir)

- ESCALADA-2: 5 decisões E2 congeladas. ESCALADA-3: mecânica The Lineup
  implementada (S13) + export por-contribuidor (S27). Import S28 em curso
  com fonte localmaxxing carimbada + botão de denúncia.

## Fora de escopo

- Código de backend novo; mudanças na API; deploy (o dono opera);
  escrever a copy final ele mesmo — ele ENTREGA o prompt-mestre e o mapa.
