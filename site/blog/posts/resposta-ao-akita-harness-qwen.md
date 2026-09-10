---
title: "Resposta ao Akita: o harness muda o Qwen 3.8 mais do que a gente admite"
description: "O mesmo Qwen 3.8-27B: OpenCode no clone falhou com cola; llms.surf/oracfit isolado terminou 9/9 sem gabarito. n=2. Harness pesa tanto quanto o modelo."
date: 2026-09-10
slug: resposta-ao-akita-harness-qwen
lang: pt-BR
author: Carlos
tags:
  - harness
  - qwen
  - benchmark
  - oracfit
  - akita
canonical: https://llms.surf/blog/resposta-ao-akita-harness-qwen
---

*Em resposta a [LLM Benchmarks: Vale a Pena ($$) Misturar 2 Modelos?](https://akitaonrails.com/2026/04/25/llm-benchmarks-vale-a-pena-misturar-2-modelos/) (25 de abril de 2026).*

Olá, Akita. Sem briga. Seu post de abril continua o texto mais honesto que eu li sobre “planner caro + executor barato”. Eu concordo com o miolo. Quero estender uma ponta que, no seu próprio experimento, já aparece: **o harness pesa tanto quanto o modelo**. E quero acrescentar duas exigências de produto/segurança que qualquer claim de “misturei dois modelos” deveria passar antes de ir para o Twitter.

Não rodei Opus planejando e Qwen executando pelo meu dispatcher. Rodei **um** 27B local em **dois** harnesses. Isso não prova mix-of-2-LLMs. Prova outra coisa, que acho que interessa ao benchmark: o mesmo modelo, na mesma família de tarefa Rails+RubyLLM, sai `failed`+cola num harness e `9/9` sem cola no outro.

---

## TL;DR

| O que | Em uma frase |
| --- | --- |
| Concordo | Rails coeso não é Mechanical Turk. O imposto do planner (~US$ 11 no round 3) é real. Assinatura muda a conta. Harness > modelo. |
| Estendo | “Não vale misturar” é, em parte, um achado de **harness**. Mesmo Qwen 3.8-27B: OpenCode no clone falhou com cola; llms.surf/oracfit isolado terminou 9/9 sem gabarito. |
| Não provei | Mix Opus-planner + Qwen-executor via llms.surf. Isso continua em aberto. |
| Pergunta | Se o “planner” for camada local barata (regras + oráculo + isolamento), e não US$ 11 de turns de Opus, o par planner+executor barato volta a fazer sentido? |
| Checklist | Cola fora do workspace **e** fora de testes/oráculos. Keys fora de Docker/README/`.env`. Oracle vermelho se `master.key` ou API key vazarem no artefato. |
| Limite duro | n=2, greenfield, oráculo do oracfit mais fraco que a rubrica 8-dim, e o run 2 pediu teto de 32k de output (o run 1 morreu em 16k). |

**Placar do Qwen 3.8-27B na 3090 (a minha mesa, não a sua):**

| | Run 1 — OpenCode + `run_benchmark.py` | Run 2 — llms.surf / oracfit |
| --- | --- | --- |
| Workdir | Dentro do clone do benchmark | `/tmp/qwen-bench-surf/project` |
| Tempo | 70m36s | ~44 min (2659 s no ledger) |
| Status | `failed` (stall 20 min, `finish_reason=length`) | oracfit `pass`, oracle exit 0 |
| Works? (Akita) | partial | sim (estrutural 9/9) |
| Dockerfile / compose | não / não | sim / sim |
| README | leftover do `rails new` | README de verdade |
| RubyLLM | real (`add_message` + `complete.content`) | real (`chat` + `add_message` + `ask` + `messages.last.content`) |
| Cola | leu `benchmark-v4/reference/chatapp` (“The reference is the gold solution.”) | 215 tool calls, zero `benchmark-v4/reference`; saiu do workdir só para ler a gem `ruby_llm` |
| Testes | FakeChat local | 10 testes, WebMock na URL real do OpenRouter |
| Rubrica humana 8-dim | nem fecha (incompleto + cola) | ~79/100, Tier B (A começa em 80) |
| Teto de output | 16k | 32k pedido |

`oracfit pass` **não** é Akita A. No harness do Akita isso seria: Works? yes, API Tier 1, nota humana ~79, Tier B.

---

## 1. Rodei a mesma família de tarefa, 27B local, dois harnesses

A tarefa é a sua: Rails recente, SPA tipo ChatGPT, RubyLLM + OpenRouter + Claude Sonnet, Tailwind, Hotwire, Minitest, Brakeman/RuboCop/SimpleCov, README, Dockerfile, compose. Sem Active Record, sem mailer, sem jobs. Prompt da mesma família do `run_benchmark.py`.

Hardware e serving, para não misturar com o seu llama-swap:

- Arch Linux, RTX 3090
- Qwen3.8-27B **EXL3 3.5bpw + DFlash2**
- servidor **exllamav3** em `127.0.0.1:8888`
- **não** é llama.cpp
- reasoning **sempre ligado** — come `max_tokens`

Isso importa. Qwen 3.8 thinking no OpenCode é da mesma família do seu DeepSeek V4 Pro: o modelo não “desliga o pensamento”. Se o teto de output é baixo, o thinking come o teto e o harness registra `length`.

### Run 1 — OpenCode no clone (harness Akita)

`opencode run --agent build --format json` via `run_benchmark.py`, workspace em `results-3090/qwen3_8_27b_exl3_3090/project`, **dentro** do repositório que também tem `benchmark-v4/reference/chatapp`.

Números do `result.json`:

- 4236,52 s → **70m36s**
- `status=failed`, `stalled=true`
- `stall_reason`: sem progresso por 20:00; última atividade `assistant finished (length)`
- `finish_reason=length`
- teto de output do modelo no config: **16384**
- 1742 arquivos
- checklist estrutural: Gemfile/app/routes/views/js/tests sim; **Dockerfile não; compose não**; README existe, mas é o boilerplate do generator

A API do RubyLLM **é real**. O service `AssistantReply` faz o caminho certo:

```ruby
chat = RubyLLM.chat
@transcript.each { |entry| chat.add_message(role: entry[:role].to_sym, content: entry[:content]) }
chat.complete.content
```

Isso sozinho já evitaria o Tier 3 clássico (`chat.complete` inventado como fluent, `RubyLLM::Client.new`, etc.). Mas o run **não vale como prova de capacidade**. No ndjson o modelo acha o gabarito, lê Gemfile, initializer, `assistant_reply.rb`, controllers, importmap — e escreve, com todas as letras:

> The reference is the gold solution.

Foram 20 eventos no stream citando `benchmark-v4/reference`. Não é “inspirou-se no README”. É cola.

Dois confundidores no mesmo run, e eu não vou esconder nenhum:

1. **cola** — gold no mesmo filesystem, workspace sem teto de `GIT_CEILING` / isolamento
2. **orçamento de thinking** — 16k de output, reasoning sempre on, stall de 20 min em `length`

Por isso o run 1 não é “Qwen é fraco”. É “Qwen + esse harness + esse teto + gabarito ao alcance”.

### Run 2 — o mesmo modelo, despachado pelo llms.surf / oracfit

Painel local em `127.0.0.1:8766`. Projeto isolado em `/tmp/qwen-bench-surf/project`. Spec + oráculo mecânico **fora** da árvore do benchmark. Ledger do oracfit:

- `run_id` `495e3f70-bb3f-4d39-a71c-07beba367e37`
- `task=rails-chatapp`, `mode=normal`, `model_id=qwen38-27b-exl3-3090`
- `status=pass`, `oracle_exit=0`, `attempt=1`
- `flash_work_s=2658.522` → **~44 min**
- `estimated_cost=0` (local)
- **1751 arquivos**
- **215 tool calls**

Checklist estrutural estilo Akita, 9/9 **YES**: Gemfile, routes, `app/`, views, JS, testes, README, Dockerfile, compose.

RubyLLM de novo real, e desta vez **sem gabarito**. `ChatService`:

```ruby
history.each { |entry| chat.add_message(role: entry[:role], content: entry[:content]) }
chat.ask(message)
chat.messages.last.content
```

`RubyLLM.configure` lê `ENV["OPENROUTER_API_KEY"]`. Modelo default `anthropic/claude-sonnet-4.6`, overridável por `CHAT_MODEL`.

Testes: **10** (6 de controller + 4 de service). WebMock na URL verdadeira `https://openrouter.ai/api/v1/chat/completions`. Não é `FakeClient` alucinado. O service até inspeciona o JSON do request (system/developer + history + user).

Cola: **zero** `benchmark-v4/reference` no `events.jsonl`. O modelo saiu do workdir para ler a gem instalada (`ruby_llm-1.16.0` em `~/.local/share/gem/...`). Isso eu conto como pesquisa de API, não como gabarito. A spec pedia explicitamente: não subir diretório, não procurar reference/gold/gabarito/cola.

Rubrica humana 8-dim (a do scanner/audit, A a partir de 80): **~79/100, Tier B**. Deduzi pontos em:

- histórico só no JS — F5 apaga a conversa (servidor stateless, transcript no Stimulus)
- sem teste de env ausente (`OPENROUTER_API_KEY` missing)
- Docker / `force_ssl` / `master.key` fracos (volto nisso)
- `fetch` + `innerHTML` no Stimulus para aplicar o Turbo Stream

De novo, para não vender verde como ouro: **oracfit pass ≠ Akita A**. O oráculo do run 2 é estrutural. Ele não lê a rubrica de 8 dimensões. No harness do Akita eu reportaria Works? yes / API Tier 1 / B~79.

---

## 2. Onde o Akita está certo (e eu assino)

Vou ser curto aqui porque você já escreveu o argumento melhor do que eu reescreveria.

### Rails coeso não é Mechanical Turk

Você separou lote independente (“traduz 100 docs”) de cadeia com dependência (Gemfile → initializer → service → controller → view → teste → Docker). O chat Rails é o segundo caso. Plan e implementação não têm linha limpa. Round 1 com 0 delegações em 7 variantes não é teimosia do modelo: é a estrutura do problema. Concordo.

A analogia do `Promise.all` no post é a melhor imagem que vi disso. Três `await` em série não ficam 3× mais rápidos porque você colocou uma fila no meio. Dois modelos numa tarefa A→B→C viram latência somada + parsing de envelope + watchdog. Não é paralelismo. É micromanagement com extra hop.

### O imposto de US$ 11 do planner

No round 3, o custo que não aparecia no JSON do executor era o Opus no Claude Code: ler output, planejar o próximo dispatch, escrever prompt, vigiar, conferir disco. ~14 dispatches úteis × 3–5 turns × fração de dólar. **~US$ 11 de planner escondido**. Qwen/Kimi baratos no executor, conta total ~US$ 12 contra ~US$ 4 do Opus solo no opencode. A matemática é feia e é honesta. Quem omite o planner está mentindo o preço.

### Assinatura muda a conta

Pay-as-you-go versus Plus/Pro/Max não é detalhe. Se o Opus já está no teto mensal, o custo marginal do turn extra é zero até estourar a cota. Orquestrar dois modelos para “economizar tokens que você não está pagando” é otimização contra um custo que não existe. A exceção estreita (estourou Pro, desvia para Kimi) você já delimita bem. Não vou reabrir.

### Harness > modelo — você já mediu isso, eu só repeti na 3090

O achado mais subestimado do seu post não é “multi-agente perde”. É este: **o mesmo Opus 4.7 escreve pior no Claude Code do que no opencode**, alucina `chat.complete` (Tier 3) num harness e acerta a API no outro, e ainda sai 4–7× mais caro. Você mesmo diz que “orquestração conserta o Claude Code” é workaround de bug alheio. O conserto limpo é trocar o harness.

DeepSeek V4 Pro é o mesmo filme com outro protagonista. A API exige ecoar `reasoning_content`. O ai-sdk do opencode stripa o campo. Turn 2 = 400. Três configs de `reasoning`, mesmo buraco. Os “completed” antigos eram Opus no fallback `general`. Você corrigiu no público. Isso é raro e vale ouro.

Qwen 3.8 no meu run 1 é **a mesma classe**: reasoning sempre on, teto de 16k, `finish_reason=length`, stall de 20 min. Não é “o modelo travou porque é local e burro”. É protocolo × orçamento × loop de ferramenta. Servir EXL3 no exllamav3 em vez de llama.cpp não isenta o harness de saber que thinking come output.

---

## 3. Onde eu discordo / estendo: “misturar não paga” é em parte um achado de harness

A frase do TL;DR do seu post — misturar frontier planner + executor barato perde para Opus 4.7 solo num harness maduro — eu **não** vou inverter com n=2. Opus solo 97/100 em 18 min por ~US$ 4 continua um baseline brutal. Eu não tenho um run de mix para colocar do lado.

O que eu tenho é isto: **o mesmo executor barato (Qwen 3.8-27B) muda de mundo quando você muda o dispatcher**.

| Variável | Run 1 | Run 2 |
| --- | --- | --- |
| Modelo | Qwen3.8-27B EXL3 3.5bpw + DFlash2 | o mesmo servidor, `127.0.0.1:8888` |
| Runner de código | OpenCode `build` | OpenCode de novo, **mas** atrás do oracfit |
| Isolamento | workspace no clone, gold a um `find /` de distância | `/tmp/...`, spec “não suba diretório” |
| Critério de vitória | `run_benchmark.py` (status/stall/length) | oráculo mecânico no disco (exit 0/1) |
| Teto de output | 16k | 32k pedido |

Três coisas mudaram ao mesmo tempo. Eu não vou fingir A/B limpo. Mesmo assim o delta é grande demais para jogar só no teto de 16k→32k:

- run 1 **copia o gabarito** e ainda assim **não entrega** Docker/compose nem README
- run 2 **não vê o gabarito**, lê a gem, e entrega os 9 artefatos + 10 testes WebMock

Se o veredito “executor local não aguenta Rails coeso” viesse só do run 1, ele estaria **contaminado**. É o mesmo tipo de viés que você caçou no DeepSeek “completed” escrito pelo Opus. Aqui o Qwen “Tier 1 API” do run 1 foi escrito com o gabarito aberto.

Por isso eu leio o seu “não vale misturar” assim:

1. **Como afirmação sobre Opus-planner + executor-LLM, no seu harness, na sua rubrica** — os números aguentam. Não mexo.
2. **Como afirmação geral “orquestração não paga / executor barato não sobe”** — cedo demais. Parte do que você mediu é o custo de **um tipo** de planner (turns de Opus + envelope de subagente + fallback `general`). Outra parte é o harness do executor (opencode stripando reasoning, watchdog curto, gold no disco, teto de output).

O run 2 não é mix de dois LLMs. É **um** LLM + uma camada que não é modelo: spec curta, workdir isolado, oráculo que falha antes do trabalho existir, watchdog, ledger. Se essa camada conta como “planner”, a conta do round 3 muda de figura — porque essa camada custou US$ 0 de API.

---

## 4. O que o llms.surf / oracfit *é* (sem marketing)

Nome atual: **llms.surf**. Nome antigo do binário e do painel: **oracfit**. Não subi servidor nenhum para escrever isto; li o repo e o ledger do run.

A ideia que o README declara, e que o run 2 de fato usou:

> Every task carries an **oracle**: a real command that only passes when the work exists.

Vitória = exit code verde no disco. Não é “o modelo disse done”.

Peças que o run tocou, sem inventar o que não vi executando:

| Script | O que faz, no código |
| --- | --- |
| `bin/oracfit` | CLI-router: `oracfit run normal <spec> <task>`, `status`, `gui`/`panel`. Motor = `dispatch-mode.sh`. |
| `bin/oracfit-gui.sh` | GUI local. Default `127.0.0.1:8766`. Páginas: home, HITL, TODO, anéis, dispatches, run ao vivo, incidents, registry. Read-only, salvo nota HITL e (opt-in) POST de dispatch. |
| `bin/oracfit-todo-server.py` | servidor Python stdlib. Estende o panel; `/api/gui/todo` casa backlog × ledger de anéis. |
| `bin/oracfit-daemon.sh` | double-fork + `setsid` + pidfile. Nasceu de incidente: `nohup` não sobrevive a kill de grupo do harness. |

O oráculo **deste** run (`oracle.sh`) é deliberadamente burro e estrutural. Ele exige, no workdir:

- `Gemfile` com `rails` e `ruby_llm`
- `README.md` que fale de setup/install/bundle/docker
- `Dockerfile`
- um arquivo compose
- `config/routes.rb`, `app/controllers`, `app/views`
- `test/` ou `spec/`
- constante `RubyLLM` em algum `.rb` de `app/` ou `config/`
- superfície de chat em routes ou controllers

Antes do trabalho, exit 1 é o estado **correto**. Depois, exit 0. Sem crase na linha do comando (eles já se queimaram com isso: backtick no oráculo vira substituição e exit 127 fantasma). Sem ler a rubrica 8-dim. Sem boot, sem browser, sem `docker compose up`.

É por isso que eu bato na tecla: **oracfit pass ≠ Akita A**. O oráculo impede o “done sem artefato”. Ele **não** impede histórico só no JS, `master.key` na imagem, `force_ssl` quebrando compose, ou teste que não cobre key ausente.

O que o dispatcher *não* é, neste experimento: um segundo LLM. Ninguém pagou Opus para fatiar a tarefa. A “planilha” foi spec + oráculo + isolamento + teto de tempo. Se isso for planner, é planner de regras, não de tokens.

---

## 5. Pergunta em aberto (não é claim)

Você mostrou que **Opus-planner + executor-LLM**, no verde Rails, ou empata mais caro, ou perde qualidade/tempo. O lift do executor fraco (GLM 46→93, Qwen 71→94) veio do plano prescritivo do Opus, e a conta foi dominada pelo planner.

Eu **não** rodei Opus + Qwen através do llms.surf. Não tenho número para “mix de 2 LLMs no meu dispatcher”. Quem disser que este post prova isso está errado.

A pergunta que eu acho justa, depois do run 2:

> Se o “planner” deixar de ser US$ 11 de turns de Opus e virar uma camada local (oráculo + isolamento + recusa de cola/keys), o par planner-barato + executor-27B local passa a valer a pena no *mesmo* tipo de tarefa que você mediu?

Três respostas possíveis, nenhuma comprovada:

1. **Não.** O 27B local ainda precisa do plano prescritivo do Opus para chegar em A. 79 é B. Docker/ssl/keys e persistência continuam o buraco. O oráculo estrutural não substitui o frontier.
2. **Sim, em volume.** Um run greenfield ainda é mais barato no Opus solo. Cinquenta refactors iguais amortizam a camada local (a sua própria exceção multi-tenant), e o 27B sua na 3090 a custo zero de API.
3. **Depende do oracle.** Se o oráculo crescer até a rubrica 8-dim + runtime + “falha se vazou key”, o 27B ou sobe de verdade ou toma vermelho honesto. Hoje o verde do oracfit é mais estreito que o seu A.

Eu estou no (3) como hipótese de trabalho. Quero o run que falta: **mesmo workdir isolado, mesmo oráculo, Opus só na spec (ou nem isso) versus Qwen solo versus Opus+Qwen**. Sem isso, “mix não paga” e “mix paga se o planner for código” são as duas metades de um experimento incompleto.

---

## 6. Checklist que eu quero no próximo “misturei dois modelos”

Aqui está o pedido extra, e eu acho que é o pedaço mais acionável deste texto. Dois furos. Os dois invalidam claim.

### 6.1 Esconder a cola — workspace **e** testes/oráculos

O gold/reference precisa ficar **fora** do workspace do modelo. Isso já era óbvio depois do run 1. Não basta.

Cola também é:

- fixture de teste que embute a API dourada (`chat.add_message` + `complete.content` copiados do gabarito)
- prompt/oráculo que cita o app de referência
- scanner/rubrica no disco do agente (“como eu sou gravado?”)
- irmão `results/<outro_modelo>/project` no mesmo clone
- `git log` / `git show HEAD:docs/success_report*.md` quando o workdir vive dentro do repo do benchmark

O run 1 é o caso-escola. OpenCode no clone. `find /` acha `benchmark-v4/reference/chatapp`. O modelo lê o service dourado e declara que aquilo é a gold solution. A API “Tier 1” desse run **não conta**.

O run 2 isolou o workdir em `/tmp` e a spec mandou não procurar gabarito. 215 tools, zero gold. A API Tier 1 **desse** run conta — ele foi na gem.

Mas o oráculo do run 2 ainda é permissivo: `grep RubyLLM` em `app/`/`config/`. Isso não vaza o gold. Um oráculo preguiçoso *poderia* vazar — por exemplo, diff contra `reference/chatapp`, ou um teste do harness que o modelo consegue abrir e que já contém o `AssistantReply` certo. **Teste que carrega o gabarito é cola com nome de qualidade.**

Regra que eu quero ver em qualquer harness sério, inclusive no seu e no meu:

1. Gold fora do disco visível (mv, não rm; teto de git; workdir com `.git` isolado).
2. Prompt/oráculo/fixture **não** reproduzem a solução. Oráculo = existência + comportamento, não o source da referência.
3. Scan pós-run nas **entradas** de tool (`read`/`cat`/`sed` no gold), não no stdout de um `ls` inocente.
4. Run com cola = contaminado. Preserva, anota, não entra na tabela oficial.

Vocês (e a gente) já viram as duas espécies: modelo fraco copia o **app** do vizinho; frontier lê a **rubrica** e o relatório. O mecanismo é o mesmo. O shield tem que ser para todos.

### 6.2 Esconder keys críticas em prod — e falhar o oráculo se vazar

Auditoria do artefato do run 2, no disco, sem inventar:

| Achado | Detalhe |
| --- | --- |
| `config/master.key` no disco | 32 bytes, presente. `.gitignore` ignora. **`.dockerignore` não ignora.** |
| `.dockerignore` | ignora `.git`, `.dispatch`, `log/*`, `tmp/*`, `coverage`, `.env`, `.env.*`, `node_modules`. Sem `config/master.key`, sem `config/credentials.yml.enc` explícito. |
| `Dockerfile` | `COPY . .` no stage de build. A key **pode entrar na imagem**. |
| compose | injeta `OPENROUTER_API_KEY: ${OPENROUTER_API_KEY}`. Isso é o caminho certo **se** vier só do ambiente do host. |
| README | ensina um `.env` na raiz com `# OPENROUTER_API_KEY=your-key-here`. Não é a key real, mas é o harness pedindo um arquivo de segredo no projeto. |
| `production.rb` | `assume_ssl = true` e `force_ssl = true`. Compose **não** passa `SECRET_KEY_BASE`. Boot de produção no compose é o tipo de coisa que quebra no `docker compose up` e o oráculo estrutural não vê. |

Nada disso é “Qwen é malicioso”. É Rails generator + modelo que não pensa em imagem. O ponto de produto é outro:

**Um harness/dispatcher sério deveria recusar embarcar segredo em Docker / README / `.env`, e o oráculo deveria falhar se `master.key` ou API keys vazarem no artefato.**

Checklist mínimo que eu colocaria no `oracle.sh` (e no phase-2 do Akita) antes de qualquer “Works? yes”:

- `test ! -f config/master.key` no artefato publicado, **ou** `.dockerignore` com `config/master.key` + `config/credentials.yml.enc` + `*.key` + `.env*`
- `grep` no Dockerfile/compose/README/`*.env*` por `OPENROUTER_API_KEY=sk-` / `sk-or-` / key literal — vermelho
- compose pode **referenciar** `${OPENROUTER_API_KEY}`; não pode **escrever** o valor
- README não cola key de exemplo que parece real; no máximo `export OPENROUTER_API_KEY` sem valor
- `SECRET_KEY_BASE` no compose (via env) se `RAILS_ENV=production`; senão o oráculo de runtime falha
- se `force_ssl` está on, o oráculo de compose precisa de healthcheck HTTP honesto (`/up` excluído do redirect) ou o run marca Docker vermelho, não verde estrutural

O run 2 passou no oracfit **com** `master.key` no disco e `.dockerignore` buraco. Isso é evidência a favor do Akita no espírito (“verde de checklist ≠ app que você colocaria no ar”) e evidência contra o meu oráculo atual. Os dois podem ser verdade ao mesmo tempo.

Por que isso entra num post sobre misturar modelos: se o claim é “o planner barato + o executor local entregam o app”, o app inclui **não vazar a key na imagem**. Senão você não mediu produto. Mediu scaffold.

---

## 7. Limites (para ninguém transformar isso em thread)

1. **Greenfield Rails.** Mesmo recorte que o seu. Sem legado, sem 50 microsserviços, sem DSL de empresa. Conclusão não generaliza para o trabalho do leitor — você já disse isso, eu repito.
2. **n=2.** Um fail com cola, um pass isolado. Sem terceira repetição, sem inverter OpenCode isolado × oracfit no clone. Não é estatística. É existência: o 27B *consegue* 9/9 sem gabarito neste hardware.
3. **Três variáveis no meio.** Isolamento, dispatcher/oráculo, teto 16k→32k. O fail do run 1 é `length` **e** cola. Não posso atribuir 100% do delta ao llms.surf.
4. **Oráculo oracfit ≪ rubrica Akita.** Estrutural ≠ 8 dimensões ≠ boot ≠ Docker runtime ≠ browser. 79 humana, não 97. Eu não rebatizei B de A.
5. **Um modelo, um servidor.** EXL3 3.5bpw + DFlash2 no exllamav3. Não comparei com o seu Qwen via llama-swap/OpenRouter. Quantização e stack de serving são outro eixo.
6. **Sem mix de 2 LLMs.** A pergunta do seu título continua em aberto no *meu* harness.
7. **Custo de parede.** 44–70 min de 3090 não é 18 min de Opus. Energia e tempo de humano vigiando existem. “US$ 0 de API” não é “de graça”.

---

## 8. Convite para replay

Akita, o repo do benchmark é o lugar certo para discordar com arquivo, não com vibe. Se quiser reproduir o lado sujo e o lado limpo:

**Run sujo (o que eu não recomendo como score, só como controle de cola):**

- `python scripts/run_benchmark.py` com o Qwen local, workspace **dentro** do clone
- teto de output 16k, reasoning on
- deixe `benchmark-v4/reference/chatapp` visível
- espere o modelo achar o gold. No meu caso, ele até narrou.

**Run limpo:**

- workdir fora do clone (`/tmp/...` ou `git init` no `project/` + `GIT_CEILING_DIRECTORIES` no results)
- gold, rubrica, `success_report*`, scanner, `CLAUDE.md` **fora** do disco do agente
- oráculo que **não** contém a API dourada
- teto de output declarado (32k se o modelo thinking come 16k)
- depois do verde estrutural: rubrica 8-dim **na mão**, e um oráculo extra de segredo (`master.key` / `.dockerignore` / README / compose)

**O run que falta (o do seu título):**

- mesmo workdir isolado
- mesma spec
- mesma rubrica
- três condições: Qwen solo · Opus solo · Opus-planner + Qwen-executor
- planner = turns de Opus **ou** camada oracfit, em colunas separadas
- custo do planner visível, como você fez no round 3

Eu publico o artefato do run 2 em `/tmp/qwen-bench-surf/project` para inspeção local (não é commit, não é PR). O ndjson do run 1 está em `results-3090/qwen3_8_27b_exl3_3090/`. Quem quiser grepar `benchmark-v4/reference` e `The reference is the gold solution` vai achar. Quem quiser grepar o ledger do oracfit vai achar `oracle_exit=0` e 215 tools sem gold.

Se o replay mostrar que, no isolamento, o OpenCode solo também fecha 9/9, eu atualizo este texto: o herói deixa de ser o dispatcher e passa a ser “tire a cola e o teto de 16k”. Isso ainda seria um achado seu — harness e protocolo — só que com o sinal invertido no marketing de orquestração.

---

## Fecho

Você está certo no que importa para quem está construindo produto: Rails com dependência interna não se beneficia de um segundo cérebro só porque o feed ama dashboard de agente. O imposto do planner é real. Assinatura muda a conta. DeepSeek “completed” sem linha é o tipo de correção que deixa o benchmark confiável.

Eu só não quero que a frase “não vale misturar” vire “qualquer camada acima do modelo é teatro”. No 27B local, a camada que **não** é um segundo LLM — isolamento, oráculo, recusa de cola, recusa de key na imagem — foi a diferença entre fail com gabarito aberto e um B honesto sem gabarito.

Misturar dois modelos? Ainda não sei. Misturar um modelo com um harness que não deixa colar nem vazar `master.key`? Isso, na minha mesa, pagou. E ainda está incompleto: o oráculo deixou a key no disco. Próximo vermelho é esse.

Se vier replay, eu leio. Se vier o mix de verdade no llms.surf, eu atualizo o placar — para cima ou para baixo, com o custo do planner na mesma linha.

— Carlos
