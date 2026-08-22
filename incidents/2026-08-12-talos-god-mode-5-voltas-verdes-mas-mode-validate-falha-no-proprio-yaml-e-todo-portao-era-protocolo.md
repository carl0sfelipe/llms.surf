---
id: 2026-08-12-talos-god-mode-5-voltas-verdes-mas-mode-validate-falha-no-proprio-yaml-e-todo-portao-era-protocolo
titulo: TALOS (god mode v3.5) fechou 5 voltas verdes com oráculo e self-audit quente pegando 1 bug real cada — mas `mode validate` FALHA no próprio yaml (chaves `never`/`halt_conditions` desconhecidas do validador e nunca validadas no run), o checkpoint embute `git add -A` que varreu edição de agente paralelo, e backlog congelado, portão do dono e teto eram todos protocolo
data: 2026-08-12
recorrivel: sim
regra: nao — 9 regras candidatas para a v4 no corpo (6 convergem com ouroboros/pythia/hefesto/aion; 3 são novas)
status: aberto
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou"
interage_com: "2026-08-12-aion-god-mode-1-anel-com-mecanismo-real-mas-perpetuidade-morreu-com-a-sessao"
interage_com: "2026-08-12-talos-mcp-do-browser-morre-no-meio-do-veredito-visual-sem-fallback-declarado"
interage_com: "2026-08-12-talos-edicao-concorrente-na-mesma-arvore-e-checkpoint-com-git-add-a-varre-o-que-nao-e-seu"
---

