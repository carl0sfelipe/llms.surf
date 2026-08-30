# ESCALADA-4 — Prompt-mestre para o Claude Design (Opus): os 2 sites

> Resposta do Fable à ESCALADA-4 (2026-08-31). Os protótipos de landing do
> bestmodel foram REPROVADOS pelo dono (falha fatal verificada: os 3 têm
> `min-width` 1024px — `apps/web/prototypes/{goal-first,hardware-first,
> mobile-landing}.html`). Eles NÃO evoluem: são substituídos.
> Este arquivo entrega (1) o prompt fechado, (2) as instruções de iteração
> e colagem, (3) os critérios de aceite do dono. Nenhuma copy de site é
> redigida aqui — copy é trabalho do Claude Design, dentro da régua.
> Fontes: ESTADO-SESSAO.md, pesquisa-gamificacao-whitelist.md,
> PLANO-LINEUP-2-GOLIVES.md + contratos verificados no repo (S27, template
> do issue, vercel.json, gen-seo.mjs). Nada além disso.

## 0. Decisões de desenho tomadas nesta escalada (delegadas ao Fable)

A escalada deixou dois espaços "com você". Fechados assim:

1. **Jornada de tiers do The Lineup (llms.surf)**: **Haole → Grom →
   Local → The Legend** — pontas dadas pelo dono (Haole, The Legend),
   meio preenchido com as sementes sugeridas (Grom = o iniciante que já
   pertence à água; Local = quem tem lugar garantido no pico). 4 tiers =
   os 4 degraus da tabela de pontos aprovada (`data/lineup-points.json`).
   First Wave NÃO é tier: é o PRÊMIO — os primeiros 25 por pontos quando
   o gate de cloud abrir (único cap público, política D6/D9).
2. **Gamificação própria do bestmodel.run**: nome **Track Record**,
   léxico de auditoria científica (zero surf): níveis **Contributor →
   Replicator → Auditor**, mapeados nos atos que o motor já valida
   (run assinada / reprodução / divergência pega). Sóbrio por construção:
   o nível é o seu papel no método, não uma fantasia.

Os dois nomes são default do Fable — dial do dono, troca barata (é uma
palavra no prompt e nos critérios de aceite).

---

## 1. O PROMPT (colar inteiro na primeira mensagem do Claude Design)

Junto com o prompt, anexar na mesma mensagem os 4 arquivos listados no
bloco `ATTACHMENTS` (conteúdo bruto, cada um em um bloco de código).

