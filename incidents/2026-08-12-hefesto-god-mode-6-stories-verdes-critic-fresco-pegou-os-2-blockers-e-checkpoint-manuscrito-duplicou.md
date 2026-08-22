---
id: 2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou
titulo: HEFESTO (god mode v3.5, fábrica BMAD) fechou 6 stories/8 commits/56 testes em 69min52s de anéis — os únicos 2 blockers da sessão foram pegos pelo critic FRESCO com oráculo 100% verde, e a contabilidade manuscrita duplicou um checkpoint inteiro que sobreviveu 3 anéis sem nenhum detector
data: 2026-08-12
recorrivel: sim
regra: nao — 7 regras candidatas para a v4 no corpo (4 convergem com ouroboros/pythia; 3 são novas)
status: aberto
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-hefesto-prova-rfs-por-git-checkout-apagou-trabalho-nao-commitado-no-meio-do-anel"
interage_com: "2026-08-12-colisao-de-id-hefesto-dois-god-modes-distintos-com-o-mesmo-nome-a-4min-de-distancia"
---

# HEFESTO — postmortem do god mode v3.5 (sessão poker-freeroll-radar)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo | `hefesto` — **`~/poker-freeroll-radar/core/modes/hefesto.yaml`** (workdir overlay, commit `bc8e1fb` do projeto). ATENÇÃO: NÃO é o `~/oracfit/core/modes/hefesto.yaml` (`ac4398c`) — são dois modos DIFERENTES com o mesmo id; ver incident satélite da colisão |
| Alvo | `~/poker-freeroll-radar` (radar de freerolls: FastAPI + Next.js), branch `hefesto`, projeto com cadeia BMAD completa (22 stories com critérios de aceite e detector R-FS escritos ANTES da forja) |
| Duração e anéis | Anéis CP-0→wrap: 21:18:38→22:28:30 -0300 = **69min52s** (timestamps de `bc8e1fb` e `32db19a`). Fase pré-CP-0 (criação do modo, validação) sem âncora de commit = não medida. **7 checkpoints (CP-0..CP-6) + 1 commit de wrap = 8 commits** |
| Papéis | plan, forja, refino, auditoria, checkpoint = frontier host em contexto QUENTE (mesma conversa). Critic = frontier em contexto FRESCO (Task subagent `cavecrew-reviewer`, 1 por story, 6 rodadas). Export = git via shell. **Zero dispatch a modelo free** (por desenho, yaml linha 11) |
| Oráculos mecânicos | `pytest -q` + `ruff check app/` por anel (stage_oracle, yaml linhas 68-69); suíte cresceu 7→13→24→30→43→**56 testes** (contagens por CP em CHECKPOINTS.md; 56 medido no terminal desta sessão). + prova R-FS de sabotagem por story: **7 provas vistas vermelhas** (6 stories + 1 do detector novo no refino do CP-6) |
| Quem pegou cada bug | Oráculo: 28 erros ruff + 1 falso positivo do guard de datetime (CP-1). Critic fresco: **os únicos 2 blockers da sessão** (CP-6) + 22 menores (3+5+1+5+4+4, somados de CHECKPOINTS.md CP-1..CP-6). Autoauditoria quente: 0 bugs de código; pegou a duplicação do CP-2 POR ACASO, 3 anéis depois, ao reler o arquivo para escrever o CP-6. Ninguém mecânico: a duplicação (nenhum check a teria pego) |
| Ledger | `rg -c hefesto ~/oracfit/ledger/ledger.jsonl` → **0 entradas** (exit 1). 3ª ocorrência independente do achado ouroboros/pythia |
| Granularidade | 1 story = 1 commit MANTIDA nos 6 anéis (git log `main..hefesto`). Derivou no conteúdo: o commit do CP-6 (`4c58fcf`) levou junto a limpeza da duplicação (numstat: CHECKPOINTS.md 37+/21−, backlog 2+/2−) — story misturada com correção de contabilidade. O export do yaml codifica `git add -A` (linha 86) |
| Falhas de ambiente | Nenhuma observada — e nenhuma checada (zero preflight; `df` nunca rodou durante o run). Identidade git default em TODOS os 8 commits (`mini@Mac-mini-de-mac.local`, warning do git em cada commit) — mesma classe do sintoma 4 do pythia |
| Decisões autônomas | (1) branch `hefesto` criada; (2) fase do `bmad.config.yaml` → implementation; (3) EPIC-01-S03 desviada para o fallback que a própria story previa (spike: Lobbyze sem endpoint de refresh → detector + runbook, CP-3); (4) parada no fim do sprint 1 com bloco "ESTADO ATUAL" listando 5 decisões devolvidas ao dono; (5) desenho LGPD (sha256+salt) com a limitação — pseudonimização, não anonimização — declarada ao dono no CP-6. Todas registradas em CHECKPOINTS.md/backlog commitados |
| Custo | Tokens NÃO medidos (sem contador disponível na sessão). Frontier em todas as pontas por desenho. A skill `orquestrar` da máquina manda despachar bulk >20 linhas para tier free — deliberadamente não seguida pelo desenho do modo; quanto do bulk (código+testes das 6 stories) seria despachável não foi medido |

