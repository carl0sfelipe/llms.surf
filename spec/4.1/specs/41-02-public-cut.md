---
id: "41-02-public-cut"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# docs/PUBLIC-CUT.md descreve o corte 4.1.0

## Objetivo

`docs/PUBLIC-CUT.md` ainda descreve o corte 3.5.0 (título e `106 postmortems`). Atualize-o para o corte 4.1.0 com os números da árvore e uma seção `## What changed since 3.5.0` contendo só os deltas verificáveis abaixo. Não descreva features novas: o que não estiver nos dados verificados vai como `[A DEFINIR]` para o dono preencher.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- `VERSION` = `4.1.0`. Contagens da árvore/`DATA.stats`: 115 incidentes, 27 modelos, 21 modos, 8 adapters + 1 stub, 37 suítes.
- Corte 3.5.0 (site publicado em 2026-09-20): 106 incidentes, 23 modelos, 20 modos, 8 adapters + 1 stub, 34 suítes.
- Adapters na árvore: claude-code, cursor, hermes, llamacpp, opencode, prime-agent, qwen-code, zcode, stub.
- Linhas atuais a trocar: `# Public Cut — llms.surf v3.5.0` (linha 1) e `the 106 postmortems that shipped in this cut` (linha 14).

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: bin/check-docs.sh verde
- como fetchar: bash bin/check-docs.sh
- como comparar: exit 0

## Passos

1. Troque o título para `# Public Cut — llms.surf v4.1.0` e a linha 14 para `115 postmortems`.
2. Acrescente, antes de `## O que fica no monorepo de desenvolvimento`, a seção `## What changed since 3.5.0` com quatro bullets exatamente nestes formatos: `incidents: 106 → 115`, `test suites: 34 → 37`, `models in registry: 23 → 27`, `modes: 20 → 21`, e um quinto bullet `features: [A DEFINIR]`.
3. Não escreva tok/s, $/M, tokens/mês nem datas de lançamento.
4. Rode `bash bin/check-docs.sh` (exit 0).
5. Commit com a mensagem exata: `docs: PUBLIC-CUT descreve o corte 4.1.0`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: grep -q '^# Public Cut — llms.surf v4.1.0$' docs/PUBLIC-CUT.md && grep -q '115 postmortems' docs/PUBLIC-CUT.md && grep -q 'incidents: 106 → 115' docs/PUBLIC-CUT.md && ! grep -q '3.5.0$' docs/PUBLIC-CUT.md

## Oráculo

- comando: bash spec/4.1/oracles/public-cut.sh
- exit esperado: 0

## Resultado

O documento do corte público bate com a árvore e mostra o que mudou desde 3.5.0 só com números verificáveis.