```text
You are designing and building TWO complete production websites for two
sibling products that share one engine. You write all HTML, CSS, JS and
all copy. You are replacing prototypes that were REJECTED for being
desktop-only. Read everything below before producing anything.

=== THE TWO PRODUCTS, ONE ENGINE ===

- bestmodel.run — a benchmark engine for local LLMs. Every result on the
  leaderboard DERIVES from validated runs signed with per-user Ed25519
  keys. Nothing is an opinion; everything is a measured, reproducible,
  attributable run.
- llms.surf — a dispatch framework that routes dev work to the model that
  wins each task, fed by bestmodel's measurements. Its waitlist is a
  gamified queue called The Lineup where CONTRIBUTION is the currency.

Every signed run on bestmodel improves llms.surf's model-per-task picks
for everyone. Each site must carry a "two products, one engine" block
linking to the other, phrased in its own voice.

=== NON-NEGOTIABLE 1: MOBILE FIRST (the reason the prototypes died) ===

The rejected prototypes gated the layout behind min-width: 1024px and a
"Designed for wide screens" notice. That exact failure is forbidden.

- Design for 360px width FIRST. Enhance upward with min-width media
  queries on top of a working narrow layout — never gate content.
- Zero horizontal scroll at any width from 320px up. Test 360 / 768 /
  1280 mentally for every page you emit.
- Tap targets >= 44px, readable base font >= 16px, tables collapse to
  cards or scroll WITHIN their own container on narrow screens.
- Never emit any "best viewed on desktop" apology, and never emit a
  min-width that hides or replaces page content.

=== NON-NEGOTIABLE 2: HONESTY RULES (gate-enforced in the repos) ===

These are tested mechanically; violating them fails the repo gate.

- NEVER state a price, a date, or an invented quantity. No "$", no
  "coming in Q4", no "only X spots" — the ONE public cap that exists is
  First Wave = 25 (a standing policy, stated as a rule, never as
  countdown scarcity).
- Future features are "gated": describe the gate that opens them, never
  a promise with a date. Past/present facts only when measured (the
  whitelist of citable facts is below).
- Numbers on pages come from data files rendered at runtime or build
  time — never hardcoded in copy. Attached JSON files are the only
  sources of points, tiers, and standings.
- Bad sources are NEVER hidden. Provenance classes, incidents and
  divergences are displayed, not buried.
- The A3 consent checkbox (spec below) is a transparent opt-out:
  visible, pre-checked, plainly worded, and unchecking costs the user
  nothing. No dark pattern anywhere on either site.

=== NON-NEGOTIABLE 3: OUTPUT FORMAT ===

- Plain static HTML5 + one CSS file per site + vanilla JS. No
  frameworks, no build step, no npm, no external CDNs, no webfonts
  loaded from third parties (system font stack, or self-hosted with the
  font file named as an asset to be added), no trackers or analytics.
- Semantic HTML, WCAG AA contrast, visible focus states, and
  prefers-reduced-motion respected on any animation.
- Each file you emit must be COMPLETE (no "..." elisions) and preceded
  by a header line: === FILE: <path> ===
- llms.surf is served by GitHub Pages, currently under a project
  subpath — ALL urls in it must be RELATIVE (href="styles.css", never
  href="/styles.css").
- bestmodel.run is served by Vercel with cleanUrls: keep .html
  filenames, link internally with extensionless paths ("/hardware").
- Dynamic data is fetched client-side from the JSON paths given per
  page, with a graceful empty state when the file is missing.

=== SITE A: llms.surf ===

Voice: sarcastic, sharp, surf-literate, allergic to marketing fluff.
It mocks vibes and worships mechanisms. These approved lines are tone
anchors and MUST appear (verbatim) somewhere natural:
- "Victory is a green exit code — never a model's opinion of itself."
- "Victory is exit 0. 'I tried 8 times' is not victory."
- "The Lineup — list order, first wave first; contribution is what
  climbs."

The Lineup narrative: a HAOLE is the outsider who paddles out not
knowing the rules of the break. The queue turns the haole into a
legend, and the currency is contribution. Tier journey (names fixed):

  Haole -> Grom -> Local -> The Legend

Thresholds, point values and badge definitions come ONLY from the
attached data/lineup-points.json. Standings come ONLY from
data/lineup.json (generated by a scheduled GitHub Action; its git
history is the public audit trail — say so on the page). Badges to
render (each one teaches exactly one action): Duck Dive (opened the
waitlist issue), Tow-In (first converted referral), Signed Set (first
signed run on bestmodel), Same Wave (reproduced someone's run), Shark
Eye (caught a divergence/fake), Shared Break (shared a custom mode).

Ranking surface rules (anti-demotivation, fixed): personal progress bar
("N pts from Local") always; small finite cohort view; opt-in hall for
top tiers. NO infinite global leaderboard.

A3 checkbox (exact behavior, wherever the waitlist entry is explained):
pre-checked, visible, labeled in full: showing your handle on the
public Lineup page is optional; unchecking removes you from the page
but your points and place are yours either way.

Pages (minimum set — you may propose more, never fewer):
1. index.html — home. Hero states what the product does (routes dev
   work to the model that wins the task, fed by measurements), the
   victory-line tone anchors, The Lineup teaser with the Haole->Legend
   journey, "two products, one engine" block to bestmodel.run.
2. lineup.html — The Lineup. Full journey, tier cards, badge glossary,
   points table rendered from lineup-points.json, personal-progress
   explainer, standings from data/lineup.json, "how this is computed"
   section pointing at the Action + git history, the A3 explainer, the
   entry CTA (open the waitlist issue — the issue IS the public
   commitment).
3. confirm.html / thanks.html — email funnel pages. The form logic is
   pluggable: it only renders when a JS constant DATA.whitelistEndpoint
   is set (the host is static; no endpoint, no form). Keep that exact
   mechanism; design the states for both endpoint-set and dormant.
4. incidents.html — public incident log. Honest, dry, sarcastic
   headers welcome; incidents are content to be proud of, not hidden.
5. readme.html + v4-plan.html — docs surface: what the framework is,
   how dispatch works, what v4 changes. Future items phrased as gated.

=== SITE B: bestmodel.run ===

Voice: professional, sober, metrology-grade. No jokes near data. The
confidence comes from provenance, signatures and reproducibility. This
site replaces rejected prototypes — start from zero, keep nothing.

Gamification (own name and design, NO surf lexicon): "Track Record".
Levels are scientific roles earned through validated acts:
  Contributor (validated signed runs) -> Replicator (reproduced
  another user's run within tolerance) -> Auditor (caught a divergence
  or fake). Present it as method, not game: your level is your role in
  the verification chain. Cross-note (sober, one line): validated acts
  also score in llms.surf's shared Lineup ledger.

Leaderboard requirements (fixed):
- Standings DERIVE from validated runs — say so plainly.
- Every row shows a source-class badge (source classes are the
  provenance taxonomy; all 626 harvested cells are classified).
- Community-pool rows carry class "reported": data from the
  localmaxxing.com public API (snapshot 2026-08-13, 1310 cells),
  clearly badged as reported, never blended silently with verified.
- EVERY row has a "report unreal run" button/link (target URL will be
  provided at integration; emit a data-report-run attribute and a
  stub handler).
- Run detail page: full provenance of one run — model, quant, hardware,
  signature attribution, source class, validation status, and the
  report button again.

Pages (minimum set):
1. index.html — landing. What the engine is (validated, signed,
   reproducible local-LLM benchmarks), how to read the numbers, entry
   points to leaderboard and hardware, "two products, one engine"
   block to llms.surf, Track Record teaser.
2. Leaderboard page + run-detail page — deliver as TEMPLATES with
   realistic sample markup (clearly marked SAMPLE); real rows are
   injected by the repo's generator at integration.
3. hardware.html — hardware index page (existing page redesigned in
   the new system; per-hardware subpages are generated, don't emit
   them — just design the template look via the index).
4. track-record.html — the Track Record page: the three roles, what
   act earns each, why signatures make levels trustworthy, sober
   explanation of the shared ledger with llms.surf.
5. provenance.html — provenance notice: the source-class taxonomy,
   what "reported" means, the localmaxxing.com public API community
   pool (snapshot 2026-08-13, 1310 cells), the report-unreal-run
   mechanism, and the commitment that bad sources are displayed, never
   hidden.

=== FACTS YOU MAY STATE (measured; the ONLY citable numbers) ===

- Leaderboard standings derive from validated runs.
- Runs are signed with per-user Ed25519 keys (cryptographic
  attribution).
- 626/626 harvested cells carry a source classification.
- Community pool: 1310 cells, localmaxxing.com public API, snapshot
  2026-08-13, class "reported".
- First Wave = 25 (standing policy; a rule, not a countdown).
- Everything else numeric renders from the attached JSON files.

=== DELIVERY PROTOCOL ===

Work in rounds; wait for "next" between rounds.
- ROUND 1: design brief only — for EACH site: palette, type scale,
  spacing system, breakpoint plan (mobile-first), component inventory,
  and one homepage rendered complete (both index.html + the CSS file
  started). State how the two brands differ visually.
- ROUND 2: llms.surf remaining pages, complete files.
- ROUND 3: bestmodel.run remaining pages, complete files.
- ROUND 4: self-audit — re-check every emitted file against
  NON-NEGOTIABLES 1-3 and list violations found and fixed; emit
  corrected files only for pages that changed.
Never re-emit unchanged files. Never invent data beyond the whitelist.
```

