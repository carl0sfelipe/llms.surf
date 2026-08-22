---
id: 2026-08-11-canal-eficaz-scraping-instagram-curl-cffi-sem-llm
titulo: canal de enriquecimento sem LLM — curl_cffi + regex ancorado em URL exata, 5x mais rápido que LLM+webfetch
data: 2026-08-11
recorrivel: sim
regra: nao-catalogada (achado de ecossistema — ferramenta pra reduzir custo de LLM em enriquecimento de dados)
status: aberto
interage_com: "2026-08-11-instaloader-quebrado-parcial-fallback-webfetch-funciona, 2026-08-11-feedback-uso-exaustivo-sessao-pivot-e-fornecedores-v3"
---

# Canal de enriquecimento sem LLM — 5x mais rápido, mesma fonte de dado

## Contexto

Depois de confirmar que `instaloader` está quebrado/rate-limitado (incidente
irmão linkado acima) e que o fallback via LLM+webfetch funciona mas custa
~20-43s/registro (tudo LLM: reasoning + tool call), pesquisei repo de GitHub
pra scraping de Instagram em massa. Achados de pesquisa: repos "scraper"
prontos no GitHub são fracos (2-11 commits, só embrulham serviço pago tipo
ScraperAPI, zero técnica própria). A defesa real documentada por múltiplas
fontes: `curl`/`requests` puro é bloqueado por fingerprint TLS; precisa de
`curl_cffi` (impersona TLS de navegador real) pra sequer conseguir uma
resposta 200 de `duckduckgo.com`.

## O que foi testado, com número real

1. `curl` puro em `html.duckduckgo.com` → bloqueado (redireciona pra
   homepage, sem resultado).
2. `curl_cffi` com `impersonate='chrome120'` → HTTP 200, resultado real
   (confirmei presença de "Followers" e `instagram.com` no HTML).
3. Escrevi `~/bin/instagram-search-scraper.py`: busca DuckDuckGo→Yahoo,
   extrai seguidores/data via regex — **sem LLM nenhum por registro**.
4. **Primeira versão tinha bug de acurácia real**: extraía o número de
   seguidor mais PRÓXIMO textualmente do handle buscado, não necessariamente
   do perfil CERTO. Como o dataset tem nome de negócio repetido (ex:
   "Laylla" = 3+ contas diferentes, seguidores completamente diferentes —
   298 likes vs 28K vs 2.897 seguidores em contas distintas), isso gerava
   número errado silenciosamente (`layllamodas_` → 2842 seguidores, quando o
   valor real, confirmado depois, é 372000).
5. **Corrigido**: âncora agora exige a URL EXATA `instagram.com/<handle>/`
   no HTML antes de extrair qualquer campo perto dela. Sem essa URL, retorna
   `encontrado: false` — nunca dado errado.
6. Reteste pós-correção: `layllamodas_` → 372000 seguidores, **batendo
   exatamente** com o valor que o piloto via LLM tinha achado antes
   (`data/fornecedores/enrichment/pilot-20-moda-feminina.json`, id 1). Outros
   3 handles testados também bateram com valores do piloto LLM
   (`luxoinfoco`=67000, `alycifashion`=80000, `fabiola5972`=215000).

## Números medidos (não estimados)

- Sem espaçamento entre chamadas: captcha ("select all squares with a duck")
  aparece rápido — confirmado com `curl_cffi` também, não é só limitação do
  `curl` puro.
- Com `sleep(2.5)` entre chamadas: **20 registros seguidos, zero captcha**.
- Taxa de acerto: 13/20 = 65% (resto = handle não indexado nos 2 motores, ou
  perfil renomeado/removido — tratado como `encontrado: false`, não erro).
- Tempo: ~4s/registro (dominado pelo `sleep` de segurança), contra
  ~20-43s/registro do método LLM — **5-10x mais rápido**.
- Custo: **zero tokens de LLM** no caminho rápido.
- Projeção pro lote real do projeto (1870 fornecedores, tier "whatsapp +
  instagram, sem site" do `fornecedores.db`): ~2.1h, vs ~10.4h estimado pro
  método LLM.

## Por que isso interessa pro oracfit/v3

Não é um bug do oracfit — é um padrão de uso que vale generalizar: **para
enriquecimento de dado que só precisa de extração determinística (regex,
não julgamento), gastar um despacho de LLM por registro é caro e lento à
toa.** O caminho certo é: LLM decide UMA VEZ a estratégia/schema/regex
(como fiz aqui), gera o script determinístico, e o script roda sozinho sem
LLM depois — LLM só volta a entrar pros casos que o script marcar como
ambíguos/não encontrados (poucos, comparado ao total). Esse padrão
("LLM escreve a ferramenta, ferramenta roda sozinha depois") pode valer
como modo novo ou guia de boas práticas no oracfit v3, distinto do modo
atual onde cada despacho é 1 chamada de modelo por unidade de trabalho.

## Risco declarado

`curl_cffi` + busca ainda depende de DuckDuckGo/Yahoo não mudarem a defesa
anti-bot (histórico mostra que evoluem). Sem manutenção contínua, esse
script também vai quebrar eventualmente — mesma classe de risco do
`instaloader`, só que mais barato de reescrever por ser simples (150 linhas,
regex, sem dependência de estrutura interna de API do Instagram).
