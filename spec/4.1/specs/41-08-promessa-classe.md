---
id: "41-08-promessa-classe"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# A promessa de 1 bilhão de tokens ganha unidade, pesos por classe e condição de crédito (DECISÃO DO DONO)

## Objetivo

A promessa pública (“1,000,000,000 llms-surf cloud tokens”) é ambígua por um fator de ~11 entre um modelo de 8B e um de 70B. Acrescente ao `data/lineup-points.json` um bloco `pledge` com unidade, pesos por classe, condição de crédito e validade, e explique a unidade em `site/llms.txt` e `site/index.html`. Os valores são decisão do dono: use exatamente os dos dados verificados.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Bloco a inserir em `data/lineup-points.json` (chave `pledge`, no nível raiz): `total_tokens: 1000000000`, `unit: "class-S-equivalent"`, `class_weights: {"S": 1, "M": 6, "L": 11}`, `credited_when: "llms-surf cloud goes live and the first measured throughput is committed to the tree"`, `expires_months: 24`.
- Definição das classes para a copy: S = modelos de 7–9B; M = 32B; L = 70B (parâmetros do modelo servido). 1 token L consome o equivalente a 11 tokens S do pool.
- `site/llms.txt`: acrescentar, na seção Whitelist, uma frase contendo literalmente `class-S-equivalent` e os pesos S=1, M=6, L=11.
- `site/index.html`: na seção da lineup (“One billion tokens...”), acrescentar uma frase contendo `class-S` com a mesma regra.
- O JSON tem comentários em chaves `_comment`; mantenha o estilo e a validade (`jq .`).

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

Esta spec só roda se o dono confirmou os pesos. Está comentada em `batch-noite.txt` por padrão.

## Barra

- nome: jq -e .pledge data/lineup-points.json
- como fetchar: jq .pledge data/lineup-points.json
- como comparar: campos e valores exatamente como nos dados verificados

## Passos

1. Edite `data/lineup-points.json` acrescentando o bloco `pledge` (JSON válido).
2. Acrescente as frases em `site/llms.txt` e `site/index.html`.
3. Rode `bash tests/test-site-honesty.sh` e `bash tests/test-lineup-machine.sh` (exit 0).
4. Commit com a mensagem exata: `lineup: promessa definida em class-S-equivalent (S=1, M=6, L=11)`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: jq -e '.pledge.unit == "class-S-equivalent" and .pledge.class_weights.L == 11' data/lineup-points.json && grep -q 'class-S-equivalent' site/llms.txt && grep -q 'class-S' site/index.html

## Oráculo

- comando: bash spec/4.1/oracles/promessa-classe.sh
- exit esperado: 0

## Resultado

A promessa passa a ter uma aritmética que qualquer um pode conferir.
