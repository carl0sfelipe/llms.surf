---
id: 2026-08-12-demiurgo-god-mode-convergiu-sem-reversao-mas-o-unico-mecanismo-era-o-sha256-da-trave
titulo: DEMIURGO (god mode v3.5) convergiu 8.1→9.8 em 3 iterações aceitas, zero reversões — mas a spec declarou "hard-fails MECÂNICOS" que nunca existiram como código; fora o sha256 da trave, toda proteção era protocolo, e juiz no mesmo contexto do gerador torna o arco de aceitação infalsificável
data: 2026-08-12
recorrivel: sim
regra: nao — 5 regras candidatas para a v4 no corpo (3 convergentes com ouroboros/pythia, 2 novas)
status: aberto
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-demiurgo-trave-autoral-baixa-saturou-em-3-iteracoes-sem-variancia-do-juiz"
---

# DEMIURGO — postmortem do god mode v3.5 (sessão tdah-loops)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo (nome + arquivo) | DEMIURGO — `core/modes/demiurgo.yaml` (oracfit main, commit `38dca41`) |
| Alvo(s) | `~/tdah-loops-repo`, branch `demiurgo`; artefato único: `skills/claude-code/SKILL.md` (skill coach TDAH) |
| Duração de parede e anéis | Spec+trave: 16:21–16:27 (commits `38dca41` oracfit, `df83fac` tdah-loops). Run do executor: checkpoint-00 16:35 → checkpoint-03 16:40 (5 min entre 1º e último commit; dispatch do subagent ~16:24, notificação de término 16:41 — ~17 min ponta a ponta). 4 checkpoints fechados (1 baseline + 3 iterações), teto de 4 iterações NÃO atingido (parou na 3ª por convergência declarada) |
| Papéis frontier vs despachados | Zero dispatch a modelo free. Orquestrador frontier em contexto QUENTE: spec do modo, autoria da trave, congelamento, auditoria post-hoc. Executor: 1 Task subagent frontier, contexto fresco no INÍCIO mas gerador+juiz+crítico+auditor no MESMO contexto pelas 4 rodadas |
| Oráculos mecânicos | 1 (um): `evals/checar-congelamento.sh` — `shasum -a 256 -c` de 3 arquivos (`evals/HASHES`: casos.jsonl, rubrica.md, o próprio script). Rodado com exit 0 nas 4 rodadas (cabeçalho de cada checkpoint). Os "hard-fails H1–H6" NÃO são mecânicos — ver sintoma 1 |
| Quem pegou cada bug/rejeição | Única detecção do run: H5 na baseline (skill sem instrução para cron → executor simulou quebra de silêncio) — pega pela fase de julgamento do PRÓPRIO executor (mesmo contexto), guiada por hard-fail escrito ANTES na rubrica congelada (`checkpoints/checkpoint-00.md`, seção "Hard-fails encontrados"). Nas 3 iterações: zero rejeições, zero reversões — ninguém rejeitou nada |
| Entradas no ledger.jsonl | `rg -c demiurgo ~/oracfit/ledger/ledger.jsonl` → **0** (medido 2026-08-12 ~22:50). 3ª ocorrência independente no dia (ouroboros: 0; pythia: 0) |
| Granularidade de checkpoint | 1 rodada = 1 commit, manteve 4/4: `1677375` 16:35, `61f3141` 16:37, `151ee1c` 16:38, `5476346` 16:40 (`git log --date=format:'%H:%M'` na branch demiurgo). Não derivou (contraste: pythia fundiu C0+C1 e C3+C4) |
| Falhas de ambiente | Nenhuma observada: 4 commits e 4 execuções do freeze-check com exit 0; sem ENOSPC, sem morte de terminal. Nota: o run inteiro viveu dentro de 1 subagent por ~17 min, sem processo longo externo — a classe de falha do ouroboros (cadeia/vigia em terminal de sessão) não tinha superfície aqui |
| Decisões autônomas sem o dono | Nome do modo; autoria dos 8 casos + rubrica + limiar de convergência 0.3 + teto 4 (registradas em `core/modes/demiurgo.yaml`, `evals/rubrica.md` e no loop `demiurgo-evolucao-skill-coach` de `~/TDAH/open-loops.yaml`); parada por convergência na it. 3 (registrada em `checkpoints/checkpoint-03.md`). Dono não foi consultado entre o dispatch e o fim (por design do modo); skills instaladas não foram tocadas (gate revisao-humana aberto) |
| Custo | Tokens: NÃO medidos — não há ledger de host-mode (o próprio sintoma 3). Parede: ~17 min, 1 subagent frontier. O que poderia descer de tier: a fase de geração das 8 respostas por rodada (simulação mecânica de conformidade); o julgamento não (é o objeto do experimento) |

