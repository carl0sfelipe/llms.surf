---
id: "41-01-contagens-estaticas"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Contagens estáticas do site iguais a DATA.stats, com gate que impede regressão

## Objetivo

Os números que aparecem no site sem JavaScript (fallback dos `data-stat`, `#wipe-count`, meta description, `readme.html`) e a linha 88 de `site/llms.txt` ainda dizem 106 / 3.5.0, enquanto `site/app.js` (`DATA.stats`) e a árvore dizem 115 / 4.1.0. Corrija os textos estáticos para os valores de `DATA.stats` e estenda `tests/test-site-honesty.sh` para vigiar esses lugares, de modo que uma adulteração em `site/index.html` (`#wipe-count`, `data-stat`), `site/readme.html` (`public cut vX`) ou `site/incidents.html` faça o teste falhar.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- `VERSION` = `4.1.0`; `site/app.js` `DATA.stats`: incidents 115, models 27, modes 21, adapters 8, adaptersStub 1, suites 37, version "4.1.0".
- `site/llms.txt`: linha 51 tem vírgula sobrando (`models in registry: 27,`); linha 88 diz `the ledger; 106 postmortems in this cut`.
- `site/index.html`: linha 175 `<span class="g" id="wipe-count">106</span>`; linha 316 `<b data-stat="incidents">106</b>`; linha 321 `v<b data-stat="version">3.5.0</b>`.
- `site/incidents.html`: linha 7 meta description com `106 incidents`; linha 63 `id="wipe-count">106<`.
- `site/readme.html`: linha 64 `public cut v3.5.0`.
- `tests/test-site-honesty.sh` já compara `DATA.stats` com a árvore e já vigia `version:`/`incidents:` em `site/llms.txt` (linhas 76–79); não vigia `index.html`, `readme.html` nem `incidents.html`.
- Os `data-stat` são preenchidos por JS a partir de `DATA.stats`, mas o fallback estático é o que agentes e leitores sem JS veem (a própria `llms.txt` promete twin com os mesmos fatos).

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: tests/test-site-honesty.sh verde com a árvore e vermelho com adulteração
- como fetchar: bash tests/test-site-honesty.sh
- como comparar: exit 0 na árvore; exit 1 quando um número estático é trocado (o oráculo faz a mutação numa cópia)

## Passos

1. Em `site/llms.txt`: remova a vírgula da linha 51 e troque `106 postmortems` por `115 postmortems` (use o valor de `DATA.stats.incidents`, não um número decorado).
2. Em `site/index.html`: troque os fallbacks estáticos 106 → 115 e 3.5.0 → 4.1.0 nos elementos `#wipe-count`, `data-stat="incidents"` e `data-stat="version"`. Não mude o JS.
3. Em `site/incidents.html`: meta description e `#wipe-count` → 115. Em `site/readme.html`: `public cut v4.1.0`.
4. Em `tests/test-site-honesty.sh`: acrescente checagens que leem `$incidents_disk`/`$version_disk` e falham se `site/index.html` não tiver `id="wipe-count">$incidents_disk<` e `data-stat="incidents">$incidents_disk<` e `data-stat="version">$version_disk<`; se `site/incidents.html` não tiver `wipe-count">$incidents_disk<` e `$incidents_disk incidents` na meta; se `site/readme.html` não tiver `public cut v$version_disk`. Use `fail` e `echo ok ...` no mesmo estilo do arquivo.
5. Rode `bash tests/test-site-honesty.sh` e `bash bin/check-docs.sh`; ambos precisam sair 0.
6. Commit com a mensagem exata: `site: fallbacks estáticos = DATA.stats; honesty vigia index/readme/incidents`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: grep -c 'wipe-count">115<' site/index.html site/incidents.html | grep -q ':1$' && grep -q 'the ledger; 115 postmortems' site/llms.txt && ! grep -q '27,$' site/llms.txt && grep -q 'public cut v4.1.0' site/readme.html && grep -q 'wipe-count' tests/test-site-honesty.sh

## Oráculo

- comando: bash spec/4.1/oracles/contagens-estaticas.sh
- exit esperado: 0

## Resultado

Site e `llms.txt` contam a mesma história sem JavaScript, e o gate de honestidade cobre os lugares que apodreceram desta vez.