## Contexto

Quarto teste god mode da v3.5 (ouroboros e pythia rodaram no mesmo dia, em
sessões independentes). O `hefesto` (fábrica BMAD) promete: frontier executa
o loop create-story→dev-story→code-review sozinho, story a story, com oráculo
mecânico soberano + critérios de aceite congelados ANTES da forja + regras
R-FS (todo detector com prova de que fica vermelho) e R-BACKLOG (achado não
corrigido vira linha commitada) como parte do oráculo — e um commit por story
na branch `hefesto`, nunca push. Diferença estrutural para os irmãos: o alvo
tinha spec-pack completo pré-escrito (22 stories BMAD com critérios de
aceite), então o executor nunca decidiu O QUE fazer, só COMO.

Resultado bruto: **6 stories fechadas (EPIC-01 4/4 + EPIC-02 core 2/2) em
69min52s de anéis, 8 commits, suíte de 0→56 testes verdes, ruff limpo**
(git log `main..hefesto`; terminal desta sessão).

## O que funcionou (com evidência e contraprova)

1. **Critic fresco pegou os 2 únicos blockers da sessão — com oráculo 100%
   verde no momento da revisão.** No CP-6 o oráculo estava 54/54 verde
   (terminal) quando o subagent critic apontou: `link.id` acessado DEPOIS de
   commit/rollback → `expire_on_commit` do SQLAlchemy dispara um SELECT de
   refresh que explode exatamente quando o banco está fora — o 500 apareceria
   no único cenário em que a garantia "clique perdido nunca bloqueia o
   redirect" importa. Dois pontos do código, mesma causa raiz
   (`app/services/tracking.py` e `app/api/v1/endpoints/affiliates.py`;
   correção no diff de `4c58fcf`). O teste existente de falha de insert
   passava porque o construtor explodia ANTES do commit — o critic apontou
   isso também, e o refino criou um detector novo (falha de COMMIT real +
   contagem de SQL pós-rollback) visto vermelho contra a regressão antes de
   fechar (terminal desta sessão: FAILED com o `link.id` reintroduzido, verde
   com a correção). **Contraprova:** o critic rodou porque o executor o
   lançou — é protocolo. Se o executor pulasse a rodada do CP-6, os 2
   blockers iam para o commit com pytest e ruff verdes; nenhum mecanismo
   teria reclamado.
2. **Prova R-FS de sabotagem por story separou "funciona" de "detecta".** 7
   provas vistas vermelhas, uma por anel (CHECKPOINTS.md CP-1..CP-6). A mais
   ilustrativa (CP-6, terminal desta sessão): com o insert de clique
   desligado por edição pontual, o teste de redirect CONTINUOU verde (302) e
   o teste de contagem falhou (0 ≠ 50) — a distinção exata que a story
   exigia. **Contraprova:** a prova é disciplina, nada a obriga; e a 1ª
   tentativa dela (CP-1) DESTRUIU trabalho não commitado — ver incident
   satélite do git checkout.
