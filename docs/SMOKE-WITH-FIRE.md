# Smoke with fire — go-live do llms.surf

> **Quando:** depois do site público v1 estar no ar (DNS + `site/`
> deployado), não antes. **Quem:** Fable (caro, meta + dogfood) na Phase A;
> anéis GLM (`core/modes/glm_smart.yaml`) na Phase B. **Por quê:** GLM não
> recebe a espingarda S25/S26 sem oráculo congelado; Fable não gasta 25% do
> plano reescrevendo Python. A divisão é o produto comendo a si mesmo.

Nada neste arquivo é implementação. É a ordem de fogo do go-live.

**Gate zero (D1): nenhum passo abaixo roda antes de S1 verde.** A promessa
de 2 minutos do hero já quebrou uma vez em HEAD (a spec de smoke ficou fora
do corte público) — a prova de que não quebrou de novo é mecânica:

```bash
bash bin/check-spec.sh specs/oracfit-smoke-normal.md && \
bash bin/check-spec.sh specs/oracfit-smoke-unlock-plan.md && \
bash bin/test-oracfit-tldr.sh && \
bash tests/test-go-live-local.sh
```

## Phase A — Fable fumaça o v1 no ar (fogo, não screenshot)

Fable, em sessão nova, contra a **origem deployada** (não `file://`):

1. Carregar `https://llms.surf/` (ou o host público real). O anel reprova se
   o hero, oracle-loop, stats strip, wipeout cards, swell table, tokens e
   quickstart não estiverem todos alcançáveis.
2. Assertions dos números do stats strip contra o git HEAD deste repo
   (`tests/test-site-honesty.sh` verde naquele commit — inclusive os counts,
   que a seção nova de tokens não inventa; D6).
3. Clicar todo link de nav e as quatro páginas internas. O copy-button copia
   a URL real de clone (`carl0sfelipe/llms.surf`). O link da waitlist abre o
   template `tokens-waitlist.md` (D9).
4. Confirmar que Swell continua lendo **no data yet** — a seção de tokens
   diz "nothing for sale" e não tem preço na tela.
5. CLI local, na ordem da jornada (`docs/go-live/JOURNEY-1H.md`):
   `bin/llms-surf start` com stub, `bin/llms-surf gui`, wizard com o trio de
   surf (paddle/tow/surfcheck), `oracfit modes` listando os 20. Esta é a
   promessa de 2 minutos sendo cumprida na mão.
6. Escrever `docs/v1-smoke-log.md` curto: o que quebrou, o que confundiu,
   onde um estranho cairia. Esse log alimenta a próxima Phase B — não é vibe.

Screenshot de hero não é smoke. Comportamento é.

## Phase B — anéis GLM = só este pack

O pack é `docs/go-live/specs/S1..S6` — nada além dele. Modo: `glm_smart`.
Oráculo congelado no ring open (as linhas `- comando:` de cada spec).
Gauntlet on. Safety ceiling 4.

| story | tema | oráculo (congelar a linha da spec no ring open) |
|---|---|---|
| S1 | promessa de 2 minutos (P0, D1) | check-spec das 2 smokes + oráculo falha pelo motivo certo em workdir limpo |
| S2 | aliases de surf (D2) | `oracfit alias` resolve os 3 e recusa desconhecido; TUI anuncia o trio |
| S3 | ficha da syntax custom (D3/D4) | validate + lint dos 2 YAMLs no loader real |
| S4 | mode share / mode add (D5) | round-trip: add instala em workdir temp, share imprime com cabeçalho do post |
| S5 | god modes fora do default + tokens honestos (D6/D7/D9) | site-honesty verde + seção de tokens na superfície humana e do agente |
| S6 | higiene do corte (D8) | `docs/go-live` declarado nos 2 gates + `check-publico --oficina` limpo |

`tests/test-go-live-local.sh` roda os seis oráculos em sequência — é o mesmo
gate que o time de lançamento usa; um anel GLM que reabre qualquer uma dessas
stories fecha contra o mesmo comando.

Se o GLM não conseguir manter um oráculo verde, abre incidente e para. Não
inventa sétima story.

## O que o Fable continua dono (não vai para GLM)

- Qualquer decisão nova de honestidade ou schema (a lição S26 vale aqui).
- Mudança de licença (D10: `bestmodel.run` fica como está; flip é
  irreversível e não bloqueia este lançamento).
- Inventar preço de token, N de waitlist anunciado, ou qualquer número que
  não venha do tree (D6).
- Tocar produção de terceiro ou rig alugado.

## Pré-condições (não é calendário — na ordem, todas exigidas)

- **(a)** O pack S1–S6 realmente no disco E commitado (veredito lido na
  superfície certa — regra 53: branch revisada tem que ser a branch onde o
  trabalho vive).
- **(b)** `tests/test-go-live-local.sh` verde (gate local, A1).
- **(c)** Host público servindo `/` e `/llms.txt`, com
  `tests/test-site-honesty.sh` verde no commit deployado.
- Dono com caminho GLM/Zhipu que o `glm_smart` realmente consiga chamar
  (`model_ref: zhipuai/glm-5.2-coding-plan`). Adapter escuro = o anel não
  abre — se diz isso, não se finge um dispatch.
- Thread **"share your break" APROVADA pelo dono (2026-08-29)**: uma
  Discussion fixada no lançamento, semeada com os dois YAMLs da ficha
  (`examples/glassy.yaml`, `examples/outside_set.yaml`). Nunca a thread sem
  quem responda.

## Done when

Log da Phase A existe. Os seis oráculos do pack verdes
(`tests/test-go-live-local.sh`) ou incidente aberto para cada vermelho. Site
no ar continua honesto. Nenhum número novo inventado em nenhum dos dois
produtos.
