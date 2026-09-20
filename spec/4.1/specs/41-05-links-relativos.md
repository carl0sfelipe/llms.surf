---
id: "41-05-links-relativos"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Nenhum link relativo quebrado no site e nas SKILLs; gate novo

## Objetivo

Crie `tests/test-links.sh`, que resolve todo `href`/`src` relativo em `site/**/*.html` e todo link Markdown relativo em `SKILL.md` e `fluxos/**/SKILL.md`, e falha se algum alvo não existir. Corrija os que estiverem quebrados. Adicione a suíte às contagens públicas.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Arquivos a varrer: `site/**/*.html` (inclui `site/blog/**/index.html`), `SKILL.md`, `fluxos/*/SKILL.md`.
- Ignorar: `http(s):`, `mailto:`, `data:`, `javascript:`, `tel:`, âncoras `#...` e caminhos começando com `/`.
- Resolução: relativa ao diretório do arquivo; se não existir, tente relativa à raiz do repo.
- Na varredura de 2026-09-20 não havia links quebrados; o gate existe para o futuro.
- Suítes: conte `tests/test-*.sh` na hora; locais da contagem: `site/app.js`, `site/llms.txt`, `README.md` linha 118.

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: tests/test-links.sh verde na árvore e vermelho com um href para arquivo inexistente injetado em site/readme.html
- como fetchar: bash tests/test-links.sh
- como comparar: exit 0 / exit 1 (o oráculo injeta numa cópia)

## Passos

1. Crie `tests/test-links.sh` (chmod +x), preferencialmente chamando um bloco `python3 - <<'PY' ... PY` para a varredura, no estilo dos outros testes.
2. Rode o teste; corrija qualquer link quebrado que aparecer.
3. Atualize as três contagens de suítes.
4. Rode `bash tests/test-site-honesty.sh` e `bash bin/check-docs.sh` (exit 0).
5. Commit com a mensagem exata: `tests: gate de links relativos (site + SKILLs)`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: test -x tests/test-links.sh && bash tests/test-links.sh && grep -q 'fluxos' tests/test-links.sh

## Oráculo

- comando: bash spec/4.1/oracles/links-relativos.sh
- exit esperado: 0

## Resultado

Um link morto no site ou numa SKILL passa a ser falha de teste, não descoberta de leitor.