3. **Trave do oráculo pinada no repo neutralizou ambiente.** `ruff.toml` e
   `pytest.ini` criados no CP-1 para a config global da máquina não
   contaminar o veredito (CHECKPOINTS.md CP-1). **Contraprova:** o executor
   pode editar essas traves livremente — nenhum freeze tipo demiurgo
   (sha256); afrouxar seria invisível, o mesmo sintoma 5 do ouroboros.
4. **Decisão autônoma registrada destravou o anel bloqueado.** A EPIC-01-S03
   dependia de um endpoint de refresh que o spike provou não existir; em vez
   de travar ou inventar contrato, o anel seguiu o fallback previsto na
   própria story (detector de auth + runbook de rotação manual) e devolveu ao
   dono a captura do contrato real (CHECKPOINTS.md CP-3). Mesmo padrão
   saudável do item 5 do pythia.

## Contraste com os god modes irmãos

Só linhas de modos que observei diretamente ou via incident commitado
(ouroboros e pythia lidos de `incidents/`; demiurgo e content_factory só
conheço pela tabela do incident do ouroboros — não repito aqui o que não
auditei; aion nunca observado).

| Dimensão | ouroboros | pythia | hefesto (esta sessão) |
|---|---|---|---|
| Critic | Fresco (subagent + profile) | Autoauditoria no MESMO contexto | Fresco (subagent `cavecrew-reviewer`, 1/story) |
| Quem pegou os bugs graves | Critic fresco (3 rejeições empíricas) | Oráculos (2 bugs); autoauditoria 0 | Critic fresco (2 blockers com oráculo verde); oráculo pegou só lint/nível-de-teste |
| Spec de trabalho | Escrita pelo próprio executor por anel | Spec pré-escrita (pythia-vagai-loop) | 22 stories BMAD com critérios de aceite congelados ANTES |
| Detector extra | claims-check manual do critic | Validador mecânico de veredito (código) | Prova R-FS de sabotagem por story (7 vistas vermelhas) |
| Ledger | 0 entradas | 0 entradas | 0 entradas (3ª ocorrência) |
| Checkpoint | Manuscrito | Manuscrito (granularidade derivou: C0+C1 num commit) | Manuscrito — e CORROMPEU de verdade (CP-2 duplicado, 3 anéis sem detecção) |
| Falha de ambiente | Sessão de terminais matou cadeia+vigia | ENOSPC no meio do anel | Nenhuma observada (nenhuma checada) |
| Identidade git | — (não reportado) | Default errada em todos os commits | Default errada em 8/8 commits |

## O que quebrou / ficou frágil

1. **A contabilidade manuscrita corrompeu DE VERDADE — primeiro caso
   observado da hipótese do ouroboros.** O bloco `## CP-2` do CHECKPOINTS.md
   nasceu DUPLICADO no próprio commit do CP-2 (`404a641`:
   `git show 404a641:CHECKPOINTS.md | rg -c '^## CP-2'` → 2) e o backlog
   duplicou 2 linhas do mesmo achado (guard regex: contagem 2 no mesmo
   commit). Sobreviveram aos anéis CP-3, CP-4 e CP-5 (contagem 2 em
   `2f6ac37`, `98c2a71`, `aa56c67`) até a remoção no CP-6 (`4c58fcf`,
   contagem 1) — descoberta por ACASO, ao reler o arquivo para escrever o
   checkpoint seguinte. Classe: **mecanismo ausente** (nenhuma verificação de
   unicidade de id de checkpoint; o único leitor do arquivo é o próprio
   escritor). O ouroboros apontou "CHECKPOINTS.md manuscrito =
   autofiscalização" como risco; aqui está a materialização.
2. **Ledger vazio — 3ª ocorrência independente.** `rg -c hefesto
   ledger/ledger.jsonl` → 0. `safety_ceiling: 4` e `run_attempt_budget: 12`
   do yaml não contaram nada em lugar nenhum. Classe: mecanismo ausente
   (host-mode invisível ao `bin/oracfit`), idêntico a ouroboros/pythia.
