---
id: "41-03-incidents-schema"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Todo incidente tem frontmatter completo; um gate novo impede regressão

## Objetivo

Dos 115 incidentes, 114 têm `regra:` e 1 não tem; os demais campos (`id`, `titulo`, `data`, `recorrivel`, `status`, `interage_com`) aparecem em 114 ou mais. Complete o frontmatter faltante lendo o corpo do próprio incidente e crie `tests/test-incidents-schema.sh`, que falha se qualquer `incidents/*.md` (exceto README.md e `uso/`) não tiver as 7 chaves. Como isso adiciona uma suíte, atualize as contagens públicas (38).

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Chaves obrigatórias, na ordem em que aparecem nos incidentes existentes: `id`, `titulo`, `data`, `recorrivel`, `regra`, `status`, `interage_com`.
- Contagem de chaves hoje (grep no frontmatter de todos os incidentes): interage_com 154 (alguns repetem), titulo 114, status 114, recorrivel 114, id 114, data 114, regra 113.
- Descubra qual incidente está sem `regra:` com: for f in incidents/*.md; do awk 'NR==1&&/^---/{p=1;next} p&&/^---/{exit} p' "$f" | grep -q '^regra:' || echo "$f"; done
- Suítes hoje: 37 (`tests/test-*.sh`). Locais que citam a contagem: `site/app.js` (`suites: 37`), `site/llms.txt` (`- test suites: 37`), `README.md` linha 118 (`37 test suites`).
- Estilo dos testes: bash, `set -euo pipefail`, `fail()` imprime e sai 1, `echo ok ...` por checagem (ver `tests/test-site-honesty.sh`).

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: tests/test-site-honesty.sh e bin/check-docs.sh verdes com 38 suítes
- como fetchar: bash tests/test-site-honesty.sh && bash bin/check-docs.sh
- como comparar: exit 0 nos dois

## Passos

1. Encontre o incidente sem `regra:` e acrescente a chave com o valor derivado do texto do próprio incidente (se o texto não decidir, use `regra: [A DEFINIR]`).
2. Crie `tests/test-incidents-schema.sh` (chmod +x): para cada `incidents/*.md` fora de README.md e `uso/`, extraia o frontmatter (entre a primeira linha `---` e a próxima `---`) e exija as 7 chaves; imprima `ok incidents=<n>` no fim.
3. Atualize `site/app.js` (`suites: 38`), `site/llms.txt` (`- test suites: 38`) e `README.md` (`38 test suites`).
4. Rode `bash tests/test-incidents-schema.sh`, `bash tests/test-site-honesty.sh` e `bash bin/check-docs.sh` (todos exit 0).
5. Commit com a mensagem exata: `incidents: frontmatter completo + tests/test-incidents-schema.sh`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: test -x tests/test-incidents-schema.sh && bash tests/test-incidents-schema.sh | grep -q '^ok incidents=115' && grep -q 'suites: 38' site/app.js && grep -q 'test suites: 38' site/llms.txt

## Oráculo

- comando: bash spec/4.1/oracles/incidents-schema.sh
- exit esperado: 0

## Resultado

Nenhum postmortem entra sem a estrutura mínima, e o site continua contando as suítes certas.
