# spec: unlock-fable-2026-08-31 — 3 travas + revisão de deploy (bestmodel.run)

Você é a camada CARA deste pipeline. Seu orçamento é decisão, não digitação.
A assinatura Claude Code do dono esgotou hoje; você está sendo alcançado via
cheaperinference porque a decisão vale a chamada. Quem escreve arquivo depois
é o gpt-5.6-luna (barato), a partir de specs que EU escrevo lendo você.

## Seu papel, e o que NÃO é

VOCÊ DECIDE. Você não implementa, não escreve código, não refatora, não roda
suíte, não abre PR, não conserta lint. Trabalho de estagiário é do Luna.

Concretamente PROIBIDO nesta chamada:
- Explorar o repositório. O digest abaixo é o contexto completo. Você tem uma
  lista de leitura de 6 arquivos e nada mais — não faça `find`, não faça
  `grep -r`, não leia `node_modules`, não abra `pool.json` (380KB).
- Escrever ou editar qualquer arquivo do produto.
- Rodar build, `npm`, `cargo`, `pytest`, `make gate` ou qualquer coisa que
  custe minutos. Nenhum comando de rede.
- Devolver código pronto. Se a decisão implica código, descreva a FORMA em
  ≤5 linhas e deixe o corpo para o Luna.
- Perguntar de volta. Não existe rodada seguinte nesta chamada.

Dúvida sem resposta possível: escreva `[A DEFINIR PELO DONO]` ou
`ASSUMPTION: <a premissa>` e siga. Nunca trave esperando.

Densidade: ~3 a 8 linhas por item. Prosa longa aqui é desperdício de dinheiro
do dono. Recomendação explícita em todo item — enumeração seca sem "Recomendo:"
é resposta rejeitada.

## Lista de leitura (o único disco que você abre)

Você já está no workdir do bestmodel. Leia só estes, e só se precisar:

1. `.github/workflows/ci.yml` — 35 linhas, o CI inteiro.
2. `cli/benchmark-probe/Cargo.toml` — a dependência travada (trava 1).
3. `apps/web-next/app/page.tsx` — o join servidor que ordena a home (trava 3).
4. `deploy/docker-compose.prod.yml` — a topologia de produção.
5. `deploy/Caddyfile` — 11 linhas, a borda.
6. `apps/web-next/RELATORIO.md` — o que já foi decidido e por quê.

## Dados verificados

Nao invente numero, prazo, custo ou fonte alem dos listados aqui. Tudo abaixo
foi medido no disco ou na rede hoje, 2026-08-31. Você NÃO precisa re-medir nada.

**Produto.** bestmodel.run = catálogo honesto de performance de IA local.
Front Next 15.5.24 (App Router, TS) em `apps/web-next`, deploy Vercel projeto
`bestmodel-next`, branch `main`, root `apps/web-next`, env NEXT_PUBLIC_API_BASE = https://api.bestmodel.run (valor vive no painel
da Vercel, não no repo). Build verde: 646 páginas,
633 delas SSG por `generateStaticParams`. `main` do GitHub = HEAD f7e1c1d hoje (lido por git log, não é literal de arquivo).

**API.** FastAPI, 36 rotas, roda no desktop do dono ("beelink") em docker
compose (`deploy/docker-compose.prod.yml`: api, worker, postgres, redis,
cloudflared). Exposta SÓ por Cloudflare Tunnel — túnel bestmodel-api no painel Cloudflare,
servido pelo container bestmodel-prod-cloudflared-1 (lido por docker ps) — em
`api.bestmodel.run`. `deploy/Caddyfile` só
publica o domínio do api. Sem réplica, sem backup automático verificado, sem
health externo. Postgres e Redis vivem no mesmo host único.

**Estado real dos dados sociais.** 25 claims em produção. TODOS são import do
pool — campos do payload lido por curl na API, não de arquivo: claimant_id
nulo, claimant_handle "localmaxxing pool", source "localmaxxing". ZERO têm `source_url`. ZERO estão `settled_verified`.
ZERO votos. ZERO reports. Nenhum usuário real jamais exercitou o laço
social (votar / denunciar / liquidar com run assinada). O produto social está
no ar e nunca foi usado.

**Escada de honestidade (lei da casa).** measured = n≥3; reported = 1-2;
ausência se declara "no data yet"; nunca estimativa com cara de medida.

**Ids opacos.** `model_release_id` e `quantization_profile_id` são ids do
servidor (`model-qwen3-6-35b-a3b`, `q-gguf-q4-k-m`) e `create_run_claim`
responde 404 para id que não resolve. NÃO existe endpoint de catálogo:
`fetch_quantization_profiles` existe na camada de DB mas não é publicado por
HTTP. Consequência hoje: o form de captura só oferece os ids que o feed já
mostrou (25 modelos, 5 perfis), embora o pool tenha 626 modelos.

**CI.** `.github/workflows/ci.yml`, 2 jobs. `python` = VERDE desde hoje
(faltava Redis em localhost:6380; adicionado service container redis:7-alpine
mapeado 6380:6379; nenhum teste foi tocado). `rust-cli` = VERMELHO.

**Âncoras de nuvem.** 19 runs reais no Modal (L4/A10) + 28 runs numa RTX 3090
(vast.ai, ~US$0.30). whisper-large-v3 4.82×real (L4), sd-turbo 6.09 img/s (L4)
e 5.2 img/s (3090), llama-3.1-8b Q4 44 tok/s (L4) vs 75.8 (A10) — razão 1.7×
que bate com a razão de banda 600/300 GB/s. Rigs de nuvem ficam FORA do top-24
do seletor (corte por runCount ≥35) e aparecem via um índice "anywhere".