### ATTACHMENTS (colar na mesma mensagem, cada um em bloco de código)

| # | Anexo | De onde tirar | Por quê |
|---|---|---|---|
| 1 | `data/lineup-points.json` | llms.surf repo (S13) | única fonte de pontos/tiers — o prompt proíbe inventar números |
| 2 | `data/lineup.json` | llms.surf repo (gerado pela Action) | formato real das standings + estado vazio realista |
| 3 | Contrato do export | `specs/en/S27-contributor-export.md` do bestmodel (o bloco do JSON: `{"generated_at","contributors":[{"handle","points","validated_runs"}]}`) | o run-detail/leaderboard citam atribuição por handle |
| 4 | `site/index.html` atual do llms.surf | llms.surf repo | fonte das linhas de copy APROVADAS (âncoras de tom) — redesenhar estrutura, preservar claims |

**NÃO anexar** os protótipos reprovados. Eles não são referência de nada
— nem de estética, nem de estrutura. Substituição, não evolução.

---

## 2. Instruções de uso — como iterar no Claude Design

### O que pedir por rodada

| Rodada | Você cola/pede | Você confere antes do "next" |
|---|---|---|
| 1 | O prompt inteiro + 4 anexos | Brief de design faz sentido? As DUAS homes abrem bem a 360px (DevTools mobile)? Marcas visualmente distintas (surf afiado vs metrologia sóbria)? Se a home falhar mobile, NÃO avançar: repetir rodada 1 apontando a falha específica |
| 2 | "next" | Páginas internas llms.surf: âncoras de copy verbatim presentes, checkbox A3 com texto pleno, jornada Haole→Grom→Local→The Legend, números só via fetch dos JSON |
| 3 | "next" | Páginas internas bestmodel: botão de denúncia em TODA linha (template), badge de source-class em toda linha, classe `reported` explicada, tom sem piada perto de dado |
| 4 | "next" (auto-auditoria) | A lista de violações que ele mesmo achou; colar só as versões corrigidas |