# TALOS — postmortem do god mode v3.5 (sessão now.services2.0)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo (nome + config/doc) | `talos` — `~/oracfit/core/modes/talos.yaml` + `~/oracfit/docs/modes/talos.md` (commit `9d1f89b`, 21:15:56 -0300). **`bin/oracfit mode validate talos` → FAIL** medido na escrita deste postmortem: `unknown key 'halt_conditions'`, `unknown key 'never'`. O validador nunca rodou durante o run |
| Alvo(s) | `~/now.services2.0` (marketplace multi-país BR/PY, PRD com 47 FRs), branch `main` local — 16 commits à frente do remote ao fim (`git rev-list --count origin/main..HEAD` → 16; god mode nunca pusha) |
| Duração de parede e voltas | Do commit do modo à última volta: 21:15:56 → 22:09:22 = **53min26s**. Só as voltas (CP-0 → volta 5): `fe0adb0` 21:20:51 → `e43d22c` 22:09:22 = **48min31s**. **6 commits = checkpoint 0 + 5 voltas** (`git log --format='%h %ci' fe0adb0~1..e43d22c`) |
| Papéis frontier vs despachados | TODOS os papéis (patrol, build, self-audit, checkpoint) no frontier em contexto QUENTE — a mesma conversa, zero Task subagent, zero critic fresco, zero dispatch a tier free (ordem do dono: "todos os loops feedbacks de refinamento auditoria é feito pelo proprio frontier model"). Único papel mecânico: oracle_gate (script) |
| Oráculos mecânicos | `scripts/talos-oraculo.sh` do repo-alvo agregando 4 estágios falha-fechado (`tsc --noEmit`, eslint com zero erro, `verificar-base`, `oraculo:criar-loja`), rodado em toda volta. Medição pós-run: **150 checks ok (143 do verificar + 7 do criar-loja), exit 0, 9,56s warm** — log preservado em `incidents/evidence/2026-08-12-talos-god-mode/talos-oraculo-run-medido.log` |
| Quem pegou cada bug/rejeição | Oráculo: **1** (1º vermelho da volta 2 — fixture criava anúncio DRAFT e o disparo do alerta só olha ACTIVE; corrigido na fixture, guard mantido; diário linha 64, fix visível no diff de `8c059d1`, 3 ocorrências de `publicarAnuncio`). Self-audit quente: **1** (exclusão de dados do Épico 12 não conhecia `PriceAlert` — e-mail/PII sobreviveria à exclusão do titular; bug PRÉ-EXISTENTE pego por varredura de invariante escrita, não por releitura do diff; diário linha 67, correção em `lib/exclusao-dados.ts` no mesmo `8c059d1`). NINGUÉM no run: o `git add -A` da linha 92 do yaml (varreu edição paralela na volta 3 — satélite), a subcontagem do diário (abaixo) e o FAIL do `mode validate` — todos vistos só neste postmortem |
| Entradas no ledger | `rg -c talos ~/oracfit/ledger/ledger.jsonl` → **0** (sem matches). 4ª ocorrência de god mode com ledger vazio (ouroboros 0, pythia 0, hefesto 0); o aion foi o único ≠ 0, via runner de workdir |
| Granularidade de checkpoint | 1 volta = 1 commit MANTIDA em 6/6 (git log acima). Conteúdo derivou 1×: o commit da volta 3 (`eea292c`) levou junto a reescrita de README feita por agente PARALELO (77 inserções / 114 remoções no README dentro do commit; auditada e atribuída no diário antes de adotar — mas o veículo foi o `add -A`; ver satélite) |
| Falhas de ambiente | MCP do browser caiu no meio da volta 5 e não voltou (satélite próprio; 2ª ocorrência da família no mesmo repo — no épico 24 o browser não alcançava localhost). Disco/rede/auth: nenhum problema observado — e NENHUM checado (zero preflight; `df` nunca rodou no run). Identidade git default em 6/6 commits (`mac mini M4 16 gb <mini@Mac-mini-de-mac.local>`, `git log -1 --format='%an <%ae>'`) — 3ª sessão da classe (pythia sintoma 4, hefesto sintoma 7) |
| Decisões autônomas sem o dono | 4, todas registradas no diário commitado (`docs/diario-talos.md`): (1) override de eslint para prefixo `_` em vez de mutilar assinaturas (volta 1); (2) semântica "alerta notifica UMA vez e se aposenta" do FR-14 (volta 2, comentário em `lib/alerta-preco.ts`); (3) adoção da edição paralela do README com atribuição (volta 3); (4) reinterpretação de "restrição do dono: ZERO design" como escopo de story, não proibição (volta 4, com a fonte citada). Os 6 itens DO-DONO ficaram intactos: preço da loja, credencial Mercado Pago, credencial SMTP, DNS, ativação de plano, push |
| Custo | Tokens: **não medidos** (sem instrumentação de sessão; a conversa misturou trabalho pré-modo, não separável). Tempo medido: 48min31s de voltas. O que desceria de tier: o bulk das voltas 1 (lint) e 3 (docs) — a regra do próprio repo-alvo (CLAUDE.md: >20 linhas → dispatch a modelo free) foi deliberadamente suspensa pela ordem do dono que criou o modo |

## Contexto

Quinto postmortem de god mode do dia (rajada medida pelo incident do hefesto:
9 god modes commitados no oracfit só em 2026-08-12). O `talos` foi desenhado
como terceiro da trinca DEMIURGO (um artefato, oráculo congelado) / PYTHIA
(uma missão) / TALOS (um PRODUTO inteiro): patrulha de backlog com triagem
EXECUTÁVEL|DO-DONO congelada antes da 1ª edição, oráculo determinístico por
volta, self-audit com checklist, checkpoint commitado por volta, teto de 5.

Linha do tempo importa: o talos.yaml nasceu às 21:15:56 lendo os DOCS dos
irmãos (`demiurgo.yaml`, `docs/modes/pythia.md`), ANTES dos postmortems
existirem no repo (ouroboros commitado 21:55:14 em `c6768a3`, pythia 22:33:22
em `52a74b5`). As voltas 3–5 (21:59–22:09) rodaram DEPOIS do postmortem do
ouroboros estar commitado no mesmo repo — e não tomaram conhecimento dele:
sessões paralelas não se leem, e o anti-padrão que aquele incident documenta
(`git add -A` em árvore compartilhada) executou de novo às 21:59:37.

