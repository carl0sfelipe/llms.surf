---
id: 2026-07-28-versao-publicada-sem-commit-fonte-de-0-1
titulo: versao publicada sem commit — fonte de 0.1.3 e 0.1.4 perdida
data: 2026-07-28
recorrivel: sim
regra: 36
status: promovido
---

# versao publicada sem commit — fonte de 0.1.3 e 0.1.4 perdida

## Sintoma

`@carl0sfelipe/kit-storefront` tinha 0.1.3, 0.1.4 e 0.1.5 instaladas no
consumidor. O último commit do repositório do framework era o bump de 0.1.2.

```
$ ls -d <home-do-dono>/<repo-cliente>.live-imports/node_modules/.pnpm/@carl0sfelipe+kit-storefront@*
0.1.1  0.1.3  0.1.4  0.1.5

$ git -C <home-do-dono>/medusa-br-framework log --oneline -1
c7dbfba chore(kit-storefront): bump 0.1.2

$ git -C <home-do-dono>/medusa-br-framework tag
(vazio)
```

O storefront em produção depende de 0.1.5. A fonte dessa versão existia
apenas na working tree não commitada de uma única máquina — a branch
também não estava no remoto (8 commits à frente de `origin`), e `main`
não continha o pacote.

## Causa

Publicação manual fora do fluxo de release, sem gate entre "publicar" e
"commitar". Três mecanismos ausentes ao mesmo tempo:

1. Nenhum gate de PR — o único workflow que roda no repositório é o que
   publica (`.github/workflows/publish.yml` e `release.yml`, ambos em
   `push: main`).
2. Nenhuma tag por versão publicada — não havia como detectar que uma
   versão do registry não tinha commit correspondente.
3. `publish.yml` não tem step de build e roda em paralelo com
   `release.yml` (concurrency groups distintos), então a publicação podia
   sair de um checkout que nunca passou por validação.

## Extensão real do dano (medida depois, corrige a primeira leitura)

A primeira avaliação deste incidente dizia "perda permanente de código".
**Está errada.** O `dist/` publicado é saída de `tsc` puro — sem bundler,
sem minificação, com `.d.ts` ao lado — e o diff entre versões mostra que
os deltas são mínimos:

```
$ diff -rq .../kit-storefront@0.1.3/dist .../kit-storefront@0.1.4/dist
logo.js, marquee.js, marquee.d.ts      (3 arquivos)

$ diff -rq .../kit-storefront@0.1.4/dist .../kit-storefront@0.1.5/dist
index.js, index.d.ts                    (2 arquivos)
```

Mapa de reconstrução, verificado arquivo a arquivo:

| Versão | Reconstrói a partir de | Diferença |
|---|---|---|
| 0.1.3 | commit `c7dbfba` | só `package.json`: version 0.1.3 e deps pinadas em `0.1.1`. O `src/` é idêntico — os 3 exports de tipo que o incidente de publish atribuía à 0.1.3 já estavam em `c7dbfba:src/index.ts:9-10` |
| 0.1.4 | commit `4f3d3db` | menos as duas linhas de export de `Logo`/`Marquee` no `index.ts` |
| 0.1.5 | commit `504d453` | commitada |

Nenhum código precisou ser lido de JSX compilado. **Custo real: perícia
para descobrir o que havia sido publicado, não perda de fonte.**

Não foram criadas tags para 0.1.3 e 0.1.4: nenhum commit contém exatamente
aquele conteúdo (o campo `version` do `package.json` diverge), e tag
apontando para código que não é aquele é registro falso. O mapa acima
substitui a tag.

## Correção aplicada

Recuperação (2026-07-28):

- `medusa-br-framework` 4f3d3db — fonte da 0.1.5 commitada
- `medusa-br-framework` 504d453 — deps de volta a `workspace:*`, incidente
  de publish commitado
- tags criadas: `v0.1.1` (5b9f5bc), `kit-storefront@0.1.2` (c7dbfba),
  `kit-storefront@0.1.5` (504d453)
- `main` avançado e enviado nos dois repositórios

**0.1.3 e 0.1.4 continuam sem commit correspondente** — reconstrutíveis
pelo mapa acima, mas não rastreáveis por `git`.

Prevenção ainda **não** implementada — é o artefato SEP-03 do plano de
separação: deletar `publish.yml`, gate de PR com build/type-check/test,
`prepack: pnpm build` nos 20 pacotes e `bin/pre-publish-check.sh`.

## Pode acontecer de novo?

Sim. Nada hoje impede publicar de uma working tree suja, e nada detecta
versão no registry sem commit correspondente. Enquanto SEP-03 não existir,
a próxima publicação manual repete o caso.

Regra candidata: **publicação exige working tree limpa e tag** — publicar
com `git status` não vazio, ou sem criar tag apontando para o commit
publicado, é perda de fonte em potencial. Mecanismo: `prepublishOnly` que
recusa working tree suja + `bin/pre-publish-check.sh` verificando que
`HEAD` está no remoto.

interage_com: reforça a regra 25 (dry-run antes de gravar em store de
dados) — registry publicado é store de dados irreversível, e ali não há
dry-run possível depois do fato.
