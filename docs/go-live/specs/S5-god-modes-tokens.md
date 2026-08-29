# S5 — god modes fora do default + seção honesta de tokens

Duas decisões numa story porque compartilham o mesmo movimento (a superfície
de entrada mostra menos, e o que mostra é verdadeiro):

- **D7:** os 17 god modes ficam no git e no CLI (`oracfit modes` lista os 20)
  e saem do DEFAULT da TUI — a home mostra o trio de surf (paddle / tow /
  surfcheck); god mode continua disponível digitando o id.
- **D6/D9:** tokens a custo viram seção HONESTA: não existe preço, não existe
  número de demanda anunciado; existe waitlist (template de issue) e critério
  mecânico de unlock — demanda lida da lista + throughput medido no
  registry/ledger deste tree. Nada é anunciado antes de estar no dado.

## O que fazer

Estado exigido (implementado; oráculo abaixo é gate permanente):

1. TUI: default do menu e do wizard é o trio de surf, construído da saída de
   `oracfit alias` (uma fonte de verdade só); god modes citados como
   acessíveis, não listados.
2. `site/index.html`: seção `#tokens` na jornada humana — "no tokens for
   sale. a waitlist exists; a number doesn't." — com link para o template
   `tokens-waitlist.md`. Sem preço, sem data, sem N de demanda, sem tps.
3. `site/llms.txt`: blocos "Surf aliases", "Modes are YAML you can share" e
   "Tokens at cost — nothing for sale" (a superfície de agente conta a mesma
   verdade).
4. `tests/test-site-honesty.sh` permanece VERDE — todo número do site continua
   sendo contado do tree; nenhum número novo foi inventado.

## Regras

Nao invente numero, prazo ou fonte alem dos listados. Nao use declare const
como workaround — seção de site que promete produto inexistente é o bug que o
teste de honestidade existe para pegar.

## Dados verificados

- Existe `site/index.html` neste tree.
- Existe `site/llms.txt` neste tree.
- Existe `site/app.js` neste tree.
- Existe `tests/test-site-honesty.sh` neste tree.
- Existe `.github/ISSUE_TEMPLATE/tokens-waitlist.md` neste tree.

## Verificação

O gate de honestidade do site, inteiro:

VERIFICACAO: bash tests/test-site-honesty.sh && grep -qi waitlist site/index.html

## Oráculo

- comando: bash tests/test-site-honesty.sh && grep -qi waitlist site/index.html && grep -q "Tokens at cost" site/llms.txt && grep -q "surf aliases" bin/llms-surf-tui.sh && test -f .github/ISSUE_TEMPLATE/tokens-waitlist.md
- exit esperado: 0 — honestidade do site verde, seção de tokens presente na
  jornada humana E na superfície de agente, TUI no trio de surf, template de
  waitlist no repo.

## Barra

docs/go-live/DECISIONS-D1-D10.md (D6, D7, D9) e site/llms.txt — o texto da
seção é a posição pública; mudar o texto SEM mudar o mecanismo de unlock é
violação de D6.
