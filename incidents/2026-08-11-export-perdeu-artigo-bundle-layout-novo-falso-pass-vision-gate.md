---
id: 2026-08-11-export-perdeu-artigo-bundle-layout-novo-falso-pass-vision-gate
titulo: export perdeu artigo do bundle (layout novo) — run pass publicou post só com schemas
data: 2026-08-11
recorrivel: sim
regra: nao — mecanismo aplicado (classe C): stage_oracle mecanico do export (bin/check-export-mdx.py), extract_parte2 com fallback layout novo + strip do marker (_finalize_body, <repo-cliente> commit 31d2bca), contrato T4 de CTAs/layout, item (6) do vision prompt; tests/test_export_layout_novo.py
status: promovido
interage_com: "2026-08-11-vision-gate-decorativo-run-passa-com-verdict-rejected"
---

# export perdeu artigo do bundle — falso pass publicou MDX de 2,4 KB só com schemas

## Contexto

Run `24F10F97` do modo `content_factory` (nicho Beelink Radeon 680M v3).
Pipeline: T1-T4 → export MDX → render → vision_gate → pass.

## Sintoma

Run terminou `status: pass`, mas o post publicado tinha ~2,4 KB — título +
frontmatter + blocos JSON-LD visíveis como code blocks. O artigo completo
(~800-1200 palavras) não apareceu na página. Vision gate aprovou a página
“vazia” de conteúdo editorial.

## Causa raiz

1. **Drift de layout T4 vs contrato do exporter.** O T4-CONTENT gerou bundle
   com seção `## 2. Artigo de blog` contendo prose em `### Copy do artigo`
   (sem fence) e frontmatter/schemas em subseções posteriores. O parser
   `extract_parte2` em `export-to-blog.py` esperava o layout antigo: fence
   com frontmatter + marker `**Conteúdo Principal (Markdown):**` + body.
   Montou MDX só com frontmatter + JSON schemas — corpo do artigo ficou de fora.

2. **Oracle de export fraco.** Stage `export` tinha `oracle: true` sem
   `stage_oracle` mecânico — exit 0 do script bastava mesmo com MDX truncado.

3. **Vision gate sem checque de prose.** Prompt da fatia superior não
   reprovava página dominada por blocos de código/JSON em vez de parágrafos
   de artigo.

4. **Bundle sem CTAs `/produtos/`.** O artigo gerado não continha links
   markdown para a loja — zero matches de `produtos/` no corpo.

## Correção (aplicada)

| # | Arquivo | Mudança |
|---|---------|---------|
| 1 | `apps/content-factory/export-to-blog.py` | `extract_parte2`: contrato antigo primeiro; fallback layout novo (`Copy do artigo` → prose; frontmatter em fence posterior; schemas excluídos do body) |
| 2 | `core/modes/content_factory.yaml` | `stage_oracle` no export: ≥4000 bytes, ≥1 link `](/produtos/`, ≥2000 chars prose fora de fences |
| 3 | `apps/content-factory/config/tasks.yaml` | T4-CONTENT: ≥2 CTAs `/produtos/<handle>` + layout canônico PARTE 2; T4-JUDGE: item binário CTAs |
| 4 | `bin/vision-gate-slices.sh` | Item (6) na top slice: página deve mostrar artigo com parágrafos, não só code/JSON |

Testes: `tests/test_export_layout_novo.py` (fixtures antigo + novo + bundle real).

## Prevenção

- **Linha de defesa primária:** oracle mecânico de conteúdo no stage `export`
  (tamanho, prose, CTAs) — reprova antes de render/vision.
- **Secundária:** vision gate item (6) na top slice — não substitui o oracle.
- **Upstream:** contrato T4-CONTENT + checklist T4-JUDGE para CTAs e layout
  canônico, reduzindo drift de formato.

## Evidência

- Bundle: `artifacts/cf-<host-local>-radeon680m-v3/T4-content-bundle/content.md`
- Run: `24F10F97`
- MDX publicado truncado: ~2400 bytes, body sem prose do review