## Contexto

Terceiro god mode da v3.5 no mesmo dia (sessões independentes: ouroboros →
TCC/clubsurf, pythia → vagai, demiurgo → skill coach TDAH). Promessa
diferencial do demiurgo, escrita na própria spec: proteções "ESTRUTURAIS,
não de julgamento" — oráculo CONGELADO por sha256 antes da 1ª iteração,
"hard-fails mecânicos", teto de iterações, reversão em regressão, 1 commit
por rodada, nunca push. Alvo fechado e pequeno de propósito: 1 skill, 8
casos de eval derivados de incidentes reais do dono.

Resultado bruto: média 8.1 → 9.4 → 9.6 → 9.8 (65/80 → 78/80; o 9.8 é
arredondamento de 9.75, declarado no próprio checkpoint-03), 3 hipóteses
aceitas, 0 reversões, diff acumulado na skill de **16 inserções, 0 remoções**
(`git diff --stat df83fac..demiurgo -- skills/claude-code/SKILL.md`),
parada por convergência (ganhos +0.25 e +0.125 consecutivos ≤ 0.3).

## O que funcionou (com evidência e contraprova)

1. **O único mecanismo do modo rodou e passou 4/4**: freeze-check com exit 0
   citado no cabeçalho de cada checkpoint. Contraprova: qualquer byte a mais
   em `evals/casos.jsonl` faz `shasum -c` sair 1 (testável hoje) — MAS nada
   consome esse exit code mecanicamente; o executor lê e decide. Se
   ignorasse, nenhum runner abortaria (sintoma 2).
