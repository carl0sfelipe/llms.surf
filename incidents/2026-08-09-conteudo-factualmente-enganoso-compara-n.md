---
id: 2026-08-09-conteudo-factualmente-enganoso-compara-n
titulo: conteudo-factualmente-enganoso-compara-novo-<repo-cliente>-com-usado-ml-sem-disclosing
data: 2026-08-09
recorrivel: sim
regra: 43
status: promovido
---

# Conteúdo factualmente enganoso: compara novo da Orbe com usado do ML sem disclosing

## Sintoma

O post do blog `<host-local>-ser-6800u-vale-a-pena` (publicado em <repo-cliente>.live ~21:55,
despublicado às 22:57 após detecção humana) continha uma claim comercialmente
nociva E factualmente enganosa: comparava o **Beelink SER5 Max 24GB/500GB NOVO
da Orbe (R$ 4.290)** com anúncios do **Beelink SER5 Max 32GB/1TB USADO no
Mercado Livre (R$ 3.299-3.599)** e concluía "a Orbe tá cara", **sem disclosing
de que os preços do ML são de unidades usadas (sem caixa)**.

Verificado no MDX publicado (linhas 14, 69, 73, 77, 170, 186, 201):

- **Linha 14 (resposta direta, topo):** *"Entre R$ 3.299,00 e R$ 3.599,00 você
  encontra o mesmo Beelink SER5 Max com 32GB..."* — sem dizer que é usado.
- **Linha 69 (tabela):** *"Beelink SER5 Max 32GB/1TB | Mercado Livre | R$ 3.299
  a R$ 3.599 | [Busca Mercado Livre]"* — link clicável `lista.mercadolivre.com.br/...`.
- **Linha 73:** *"O mesmo modelo com 32GB e 1TB está entre R$ 691 e R$ 991 mais
  barato que a versão 24GB/500GB da Orbe."*
- **Linha 186 (CTA explícito pro concorrente):** *"Para comprar hoje, pesquise
  por anúncios do Beelink SER5 Max 32GB/1TB no Mercado Livre e em lojas
  nacionais com garantia."*

**Fato confirmado pelo operador (2026-08-09):** os R$ 3.299-3.599 do ML são de
**mini PCs USADOS, sem caixa** — não novos. O post apresentou isso como prova de
que "a Orbe tá cara", o que é (a) factualmente enganoso (comparação novo×usado
sem disclosing) e (b) comercialmente nocivo (link + CTA pro concorrente).

O post passou pelo **T4-JUDGE (judge_content_copy)** que aprovou como
`status: APPROVED` — o judge avaliou qualidade editorial/copy, não a **intenção
comercial nem a veracidade factual da comparação de preços**. Nenhum humano
revisou antes de publicar (regra quebrar: publicar em prod sem QA comercial).

## Causa

TRÊS camadas, nenhuma coberta por mecanismo:

1. **T4-CONTENT gerou a narrativa enganosa.** O prompt do agente content_copy
   permite comparações de preço sem exigir disclosing de condição (novo/usado)
   e sem guarda-corpo contra linkar concorrente. O "teste de demanda" do Beelink
   (SKU fora de estoque) deu ao agente liberdade pra "ser honesto", e ele
   interpretou isso como "mande pro concorrente".

2. **T4-JUDGE não valida intenção comercial nem veracidade factual.** O judge
   avalia persuasão/clarity/SEO/brand voice — nenhum critério sobre "isto é
   factualmente honesto?" ou "isto manda cliente embora?". Aprovou copy
   bem-escrita que era comercialmente suicida.

3. **Sem revisão humana/comercial pré-publicação.** O `export-to-blog.py`
   publica direto em `content/blog/` sem gate de revisão. Quem decide publicar
   é quem roda o comando, sem checklist comercial. Lição da sessão: publicamos
   DUAS VEZES (21:55 e 22:47) sem ninguém ler o conteúdo comercial.

Família do bug: mesma raiz do incidente `2026-08-09-oraculo-casa-decision`
(parser confia no formato) e do `2026-07-25-captura-de-resultado-mentiu-3x`
(regra 24: sistema reporta sucesso sobre trabalho defeituoso). Aqui: pipeline
reporta APPROVED sobre conteúdo enganoso.

