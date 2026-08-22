---
id: 2026-08-11-instaloader-quebrado-parcial-fallback-webfetch-funciona
titulo: instaloader quebra intermitente em conta business (bug externo) — webfetch+DuckDuckGo/Yahoo é fallback comprovado
data: 2026-08-11
recorrivel: sim
regra: nao-catalogada (achado de ecossistema, nao bug do oracfit)
status: aberto
interage_com: "2026-08-11-feedback-uso-exaustivo-sessao-pivot-e-fornecedores-v3"
---

# instaloader quebra intermitente — webfetch + busca é fallback validado

## Contexto

Pesquisando solução de enriquecimento de dados (checar se fornecedor/lead
ainda tem Instagram ativo) pra completar `data/fornecedores/fornecedores.db`.
Não é bug do oracfit — é achado sobre ferramenta externa, registrado aqui
porque afeta diretamente o próximo passo do trabalho de enriquecimento
despachado via `deepseek_direct_flash`.

## Teste feito

`instaloader` 4.15.3 (PyPI, release mar/2026, a mais recente) testado contra
3 handles reais do banco de fornecedores + `@nasa` como controle:

- `@nasa`: funcionou 2x seguidas, número de seguidores real e crescente
  (confirma não é cache/mock).
- `@belissimabras`, `@atacadodamalu`: `QueryReturnedBadRequestException 400`
  — `"Asset asset://laser.provider/ig_business_category_subvertical has been
  deleted. You cannot use this schema"`.
- `@aranbela`: `ProfileNotExistsException` (pode ser conta renomeada/some, ou
  mesma instabilidade).

Confirmado que **não é 100% "toda conta business"** — `@nasa` também é
`is_business_account: true` e funcionou. É falha parcial/intermitente do
schema do Instagram, batendo com o relatado publicamente em
`instaloader/instaloader` issue #2656 ("not updated since Nov 2025") e não
resolvido nem na PyPI mais recente.

## Solução aplicada

Método híbrido, documentado em skill `enriquecer-instagram`
(`.claude/skills/enriquecer-instagram/SKILL.md`, global e no repo
<repo-cliente>.live-imports):

1. Tenta `instaloader` via `~/bin/instagram-lookup.py <handle>` — rápido,
   número exato, zero custo de LLM, quando funciona.
2. Se falhar (exit code 2 do script — instaloader quebrado, não "perfil não
   existe"), cai pro método já **validado em despacho real** no piloto de 20
   fornecedores (2026-08-11): `webfetch` em
   `https://html.duckduckgo.com/html/?q=<handle>+instagram`, com fallback pra
   `https://search.yahoo.com/search?p=<handle>+instagram` quando o
   DuckDuckGo bate em captcha (aconteceu depois de ~2 buscas seguidas no
   piloto — não é confiável em lote grande sem esse segundo fallback).

Acesso direto a `instagram.com/<handle>/` **nunca** funciona — só retorna
shell JS vazio, confirmado antes de desenhar a spec do piloto.

## Números reais do piloto (prova de que o fallback funciona)

20/20 fornecedores enriquecidos com sucesso usando só o método de busca
(nem tentamos instaloader nesse piloto — foi testado depois, separado).
~43s/registro, 5 status "ativo" com evidência real (data de post <12 meses),
4 "provavelmente_inativo", 11 "indeterminado" (sem inventar quando não achou
evidência). Zero número/data fabricado — todo campo preenchido veio
literalmente do snippet de busca.

## Pode acontecer de novo?

Sim — issue pública confirma que `instaloader` não tem update desde
novembro/2025 e o bug de schema é conhecido, sem previsão de correção.
Qualquer uso futuro de `instaloader` pra enriquecimento em massa PRECISA do
fallback, não é opcional. Script `~/bin/instagram-lookup.py` já sinaliza isso
via exit code (2 = "tenta o outro jeito"), não deixa quem chama achar que
"perfil não existe" quando na verdade é a ferramenta que quebrou.