**Orçamento.** Modal ~US$13 restantes. Vast suspenso. O dono acabou de estourar
o limite semanal do ZCode. Dinheiro é escasso: proposta que exige gastar precisa
dizer quanto e por quê.

### TRAVA 1 — o CI do Rust não fecha
`cli/benchmark-probe/Cargo.toml:19` declara
`argos-opt = { path = "../../../argos-opt" }`. `~/Work/argos-opt` é repo git
local, commit `31feea6`, **sem remote**, `publish = false`, licença dual
MIT/Apache-2.0 já decidida pelo dono, **nome ainda não final**. O job roda
`cargo test --workspace` e morre com
`failed to read /home/runner/work/bestmodel/argos-opt/Cargo.toml`.
Caminhos possíveis: (a) dar remote ao argos-opt e virar git dependency;
(b) vendorizar dentro do bestmodel; (c) tirar `benchmark-probe` do
`--workspace` no CI e testar só `cli/canirunit`; (d) outro que você veja.

### TRAVA 2 — backup de .env com segredo (item de 1 linha, NÃO gaste orçamento)
`deploy/.env.bak.1788210617` foi criado por mim antes de mexer no CORS e
carrega `TUNNEL_TOKEN`. Já adicionei `deploy/.env.bak*` ao `.gitignore`.
Pergunta: apagar agora, ou política de rotação? Responda em ≤2 linhas.

### TRAVA 3 — a home lidera com n=1
`apps/web-next/app/page.tsx` monta um índice de respostas no servidor e ordena
por velocidade decrescente, cortando em 6. Com o default (Chat + RTX 3090 24GB
+ 4-bit) o número-herói da primeira tela hoje é **666.7 tok/s do
LFM2.5-1.2B-Instruct-GGUF, basis `reported`, n=1**. O basis aparece ao lado,
então é honesto — mas o herói da home é uma única run. Lei do dono conflitante:
"o seletor vem pré-selecionado com default que TEM dado" (não pode ficar vazio)
e "measured > reported". Caminhos: velocidade pura (hoje); measured primeiro e
velocidade dentro de cada basis; ordenação por confiança; outro.

## Tarefa

Escreva UM arquivo, `.dispatch/unlock-fable.md`, seguindo o esqueleto abaixo
sem sair dele. Nada além deste arquivo.

    # UNLOCK — Fable 2026-08-31

    ## D1 — argos-opt / CI do Rust
    Decisão: <a-d ou outra, uma frase>
    Porquê: <≤3 linhas, o trade-off que decidiu>
    Forma p/ o Luna: <≤5 linhas, o que muda e onde — sem código>
    Risco aceito: <1 linha>

    ## D2 — backup de .env
    Decisão: <≤2 linhas>

    ## D3 — ordenação da home
    Decisão: <uma frase>
    Porquê: <≤3 linhas, resolvendo o conflito entre as duas leis>
    Forma p/ o Luna: <≤5 linhas>
    Risco aceito: <1 linha>

    ## D4 — revisão do deploy
    Os 3 riscos que mais ameaçam este deploy, em ordem de gravidade.
    Para cada um: Risco / Evidência (do digest) / Correção / Custo (baixo-médio-alto).
    Não liste mais que 3. Não repita o que já está resolvido.

    ## D5 — funcionalidades novas
    Exatamente 3 propostas, ordenadas por (valor ao produto ÷ esforço).
    Para cada uma: Nome / Problema real que resolve (ancorado num fato do
    digest) / Forma em ≤4 linhas / Por que agora.
    Regra dura: nada que exija dado que o produto não tem. O laço social nunca
    foi usado por ninguém — proposta que assume comunidade ativa é inválida.

    ## D6 — o que eu NÃO faria agora
    ≤5 linhas. O que parece tentador e seria erro, e por quê.

## Regras

Nao invente numero, prazo, custo ou fonte alem dos listados no digest.
NUNCA use declare const como workaround de checagem de tipo — o princípio
vale aqui: não declare como resolvido o que não foi decidido; item sem decisão
recebe `[A DEFINIR PELO DONO]` explícito, nunca uma frase que finge decidir.
Não proponha número de usuários, receita, prazo de mercado ou preço — o
produto tem zero usuários reais e o dono odeia número inventado.

## Oráculo

- comando: python3 -c "import sys,re; t=open('.dispatch/unlock-fable.md',encoding='utf-8').read(); ks=['## D1','## D2','## D3','## D4','## D5','## D6']; miss=[k for k in ks if k not in t]; sys.exit(1) if miss or len(t)<900 else sys.exit(0)"
- exit esperado: 0 = o arquivo existe e traz as seis seções de decisão com
  corpo real. exit 1 antes do run é o estado CORRETO (o artefato ainda não
  existe). O oráculo prova ESTRUTURA de decisão, não qualidade — a qualidade
  quem julga sou eu na leitura.

## Verificação

VERIFICACAO: python3 bin/check-oracle.py docs/go-live/UNLOCK-FABLE-2026-08-31.md "$(mktemp -d)" --quiet

Resultado esperado: "oráculo falha (exit 1) e falha pelo motivo certo", exit 0.

## Barra

A referência é `docs/go-live/ESCALADA-6-FABLE-VALIDACAO-E-COPIA.md`: one-shot,
esqueleto rígido, veredito que volta pronto para ingest sem retrabalho. Passa
na barra a resposta que eu consiga transformar em specs para o Luna sem
precisar te perguntar mais nada.
