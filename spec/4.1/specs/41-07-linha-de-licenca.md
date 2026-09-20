---
id: "41-07-linha-de-licenca"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Uma frase de uso permitido, idêntica, em LICENSE, llms.txt, index.html e README (DECISÃO DO DONO)

## Objetivo

Hoje `LICENSE` diz que nenhuma licença é concedida, e o site diz “clone in 2 minutes”. Resolva a contradição com uma frase única de resumo de uso permitido, cuja fonte é o `LICENSE`, repetida sem alteração em `site/llms.txt`, `site/index.html` e `README.md`. ATENÇÃO: a frase é decisão do dono; use exatamente a frase dos dados verificados, sem reescrever.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Frase decidida pelo dono (copiar literalmente): `Permitted: clone and run locally for evaluation and personal use. Not permitted: redistribution, resale, or hosting for third parties. Commercial use requires written permission.`
- No `LICENSE`, a frase entra numa linha própria, logo após o parágrafo `Contact the copyright holder for licensing inquiries.`, com o prefixo exato `Permitted use summary: `.
- Em `site/llms.txt`, entra como bullet na seção `## Do not` ou logo abaixo do cabeçalho `> LICENSE is proprietary...` — sem prefixo.
- Em `site/index.html`, entra no bloco `// contract` do twin de agentes, como texto visível — sem prefixo.
- Em `README.md`, entra na seção que fala da licença (procure `LICENSE`/`proprietary`) — sem prefixo.

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

Esta spec só roda se o dono confirmou a frase. Está comentada em `batch-noite.txt` por padrão.

## Barra

- nome: a frase exata acima nos quatro arquivos
- como fetchar: grep -F 'Permitted: clone and run locally' LICENSE site/llms.txt site/index.html README.md
- como comparar: 4 arquivos, mesma frase

## Passos

1. Insira a frase nos quatro arquivos conforme os dados verificados.
2. Rode `bash tests/test-site-honesty.sh` (exit 0).
3. Commit com a mensagem exata: `license: resumo de uso permitido, uma frase, quatro lugares`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: test $(grep -lF 'Permitted: clone and run locally for evaluation and personal use.' LICENSE site/llms.txt site/index.html README.md | wc -l) -eq 4

## Oráculo

- comando: bash spec/4.1/oracles/linha-de-licenca.sh
- exit esperado: 0

## Resultado

Quem lê “clone” sabe em uma frase o que pode e o que não pode fazer.