3. **O critic — o único detector que pegou blockers — é 100% protocolo.** O
   stage `vision_gate` do yaml não dispara nada (`frontier-host` não é
   dispatchável; o próprio yaml declara nas linhas 41-43 que os stages são
   protocolo). As 6 rodadas aconteceram por disciplina do executor. Classe:
   protocolo que segurou por disciplina — e que carregou sozinho os 2 únicos
   achados graves da sessão.
4. **`git add -A` codificado NO yaml do modo (linha 86 do export).** O
   padrão que varreu arquivos de outro agente no ouroboros (commit `af029f7`
   de lá) está aqui promovido a spec. Sem dano nesta sessão (árvore de
   agente único), mas o efeito colateral apareceu: o commit do CP-6 levou a
   correção da contabilidade junto com a story (numstat de `4c58fcf`).
   Classe: mecanismo ERRADO especificado — o validador de modos aceitou sem
   reclamar (`mode validate` OK no terminal).
5. **Prova R-FS destrutiva apagou trabalho não commitado no CP-1** — ver
   incident satélite (classe: protocolo sem guarda; a correção "sabotagem
   por edição pontual, nunca checkout" é ela mesma protocolo).
6. **Colisão de id `hefesto` com outro god mode nascido 3min42s antes** —
   ver incident satélite (classe: mecanismo ausente no registro de modos).
7. **Identidade git default em 8/8 commits** (`mini@Mac-mini-de-mac.local`,
   warning impresso pelo git em cada commit do terminal). Convergente com o
   sintoma 4 do pythia; classe: preflight ausente.

## Causa raiz

A mesma do ouroboros e do pythia, confirmada em 3ª sessão independente:
**host-mode é invisível aos mecanismos da v3.5 — tudo que o yaml declara
como stage, gate, teto ou export vira prosa; só o que já era executável por
conta própria (pytest, ruff, git) funcionou como mecanismo.** A nuance
própria do hefesto: o modo confiou a CONTABILIDADE ao mesmo contexto quente
que forja (CHECKPOINTS.md manuscrito), e a única corrupção de dados da
sessão aconteceu exatamente ali — no único artefato que o dono usa para
auditar sem abrir o chat.

## Regras candidatas para a v4

Convergentes (reforço com evidência nova, não repetição):

1. **`bin/oracfit ring open|close`** (= regra 1 do ouroboros, regra 1 do
   pythia — 3ª sessão a precisar). Evidência nova: um `ring close` que
   valide unicidade de id de checkpoint teria pego a duplicação NO ANEL em
   que nasceu, não 3 anéis depois. Custo: já orçado pelos irmãos.
2. **Critic fresco obrigatório para anel de código** (= regra 4 do pythia).
   Evidência nova e mais forte: aqui o critic fresco pegou 2 blockers com
   oráculo 100% verde — nas 3 sessões do dia, é a ÚNICA classe de detector
   que pegou defeito semântico de código. Custo: 1 subagent por anel
   (~6 nesta sessão).
3. **Preflight no `ring open`** (= regra 3 do pythia): identidade git
   resolvida teria evitado 8/8 commits com autoria default nesta sessão.
4. **Proibir `git add -A` em export de god mode** (= regra 5 do ouroboros,
   promovida a lint): o validador de modos deveria FALHAR yaml de god mode
   com `add -A`/`add -u` no export — a v3.5 validou o hefesto com isso
   dentro sem reclamar. Custo: 1 regex no `mode validate`.

Novas (evidência só desta sessão):

5. **Unicidade de id no registro de modos + aviso de sombreamento**: `mode
   validate` e `modes` avisam quando o workdir overlay SOMBREIA um id
   existente no core (aqui `hefesto` ≠ `hefesto`; a resolução muda com o
   `$PWD` — medido: OK no workdir, FAIL na raiz). Cobre o satélite da
   colisão. Custo: 1 stat + comparação de hash no validate.
6. **Prova R-FS como primitiva não-destrutiva** (`oracfit sabotage
   <alvo> --patch`): aplica a sabotagem via patch reversível, roda o teste
   apontado, reverte — nunca `checkout`/`reset`. Cobre o satélite do
   checkout; mantém o que a prova tem de melhor (7 provas vermelhas nesta
   sessão) tirando o risco. Custo: script de ~30 linhas.
7. **Claims-check do arquivo de checkpoint no fechamento do anel**: ids de
   CP únicos + contagem de testes citada no texto == contagem do último run
   do oráculo (especialização barata da regra 6 do ouroboros para o único
   artefato que o dono lê). Cobre o sintoma 1. Custo: script de ~20 linhas.

## Evidência preservada

- Modo (fábrica BMAD): `~/poker-freeroll-radar/core/modes/hefesto.yaml`
  (commit `bc8e1fb`); validação medida: `cd ~/poker-freeroll-radar &&
  ~/oracfit/bin/oracfit mode validate hefesto` → `OK ... roles=['plan',
  'run', 'vision_gate', 'export']`.
- Checkpoints legíveis: `~/poker-freeroll-radar/CHECKPOINTS.md` (CP-0..CP-6
  + bloco ESTADO ATUAL); commits `bc8e1fb`→`32db19a` na branch `hefesto`
  (timestamps via `git log --format='%h %ad' main..hefesto`).
- Blockers do critic e correção: diff de `4c58fcf`
  (`app/services/tracking.py`, `app/api/v1/endpoints/affiliates.py`);
  registro em CHECKPOINTS.md CP-6; rodada do critic no transcript da sessão
  (`~/.cursor/projects/Users-mini-poker-freeroll-radar/agent-transcripts/
  a03c8107-3dc3-4466-8983-fb228bf8c375/`).
- Prova R-FS do CP-6 (302 verde + contagem 0≠50) e prova do detector novo
  (FAILED com `link.id` pós-rollback reintroduzido): terminais desta sessão.
- Duplicação medida: `git show <c>:CHECKPOINTS.md | rg -c '^## CP-2'` → 2 em
  `404a641`/`2f6ac37`/`98c2a71`/`aa56c67`, 1 em `4c58fcf`; numstat de
  `4c58fcf` (37+/21− CHECKPOINTS.md, 2+/2− backlog).
- Ledger sem entradas do modo: `rg -c hefesto ~/oracfit/ledger/ledger.jsonl`
  → exit 1 (0 matches).
- Achados devolvidos ao dono: `~/poker-freeroll-radar/docs-findings/
  BACKLOG-achados-nao-corrigidos.md` (2 achados novos do CP-6).

## O que este incident PROVA pra v4

1. **O trio de sessões fecha o desenho do detector:** oráculo verde não vê
   defeito semântico (2 blockers com 54/54 verde aqui), autoauditoria quente
   pega 0 (pythia), e o critic fresco pegou os graves nas DUAS sessões em
   que existiu (3 rejeições no ouroboros, 2 blockers aqui). Critic fresco
   por anel de código deixa de ser preferência e vira requisito — mas hoje é
   o componente MENOS mecânico de todos (sintoma 3).
2. **Contabilidade manuscrita não é risco teórico: corrompeu na 3ª sessão
   observada** — duplicação nascida dentro do anel, invisível por 3 anéis,
   no artefato que o dono usa para auditar. Ring ledger mecânico (regra 1)
   deixou de ser sugestão.
3. **Semi-mecanismos baratos pagam:** a prova R-FS de sabotagem custou ~1
   comando por story e foi a única coisa além do critic a distinguir
   "funciona" de "detecta" (0≠50 com 302 verde) — merece virar primitiva de
   core, desde que não-destrutiva (satélite do checkout).

## Pode acontecer de novo?

Sim, em qualquer god mode de fábrica da v3.5: a duplicação de checkpoint
repete enquanto o único leitor do arquivo for o próprio escritor (nenhuma
validação existe); os blockers passam se o executor pular a rodada do critic
(nada obriga); e a colisão de id repete a cada modo novo batizado num dia de
criação em rajada — 9 god modes commitados no oracfit só em 2026-08-12
(git log do repo: pythia, demiurgo à tarde; autarca, talos, hefesto A,
midas, pantocrator, ouroboros, aion na rajada 21:14–21:56), mais um décimo
homônimo de um deles no workdir de outro projeto.