2. **Hard-fail pré-escrito pegou o único gap real**: H5 (silêncio no cron)
   estava na rubrica congelada ANTES do run e zerou o caso na baseline
   (`checkpoint-00.md`). Confirma por caminho independente a leitura do
   pythia: autoauditoria quente agrega valor quando existe CHECKLIST escrito
   antes. Contraprova: sem H5 escrito, a resposta tagarela do cron ("nada
   pra hoje!") parece prestativa e teria pontuado — o gap só é visível
   porque alguém o criminalizou por escrito antes de julgar.
3. **Granularidade 1 rodada = 1 commit segurou** (4/4, timestamps na ficha),
   onde o pythia derivou no mesmo dia. Contraprova: era protocolo — nada
   impedia fundir; segurou porque o prompt exigia e o run durou 17 min.
4. **Parou por convergência antes do teto** (3 de 4 iterações,
   `checkpoint-03.md`). Contraprova: o limiar 0.3 foi arbitrado pelo mesmo
   modelo que seria medido, e os ganhos das it. 02/03 são de 1–2 pontos em
   80 sem nenhuma variância de juiz medida — "convergência" pode ser apenas
   ruído esgotado (incident satélite, interage_com).

## Contraste com os god modes irmãos (mesmo dia, sessões independentes)

Fontes: os incidents do ouroboros e do pythia (interage_com). AION teve só
o arquivo de modo commitado hoje (`63f4de3`) sem run observado — sem linha.

| Dimensão | ouroboros | pythia | demiurgo (este) |
|---|---|---|---|
| Juiz/critic | Contexto FRESCO por papel | Mesmo contexto (autoauditoria) | Mesmo contexto (gerador=juiz no mesmo subagent) |
| Trave/oráculo | MÓVEL (editado entre anéis, 21→30 checks) | Determinístico por natureza (tsc/test) | CONGELADA por sha256 — único mecanismo do modo |
| Quem pegou bugs | Critic fresco (3 rejeições empíricas) | Oráculos (2); autoauditoria 0 | Hard-fail pré-escrito na baseline (1); nas iterações ninguém rejeitou nada |
| Ledger | vazio | vazio | vazio (3ª ocorrência) |
| Granularidade | CHECKPOINTS.md manuscrito | Derivou (ciclos fundidos 2x) | Segurou (4/4, 1 rodada = 1 commit) |
| Falha de ambiente | Sessão de terminal matou cadeia+vigia | ENOSPC no meio do anel | Nenhuma (run curto, sem processo externo) |
| Alvo | Fonte crescendo em background | Produto + dogfood em produção | Artefato FECHADO (1 skill, 8 casos) |

Leitura honesta da última linha: o congelamento só coube porque o alvo é
fechado — o próprio incident do ouroboros provou que trave congelada é
incompatível com fonte que cresce durante o run. O demiurgo não refuta isso;
ele só escolheu um alvo onde o problema não aparece.

## O que quebrou / ficou frágil

1. **A spec declara mecanismo que não existe** (falha de contrato da spec).
   `core/modes/demiurgo.yaml` afirma: "HARD-FAILS MECÂNICOS: violação de
   regra-nunca zera o caso [...] não é opinião do juiz, é grep na rubrica".
   Não existe grep, script ou parser — H1–H6 são aplicados por LEITURA do
   juiz (o mesmo modelo). A proteção central anunciada como código é
   protocolo vestido de mecanismo, e nada no sistema aponta a discrepância.
2. **Mecanismo órfão** (mecanismo sem consumidor mecânico). O freeze-check
   falha fechado como script, mas seu exit code é lido pelo executor e a
   decisão de abortar é dele. Os `stages`/`stage_oracle` do yaml nunca foram
   executados por runner algum — host-mode não passa por `bin/oracfit`
   (mesma causa raiz dos irmãos). Um mecanismo que só roda porque o
   protocolo manda, e só bloqueia porque o protocolo obedece, protege
   exatamente até onde o protocolo protegeria.
3. **Teto, reversão, no-push e never-tocar-evals: tudo protocolo.** Nenhum
   contador de iterações, nenhum hook pre-push, nenhuma permissão de arquivo
   protege `evals/`. Evidência: o diff da branch (`df83fac..demiurgo`) não
   contém nenhum executável além do freeze-check; `.git/hooks` do repo só
   tem samples. O run respeitou tudo — por disciplina, não por
   impossibilidade.
4. **Arco 100% de aceitação com juiz no contexto do gerador é
   infalsificável de dentro** (falha de desenho). 3 hipóteses, 3 aceites, 0
   reversões. A ordem anti-viés ("gerar as 8 respostas antes de julgar") é
   alegação do executor no checkpoint — mecanicamente inverificável. O
   relato final do próprio executor declara: o arco sem reversão "é
   compatível tanto com hipóteses boas quanto com viés de autopreferência".
   Auditoria post-hoc do orquestrador verificou hashes, commits e diff —
   mas não re-julgou nenhum caso de forma independente.
5. **`git add -A` codificado na spec** (stage checkpoint do demiurgo.yaml),
   escrito às 16:27 do MESMO DIA em que o ouroboros sofria na prática o
   sintoma da varredura de árvore compartilhada (commit `af029f7` do
   clubsurf levou arquivos de outro agente). No demiurgo deu certo por
   estrutura acidental: branch dedicada com executor único. Em qualquer
   god mode com árvore compartilhada, a spec atual reproduz o incident do
   irmão. Classe: convergência direta com a regra 5 do ouroboros.

## Causa raiz

A mesma dos irmãos, em 3ª ocorrência independente — **host-mode é invisível
aos mecanismos da v3.5, então o yaml vira documentação e as proteções
degradam para protocolo** — com um agravante próprio do demiurgo: **a spec
DECLAROU as proteções como "estruturais/mecânicas" quando só uma era código
(e até essa dependia de leitura do modelo para ter efeito)**. Spec que
mente sobre a classe das próprias proteções é pior que spec silenciosa: dá
confiança falsa que só se desfaz lendo o código que não existe.

## Regras candidatas para a v4

Convergentes (reforço com evidência nova, não repetição):

1. **`bin/oracfit ring open|close` com ledger obrigatório para host-mode**
   (= regra 1 do ouroboros = regra 1 do pythia; 3ª sessão independente a
   precisar no mesmo dia). Acréscimo do demiurgo: `ring close` exige o exit
   code do(s) oráculo(s) mecânico(s) GRAVADO no ledger — resolve o sintoma 2
   (mecanismo órfão) de graça. Custo: já orçado pelos irmãos.
2. **Juiz/critic fresco obrigatório** (= regra 4 do pythia, estendida de
   "anéis de código" para "julgamento de eval"): veredito que aceita/rejeita
   iteração não pode nascer no mesmo contexto que gerou o artefato julgado.
   Evidência minha: 3/3 aceites e 0 reversões em contexto quente,
   infalsificável de dentro. Custo: 1 subagent por rodada.
3. **Proibição mecânica de `git add -A` em modo multi-agente + remoção do
   `-A` da spec do demiurgo** (= regra 5 do ouroboros). Evidência minha: o
   anti-padrão está CODIFICADO num yaml de modo commitado, não só num hábito.
   Custo: editar 1 linha do yaml + o pre-commit hook já proposto pelo irmão.

Novas (evidência só desta sessão):

4. **Linter de spec de modo — proteção declarada exige executável
   apontável.** Toda frase de proteção num `core/modes/*.yaml` ("mecânico",
   "falha fechado", "bloqueia", "verifica") deve referenciar um
   `command`/`stage_oracle` cujo arquivo exista e seja executável; termo de
   mecanismo sem script = modo não carrega. Cobre o sintoma 1 (a mentira da
   spec ficaria impossível de commitar). Custo: script de lint de ~50
   linhas no pre-commit do oracfit.
5. **Recibo de oráculo no commit de checkpoint.** Pre-commit hook da branch
   de god mode: commit cuja mensagem case `checkpoint` só passa se o
   freeze-check (ou oráculo equivalente) tiver escrito um recibo com exit 0
   nos últimos N segundos (arquivo `.oracle-receipt` fora do índice). Versão
   mínima do "consumidor mecânico" (sintoma 2) que funciona HOJE, sem
   esperar o runner da regra 1. Custo: 1 hook + 3 linhas no script do
   oráculo.

## Evidência preservada

- Spec do modo: `~/oracfit/core/modes/demiurgo.yaml` (commit `38dca41`) —
  as citações do sintoma 1 e 5 estão no texto commitado.
- Trave congelada: `~/tdah-loops-repo/evals/{casos.jsonl,rubrica.md,HASHES,checar-congelamento.sh}`
  (commit `df83fac`); verificação reproduzível: `bash evals/checar-congelamento.sh`.
- Checkpoints com scores, citações e vereditos:
  `~/tdah-loops-repo/checkpoints/checkpoint-0{0..3}.md` (commits `1677375`,
  `61f3141`, `151ee1c`, `5476346`, branch demiurgo — timestamps via
  `git log --date=format:'%H:%M'`).
- Diff acumulado da skill: `git -C ~/tdah-loops-repo diff df83fac..demiurgo
  -- skills/claude-code/SKILL.md` (16 inserções, 0 remoções).
- Ledger sem entradas do modo: `rg -c demiurgo ~/oracfit/ledger/ledger.jsonl` → 0.
- Relato final do executor (inclusive a autodeclaração de viés): transcript
  do subagent DEMIURGO da sessão de 2026-08-12 ~16:24–16:41 (conversa do
  coach, Cursor).

## O que este incident PROVA pra v4

1. **Ledger vazio em host-mode saiu de "achado" para "lei"**: 3 sessões
   independentes, 3 modos diferentes, mesmo resultado no mesmo dia. A regra
   `ring open|close` não é mais candidata — é pré-requisito da v4.
2. **Congelar a trave resolve UM eixo e não toca no outro.** Ouroboros
   (trave móvel, juiz fresco) e demiurgo (trave congelada, juiz quente)
   falham em pontos complementares; a v4 precisa dos dois ao mesmo tempo:
   trave com guarda de monotonicidade E juiz fresco por rodada.
3. **Spec pode mentir sobre a classe das próprias proteções e nada acusa.**
   "Mecânico" escrito num yaml não custa nada; o linter (regra 4) torna a
   palavra cara.

## Pode acontecer de novo?

Sim, por duas vias. Qualquer god mode novo pode redeclarar protocolo como
mecanismo sem que nada aponte (até a regra 4 existir) — o demiurgo fez isso
de boa-fé no mesmo dia em que dois irmãos documentavam o eixo
mecanismo×protocolo. E o próximo run do próprio demiurgo (o checkpoint-03
deixa a porta aberta para uma rodada 2 da skill) repetiria juiz quente +
arco infalsificável se rodar com o yaml de hoje.