## Correção aplicada

1. **Despublicação imediata (22:57):** MDX movido pra
   `_disabled/<host-local>-ser-6800u-vale-a-pena-v2-deceptive.mdx` + rebuild.
   Saída do ar confirmada (`<repo-cliente>.live/blog/<host-local>-...` → não encontrado).
2. **Fix do parser `extract_to_blog.py` (Entrega 1, feito antes da detecção):**
   resolveu o bug do fence (body do artigo vs PDP) + sanitize de componentes
   inexistentes (PriceAlert) + JSON-LD. NÃO resolve este incidente — o conteúdo
   enganoso está no corpo do artigo, que o parser extraiu fielmente.
3. **Reescrita do MDX pendente** (próximo passo): remover a comparação
   novo×usado sem disclosing, os links do ML, e o CTA pro concorrente;
   manter a honestidade real (o 24GB/500GB a R$4.290 é caro vs novas opções
   de 32GB) mas oferecer alternativas DA ORBE primeiro (Beelink SER8,
   Minisforum, GMKtec que já estão no catálogo).

## Pode acontecer de novo?

**SIM** — e quase aconteceu de novo nesta sessão (republicamos às 22:47 sem
notar o problema comercial, só vimos o layout). Sem mecanismo, todo post gerado
pelo T4-CONTENT pode conter: (a) comparação novo×usado sem disclosing, (b)
CTA/link pro concorrente, (c) veredito anti-Orbe apresentado como "honestidade".
O T4-JUDGE não pega isso porque não tem critério comercial/factual. **Este
incidente DEVE virar regra/mecanismo.**

Candidata a regra (promover):

> TODO CONTEÚDO GERADO PELO CF QUE MENCIONAR PREÇO DE CONCORRENTE DEVE
> DISCLOSAR A CONDIÇÃO (novo/usado/refurb) E NUNCA LINKAR CONCORRENTE SEM
> OFERECER ALTERNATIVA DA ORBE PRIMEIRO. Comparação novo×usado sem disclosing
> é factualmente enganosa. O T4-JUDGE deve ter critério comercial explícito
> (rejeitar copy que manda cliente embora ou compara conditions diferentes).
> Mecanismo: gate de revisão comercial pré-publicação (humano ou LLM crítico
> com prompt de guarda-corpo) + critério novo no T4-JUDGE. SEM MECANISMO HOJE.

Interage com: regra 16 (problema recorrente vira mecanismo), regra 24 (falso
sucesso — APPROVED sobre conteúdo defeituoso), regra 32 (regra sem mecanismo é
dívida), incidente `2026-08-09-oraculo-casa-decision` (mesma família: pipeline
confia sem validar). Supera a suposição de que "judge de copy = judge de
qualidade comercial" — copy boa pode ser comercialmente nociva.

interage_com: 16 (INSTANCIA: esta virou regra 43 com mecanismo real, não texto),
24 (REFORÇA: fairness_check é o complemento — barrar APPROVED falso sobre
conteúdo enganoso, mesma família do exit-0-sem-fazer-nada), 32 (SATISFEITA: o
mecanismo existe — _fairness_check em bmad_crew.py + 7 testes em
test_fairness_check.py + fairness_warning() em market_types.py). Sobreposição
de termo alertada pelo promote: 26/primeiro (ausência não é independência — 26
é sobre prova de ausência, 43 é sobre disclosure comercial, domínios distintos),
39/reprova (39 é sobre oráculo quebrado, 43 é sobre conteúdo enganoso — ambos
reprovam por motivo diferente, sem conflito). O que pode quebrar: a heurística
textual tem FALSO NEGATIVO se o texto omitir preço numérico (ex.: 'mais barato
lá' sem R\$) — não detecta. E falso positivo teórico se um review legítimo citar
'R\$ X no Mercado Livre, mas só novo na caixa' com o disclosing fora da janela
de 300 chars. Mitigação: janela de 300 chars é generosa; testes cobrem os casos
principais. Sempre complementar com revisão humana comercial pré-publicação.