Resultado bruto: **5 voltas verdes em 48min31s** — lint de 1 erro + 10
warnings para 0/0 (baseline registrada em `specs/talos-missao-evolucao.md`,
commit `fe0adb0`); FR-14 de 1/4 para completo com **15 checks novos** no
oráculo (medido: `git show 8c059d1 -- scripts/verificar-base.ts | rg -c
'^\+.*checa\('` → 15); epics.md e README sincronizados; funil da loja com
design; julgamento visual com fallback. Oráculo final: 150 checks verdes
(medição pós-run, log preservado).

## O que funcionou (com evidência e contraprova)

1. **Backlog congelado e commitado ANTES da 1ª edição de código.** Ordem
   provada no git: `fe0adb0` (spec com 5 EXECUTÁVEL + 6 DO-DONO, 21:20:51)
   precede `b8e1a88` (1ª edição, 21:24:32) em 3min41s. O modelo não escolheu
   a tarefa depois de ver o quão fácil era. **Contraprova:** nenhum hash,
   nenhum freeze-check — re-priorizar o backlog no meio do run seria
   invisível; só o diff do spec entre commits denunciaria, e quem audita o
   diff sou eu. Protocolo.
2. **Oráculo agregado falha-fechado pegou o único bug do código novo** (1º
   vermelho da volta 2: fixture sem publicar × guard de ACTIVE que impede
   alerta vazar anúncio não publicado). Corrigido na fixture, guard mantido.
   **Contraprova:** o guard era desenho MEU e o script é MEU e móvel — eu o
   criei no CP-0 e o ampliei na volta 2 (+15 checks). Afrouxar o guard em
   vez de corrigir a fixture passaria verde igual; nada distingue apertar de
   afrouxar (sintoma 5 do ouroboros, sem o sha256 do demiurgo).
3. **Self-audit quente pegou 1 bug real — mas note ONDE:** PII de
   `PriceAlert` fora da exclusão de dados do Épico 12, um gap PRÉ-EXISTENTE
   em código de terceiros, achado por varredura de invariante ESCRITA do
   repo (LGPD/Épico 12), não por releitura do próprio diff. Correção +
   2 checks no mesmo `8c059d1`. **Contraprova:** sobre o próprio diff
   fresco a self-audit achou 0 — e o `add -A` do meu próprio checkpoint
   ficou invisível pelas 5 voltas. Combinado com pythia (quente pegou 0),
   hefesto (quente pegou 0 em código) e aion (quente pegou 0), o placar de
   autoauditoria quente sobre o próprio diff nas 4 sessões é **0**; o único
   ponto dela veio de invariante escrita sobre código alheio.
