---
id: "41-06-post-lancamento"
schema: 1
status: draft
owner: "dogfood-noite-4.1"
modelo: "qwen38-27b-exl3-3090"
tentativas: 0
bloqueio: false
evidencia: ""
---

# Post de lançamento do corte 4.1.0 no blog

## Objetivo

Escreva `site/blog/posts/lancamento-4-1-0.md` anunciando o corte público 4.1.0, no mesmo formato de frontmatter do post existente, e publique com `python3 site/blog/build.py`. O post fala do que existe: oráculo mecânico, dispatcher local, os 115 incidentes, a whitelist/lineup e o que mudou desde 3.5.0. Nada sobre preço, tok/s, tokens/mês ou data da cloud.

## Dados verificados (o modelo PODE usar só isto — tudo conferido na árvore em 2026-09-20)

- Frontmatter de referência (`site/blog/posts/resposta-ao-akita-harness-qwen.md`): `title`, `description`, `date` (ISO), `slug`, `lang: pt-BR`, `author: Carlos`, `tags` (lista), `canonical: https://llms.surf/blog/<slug>`.
- Slug deste post: `lancamento-4-1-0`. Data: 2026-09-20.
- Fatos publicáveis: versão 4.1.0; 115 incidentes (106 no 3.5.0); 27 modelos no registro; 21 modos; 8 adapters + 1 stub (claude-code, cursor, hermes, llamacpp, opencode, prime-agent, qwen-code, zcode); 37 suítes (ou o número real na hora); contrato do oráculo conforme `site/llms.txt` (comando shell, sha256 congelado, gates leem conteúdo em disco, watchdog, critic-guard, exit 0 é vitória).
- Whitelist: `site/llms.txt` seção “Whitelist — llms-surf cloud tokens x bestmodel.run”: entrar custa uma issue, sair custa um clique; nenhum número até ser medido.
- Build: `python3 site/blog/build.py` gera `site/blog/<slug>/index.html` e atualiza `site/blog/index.html`.
- Tamanho: 250 a 1200 palavras no corpo.

Não invente número, prazo, nome, caminho ou fonte além dos listados em “Dados verificados”.
Campo que você não conseguir determinar a partir da árvore fica marcado [A DEFINIR], nunca em
branco. NUNCA use declare const como workaround — importe de verdade. Não edite o oráculo nem
os arquivos em spec/4.1/oracles/. Não toque em incidents/uso/, ledger/ ou .dispatch/.

## Barra

- nome: post existente como referência de tom e formato
- como fetchar: cat site/blog/posts/resposta-ao-akita-harness-qwen.md
- como comparar: mesmo frontmatter; mesma honestidade com números

## Passos

1. Escreva o post em pt-BR com o frontmatter acima e o corpo em Markdown (título H1 no corpo é opcional; o build usa `title`).
2. Inclua uma seção curta “O que mudou desde 3.5.0” só com os deltas verificáveis e uma seção “Whitelist” que repita a regra “nenhum número até ser medido na árvore”.
3. Rode `python3 site/blog/build.py`; confira que `site/blog/lancamento-4-1-0/index.html` existe e que `site/blog/index.html` lista o post.
4. Rode `bash tests/test-site-honesty.sh` (exit 0).
5. Commit com a mensagem exata: `blog: post de lançamento do corte 4.1.0`.

## Verificação

Comandos que provam propriedade do conteúdo (não só existência de arquivo):

VERIFICACAO: grep -q '^slug: lancamento-4-1-0' site/blog/posts/lancamento-4-1-0.md && grep -q '4.1.0' site/blog/posts/lancamento-4-1-0.md && test -s site/blog/lancamento-4-1-0/index.html && grep -q 'lancamento-4-1-0' site/blog/index.html

## Oráculo

- comando: bash spec/4.1/oracles/post-lancamento.sh
- exit esperado: 0

## Resultado

O lançamento tem um texto publicado que diz só o que a árvore sustenta.
