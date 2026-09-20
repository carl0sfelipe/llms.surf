---
id: "41-04-claims-nao-medidos"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Gate contra números não medidos sobre a cloud

## Objetivo

O site promete “no price, no date, no tps, no token amounts exist anywhere until measured in the tree”. Hoje isso é regra em prosa. Transforme em mecanismo: `tests/test-no-unmeasured-claims.sh` falha se `site/llms.txt`, `site/readme.html`, `site/blog/posts/*.md` ou `site/index.html` (fora das seções `#assumed-rates` e `#estimate`) contiverem os padrões abaixo. Se hoje houver ocorrência fora do estimador, remova-a. Adicione a suíte às contagens públicas.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Padrões proibidos (regex ERE): `tok/s`, `tokens/s`, `\$/M`, `\$ ?[0-9]+(\.[0-9]+)? ?/ ?M`, `tokens per month`, `tokens/m[eê]s`, `goes live on`, `launch(es|ing)? on (Jan|Feb|...|Dec)`.
- Seções do estimador em `site/index.html`: `id="assumed-rates"` (linha 198) e `id="estimate"` (linha 223). Só nelas números assumidos são permitidos, rotulados como assumidos.
- Suítes hoje: 37 (ou 38 se `41-03` já tiver rodado — conte `tests/test-*.sh` na hora e use o número real). Locais da contagem: `site/app.js`, `site/llms.txt`, `README.md` linha 118.
- Estilo dos testes: ver `tests/test-site-honesty.sh`.

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: tests/test-no-unmeasured-claims.sh verde na árvore e vermelho com uma frase 'We serve 9999 tok/s' injetada no llms.txt
- como fetchar: bash tests/test-no-unmeasured-claims.sh
- como comparar: exit 0 na árvore; exit 1 com a injeção (o oráculo faz isso numa cópia)

## Passos

1. Crie `tests/test-no-unmeasured-claims.sh` (chmod +x) com os padrões acima; para `site/index.html`, remova as seções `#assumed-rates`/`#estimate` antes de procurar (awk entre `<section ... id="...">` e `</section>`).
2. Rode o teste; se falhar em texto existente, corrija o texto (remova o número ou mova para dentro do estimador com rótulo 'assumed').
3. Atualize as três contagens de suítes para o número real de `tests/test-*.sh`.
4. Rode `bash tests/test-site-honesty.sh` e `bash bin/check-docs.sh` (exit 0).
5. Commit com a mensagem exata: `tests: gate contra claims não medidos (tok/s, $/M, datas de cloud)`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: test -x tests/test-no-unmeasured-claims.sh && bash tests/test-no-unmeasured-claims.sh && grep -c 'tok/s' tests/test-no-unmeasured-claims.sh | grep -qv '^0$'

## Oráculo

- comando: bash spec/4.1/oracles/claims-nao-medidos.sh
- exit esperado: 0

## Resultado

A promessa de honestidade sobre a cloud vira código que recusa, não frase que confia.