4. **Portão do dono segurou: zero número inventado.** 6 itens DO-DONO
   intactos ao fim (diário, "Estado final"); o transporte de e-mail se
   declara dev no código (`lib/email.ts`: "TRANSPORTE DE DESENVOLVIMENTO
   APENAS"); preço da loja segue mock declarado. **Contraprova:** o portão é
   100% prompt. Se eu tivesse chutado um preço, nenhum gate acenderia — o
   oráculo testa comportamento, não "decisão de negócio não tomada".
5. **O produto mordeu de volta onde tinha mecanismo:** no teste real via
   curl (volta 5), o login de usuário NOVO falhou com `error=Configuration`
   porque o `createUser` custom do FR-1 recusa criar usuário sem
   consentimento (diário linhas 135-141). Mecanismo do PRODUTO, não do modo
   — mas é o padrão a copiar: a regra falha fechado sem depender de
   disciplina de ninguém.
6. **Granularidade 1 volta = 1 commit em 6/6** — sem a fusão de ciclos do
   pythia. **Contraprova:** contada por mim mesmo; ledger 0 (abaixo).

## Contraste com os god modes irmãos

Linhas apenas do que observei (talos) ou li de incident commitado
(ouroboros, pythia, hefesto, aion — todos em `incidents/`). Demiurgo e
content_factory: só via tabela do incident do ouroboros, não re-audito aqui.

| Dimensão | ouroboros | pythia | hefesto | aion | **talos** |
|---|---|---|---|---|---|
| Critic | fresco (subagent+profile) | quente | fresco (1/story) | fresco com nota-do-dono | **quente, zero subagent** |
| Quem pegou os bugs | critic fresco (3 rejeições) | oráculos (2); quente 0 | critic fresco (2 blockers) | critic fresco (4/4) | **oráculo (1) + quente sobre invariante escrita (1); quente sobre o próprio diff: 0** |
| Seleção de tarefa | executor por anel | spec pré-escrita | 22 stories BMAD congeladas | backlog próprio por leverage | **backlog congelado e COMMITADO antes da 1ª edição, com classe DO-DONO** |
| Ledger | 0 | 0 | 0 | 2 entradas (runner workdir) | **0 (4ª ocorrência)** |
| Teto | prometido | prometido | prometido | contado no ledger | **prometido (contado por mim)** |
| Commit | executor, add -A varreu árvore | executor, ciclos fundidos | script com add -A no yaml | script com pathspec | **executor com add -A no yaml; varreu edição paralela (auditada por sorte)** |
| Validação do yaml | — | — | `mode validate` OK (aceitou add -A) | — | **`mode validate` FAIL (chaves desconhecidas) e nunca rodado no run** |
| Falha de ambiente | sessão matou cadeia+vigia | ENOSPC | nenhuma (nenhuma checada) | despertador morto aos 102s | **MCP do browser morto no meio da volta 5 (satélite)** |

## O que quebrou / ficou frágil

1. **`mode validate talos` FALHA — e nunca rodou durante o run.** Medido na
   escrita deste postmortem: `FAIL ... unknown key 'halt_conditions'`,
   `unknown key 'never'`. As chaves onde vivem exatamente as proteções que o
   cabeçalho do yaml chama de "ESTRUTURAIS" — "nunca pushar sem revisão",
   "nunca inventar preço", condições de parada — são DESCONHECIDAS do
   validador: prosa que nenhum runner jamais leria. E o erro ficou invisível
   porque rodar o validador também era protocolo (o hefesto rodou o dele e
   passou; eu nem rodei o meu). Classe: mecanismo ausente, em dois níveis.
2. **Ledger vazio — 4ª ocorrência independente.** `rg -c talos
   ledger/ledger.jsonl` → 0. `safety_ceiling: 5`, `run_attempt_budget: 12`
   e o gauntlet do yaml não contaram nada em lugar nenhum; o teto foi
   respeitado porque eu contei minhas próprias voltas. Classe: mecanismo
   ausente (idêntico a ouroboros/pythia/hefesto; o aion provou que o runner
   de workdir resolve por ~261 linhas de bash).
3. **`git add -A` codificado no yaml (linha 92) e com dano real.** 2ª
   codificação do anti-padrão em yaml de god mode no MESMO dia (hefesto,
   linha 86 — lá sem dano por ser árvore de agente único). Aqui a árvore era
   compartilhada e a volta 3 varreu a reescrita de README de um agente
   paralelo para dentro do meu commit (`eea292c`, 77+/114− no README). Só
   não foi silencioso porque o paralelo tocou o MESMO arquivo que eu estava
   editando e meus edits falharam — detecção por acidente, não por detector.
   Incident satélite próprio. Classe: mecanismo ERRADO especificado.
4. **Contabilidade manuscrita imprecisa — mesmo sem corromper.** O diário
   registra "12 casos novos de FR-14 + 2 de exclusão" onde o diff medido dá
   15 (`rg -c '^\+.*checa\('` em `8c059d1`), e "verificar 130+ casos" onde a
   medição dá 143. Ninguém pegou no run; só o postmortem mediu. É a forma
   branda do sintoma 1 do hefesto (lá o CHECKPOINTS.md duplicou um bloco
   inteiro por 3 anéis). Classe: mecanismo ausente (claims-check).
5. **Julgamento visual sem gate e sem caminho degradado declarado.** A volta
   5 inteira foi "de olho" + contagem de composição no HTML via curl — sem
   verdict falha-fechado, e com a ferramenta morrendo no meio (satélite).
   Se eu declarasse "visto e aprovado" sem evidência, nada reclamaria — a
   classe do incident do vision-gate decorativo. Classe: protocolo.
6. **Preflight zero.** Identidade git default em 6/6 commits (3ª sessão da
   classe), disco nunca checado, disponibilidade de ferramenta do plano
   (browser) nunca checada. Classe: mecanismo ausente (pythia regra 3).

## Causa raiz

A mesma dos irmãos, agora em 4ª confirmação independente: **host-mode é
invisível aos mecanismos da v3.5 — tudo que o yaml declara vira prosa, e
proteção vira disciplina do próprio modelo protegido.** A nuance própria do
TALOS é o grau zero disso: o modo foi desenhado CITANDO as proteções dos
irmãos como "estruturais, herdadas do DEMIURGO" no cabeçalho do yaml, e
nenhuma delas nasceu executável — nem sintaticamente conhecida do validador
(`never`, `halt_conditions` = unknown keys). E o conhecimento já commitado
não alcançou o run: o postmortem do ouroboros documentando o `add -A` em
árvore compartilhada existia no repo 4 minutos ANTES da volta 3 repetir o
anti-padrão. Incidents não se propagam por osmose; só mecanismo no caminho
do próximo run propaga.

## Regras candidatas para a v4

CONVERGENTES (reforçam regra já proposta por incident irmão):

1. **`bin/oracfit ring open|close` com ledger obrigatório** (= regra 1 de
   ouroboros, pythia, hefesto e aion — 5ª sessão a precisar). Evidência
   nova: teto de 5 contado de cabeça pelo executor e granularidade auditada
   só por ele. Custo: já orçado; o piloto do aion existe.
2. **Lint mecânico da definição de modo, obrigatório no registro** (= regra
   4 do hefesto + regra 4 do aion, com evidência mais dura): o validador
   deve FALHAR `git add -A`/`-u` em stage command (2ª codificação em um
   dia), e chave desconhecida de god mode deve BLOQUEAR o registro do modo —
   hoje o FAIL existe mas rodar o validate é opcional (aqui: nunca rodou).
   Forma: `ring open` chama `mode validate` e não abre com FAIL. Custo:
   1 regex + 1 chamada no open.
3. **Critic fresco obrigatório para o próprio diff** (= regra 4 do pythia,
   regra 2 do hefesto, regra 2 do aion). Evidência nova: 4ª sessão em que a
   auditoria quente sobre o próprio diff pega 0.
4. **Preflight no `ring open`** (= regra 3 do pythia): identidade git
   resolvida (3ª sessão com autoria default), disco, e — novo vetor daqui —
   disponibilidade das ferramentas que o plano da volta declara (satélite
   do MCP).
5. **Isolamento de árvore por agente / pathspec obrigatório** (= regra 5 do
   ouroboros, regra 4 do hefesto): 2ª varredura REAL de arquivos alheios por
   `add -A` em god mode; forma endurecida no incident satélite (pathspec
   positivo derivado do plano da volta).
6. **Claims-check do checkpoint** (= regra 6 do ouroboros, regra 7 do
   hefesto): números citados no diário divergiram do diff medido (12 vs 15;
   130+ vs 143) sem ninguém notar. Recontagem mecânica no close.

NOVAS (evidência só desta sessão):

7. **Freeze mecânico do backlog da patrulha.** O que o demiurgo faz com o
   oráculo (sha256 + freeze_check), o modo de patrulha precisa fazer com a
   TRIAGEM: `ring open` da volta 0 grava hash do backlog congelado;
   alteração posterior de ordem/classificação só com bloco `DECLARACAO:` no
   checkpoint da volta. Sintoma coberto: a proteção 1 do talos.yaml
   ("backlog escrito antes da 1ª volta") funcionou por protocolo e seria
   violável em silêncio. Custo: 1 sha256 + 1 check (~10 linhas).
8. **Scan DO-DONO no diff do `ring close`.** A spec da missão já lista as
   pendências DO-DONO (credencial, preço, DNS…); um scanner procura no diff
   da volta padrões da classe (chave/credencial, URL de domínio novo, valor
   monetário hardcoded novo) e FALHA o close se algo da lista aparecer sem
   bloco de decisão do dono. Limite declarado: credencial e URL são
   mecanizáveis; "preço chutado" só por heurística de literal monetário.
   Sintoma coberto: portão do dono 100% prompt (quebra 4 do "o que
   funcionou"). Custo: script de padrões por repo (~30 linhas).
9. **Split contratual da autoauditoria por alvo.** Refina a regra
   convergente 3 em vez de contradizê-la: o plano da volta declara DOIS
   alvos de auditoria — (a) o próprio diff → critic FRESCO obrigatório;
   (b) invariantes escritas do repo (custo, LGPD, i18n…) → sweep QUENTE
   permitido, listado invariante a invariante. Evidência: o único ponto da
   auditoria quente em 4 sessões veio exatamente do alvo (b) — o bug de PII
   do Épico 12, pego por varredura de invariante escrita sobre código
   pré-existente. `ring close` exige os dois relatórios. Custo: 1 subagent
   por volta + seção no template do plano.

## Evidência preservada

- Modo: `~/oracfit/core/modes/talos.yaml` (commit `9d1f89b`; `git add -A`
  na linha 92), `docs/modes/talos.md`. Validação medida:
  `cd ~/oracfit && bin/oracfit mode validate talos` → FAIL nas 2 chaves.
- Run: `~/now.services2.0` commits `fe0adb0` → `e43d22c` (timestamps via
  `git log --format='%h %ci' fe0adb0~1..e43d22c`); spec/backlog congelado em
  `specs/talos-missao-evolucao.md` (`fe0adb0`); diário por volta em
  `docs/diario-talos.md`.
- Oráculo: `scripts/talos-oraculo.sh` (`fe0adb0`); run medido pós-sessão
  (150 ok, 9,56s, exit 0) em
  `incidents/evidence/2026-08-12-talos-god-mode/talos-oraculo-run-medido.log`.
- Bugs e quem pegou: diff de `8c059d1` (fixture `publicarAnuncio` ×3;
  `lib/exclusao-dados.ts`; +15 `checa(`); diário linhas 64-72.
- Varredura da edição paralela: `git show eea292c --stat` (README 77+/114−);
  diário linhas 82-92; incident satélite.
- Ledger: `rg -c talos ~/oracfit/ledger/ledger.jsonl` → sem matches.
- Identidade git: `git log -1 --format='%an <%ae>'` no repo-alvo →
  `mac mini M4 16 gb <mini@Mac-mini-de-mac.local>`.
- Commits à frente: `git rev-list --count origin/main..HEAD` → 16.

## O que este incident PROVA pra v4

1. 4ª confirmação independente de que yaml de god mode sem runner é prosa —
   agora com prova sintática: as proteções centrais moravam em chaves que o
   validador declara DESCONHECIDAS, e ninguém viu porque validar também era
   opcional.
2. Postmortem commitado não é mecanismo de propagação: o anti-padrão do
   `add -A` re-executou 4 minutos depois do incident que o documenta entrar
   no mesmo repo. Só validação mecânica no caminho do próximo registro/run
   (regra 2) alcança o modo seguinte da rajada.
3. Autoauditoria quente tem um nicho real e barato — invariantes escritas ×
   código pré-existente (1 bug de PII aqui) — mas o placar dela sobre o
   próprio diff nas 4 sessões combinadas é 0. O split por alvo (regra 9)
   captura o que ela vale sem fingir que substitui critic fresco.

## Pode acontecer de novo?

Sim, imediatamente: o `talos.yaml` continua no repo com o validate em FAIL e
o `add -A` na linha 92 (esta entrega é só incidents; corrigir o modo é
tarefa própria), e qualquer modo novo da próxima rajada nasce igual enquanto
`mode validate` for opcional e não souber recusar god mode com chave
desconhecida ou `add -A` em stage. A recorrência é a regra, não a exceção:
foram 9 god modes commitados em um único dia.