Regra de iteração: **um problema por mensagem de correção**, citando o
arquivo e a linha da régua violada ("NON-NEGOTIABLE 1: hardware.html
estoura horizontal a 360px"). Pedidos vagos ("melhora o design")
queimam rodada sem convergir.

### O que colar de volta no repo (e o que NUNCA sobrescrever)

**llms.surf → `site/`** (GitHub Pages, CNAME llms.surf; paths RELATIVOS):

| Arquivo do Claude Design | Destino | Nota |
|---|---|---|
| index, lineup, confirm, thanks, incidents, readme, v4-plan (.html) | `site/` | fonte — colar direto |
| styles.css, app.js (e journey.js se refeito) | `site/` | fonte — colar direto |
| — | `data/lineup.json` | **GERADO pela Action lineup.yml — NUNCA colar por cima** |
| — | `data/lineup-points.json` | política do dono — só o dono edita |
| — | favicon/logo/og | mantêm-se os atuais; trocar só com pedido explícito do dono |

**bestmodel → `apps/web/site/`** (Vercel, `outputDirectory: site`,
cleanUrls):

| Arquivo do Claude Design | Destino | Nota |
|---|---|---|
| index.html, hardware.html | `apps/web/site/` | fonte — colar direto |
| track-record.html, provenance.html | `apps/web/site/` | páginas novas — colar direto |
| template de leaderboard + run detail | NÃO colar direto | vira insumo de integração: o markup entra no `gen-seo.mjs`/`derive.mjs`, que geram as páginas reais |
| — | `site/m/`, `site/p/`, `sitemap.xml` | **GERADOS pelo gen-seo.mjs — NUNCA colar por cima** |
| — | `site/data`, `site/console`, `site/prototypes` | symlinks/build (vercel.json copia console) — não tocar |

### Depois de colar (mecanismo antes de claim — regra da casa)

1. llms.surf: rodar o gate local (suítes de honestidade pinam número da
   página Lineup a `data/lineup.json`; teste do checkbox A3 presente e
   pré-marcado). Gate vermelho = a colagem não vai a commit.
2. bestmodel: `node apps/web/scripts/check.mjs` + `make gate`; rodar
   `gen-seo.mjs` para regenerar `m/`/`p/`/sitemap sobre o novo CSS.
3. Copy de proveniência: antes de publicar `provenance.html`, verificar
   o estado real do S28 (import localmaxxing). Se o import ainda não
   estiver mergeado, a página descreve o MECANISMO (classes, denúncia)
   sem afirmar que as linhas `reported` já estão no ar.
4. Deploy de teste primeiro: gh-pages espelho (plumbing, nunca worktree
   sujo) e preview do Vercel — aprovação do dono em cima do deploy, não
   do arquivo local.

---

## 3. Critérios de aceite (o que o dono confere antes de aprovar)

Mecânicos (falhou um, reprova — sem discussão estética):

1. Zero gating de conteúdo por largura (a falha exata que matou os
   protótipos): `rg -in 'wide screens|desktop only|best viewed'` nas
   duas árvores acha nada; e nenhum bloco `@media (min-width: ...)`
   ESCONDE ou SUBSTITUI conteúdo — media query de min-width só pode
   ENFEITAR um layout estreito que já funciona (é o mobile-first
   correto, permitido e esperado).
2. Toda página abre a 360px sem scroll horizontal e sem conteúdo
   cortado — conferida em celular REAL, não só DevTools.
3. `rg -n '\$[0-9]|R\$|Q[1-4] 20|spots left|vagas'` nas duas árvores de
   site: zero. Nenhum preço, data ou quantia fora dos fatos medidos
   whitelisted; futuro sempre como gated.
4. Checkbox A3: presente, visível, pré-marcado, texto pleno dizendo que
   desmarcar não perde pontos nem lugar.
5. Números do Lineup renderizam de `data/lineup.json` /
   `data/lineup-points.json` (ver fetch no fonte); nenhum número de
   pontos/tier hardcoded em HTML.
6. Leaderboard bestmodel (template): botão "report unreal run" em CADA
   linha; badge de source-class em CADA linha; classe `reported` com
   proveniência localmaxxing + data do snapshot (2026-08-13) visível.
7. Bad sources visíveis: incidents.html (llms.surf) e provenance.html
   (bestmodel) publicados e linkados da home.
8. Gates verdes DEPOIS da colagem: suítes llms.surf + check.mjs +
   make gate do bestmodel.
9. Zero dependência nova, zero build step novo, zero CDN/tracker
   (conferir `rg -n 'cdn\.|googleapis|analytics'`).
10. llms.surf: todos os paths relativos (site de teste vive em subpath
    do github.io — path absoluto quebra lá e SÓ lá).

De julgamento (o dono olha e decide):

11. Tom llms.surf: lê a home em voz alta — afiada e sarcástica sem
    virar palhaçada; as 3 âncoras de copy aprovadas presentes verbatim.
12. Tom bestmodel: sóbrio; nenhuma piada a um scroll de distância de um
    número.
13. Jornada Haole → Grom → Local → The Legend conta a história do dono
    (o outsider que a fila transforma em lenda; moeda = contribuição).
14. "Two products, one engine" presente nos DOIS sentidos, cada um na
    voz da sua marca.
15. Nomes default do Fable (tiers do meio Grom/Local; gamificação
    "Track Record" com Contributor/Replicator/Auditor) — aprovar ou
    girar o dial e re-rodar a rodada afetada.

---

## Fora de escopo desta escalada (não reabrir)

ESCALADA-2 (5 decisões E2) congelada; ESCALADA-3 (mecânica The Lineup,
S13 + S27) implementada; S28 em curso com fonte carimbada + denúncia.
Este documento não muda mecânica nem pontos — só encomenda a pele dos
dois sites por cima do que já é verdade.
