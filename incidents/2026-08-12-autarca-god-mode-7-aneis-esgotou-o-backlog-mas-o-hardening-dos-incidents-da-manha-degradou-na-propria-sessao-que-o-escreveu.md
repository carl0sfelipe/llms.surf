---
id: 2026-08-12-autarca-god-mode-7-aneis-esgotou-o-backlog-mas-o-hardening-dos-incidents-da-manha-degradou-na-propria-sessao-que-o-escreveu
titulo: AUTARCA (god mode v3.5) fechou 7 anéis em cadeia contínua e ESGOTOU o backlog (15/15 stories, 97→174 testes) em 1h46 sem humano — mas das 9 cláusulas de hardening destiladas dos incidents da manhã, 2 viraram letra morta, 2 degradaram em horas e a cláusula commit_cirurgico nasceu violada pelo próprio commit que a criou
data: 2026-08-12
recorrivel: sim
regra: nao — 7 regras candidatas para a v4 no corpo (4 convergentes, 3 novas)
status: aberto
interage_com: "2026-08-12-autarca-sumarizacao-de-contexto-no-meio-da-cadeia-ledger-derivou-de-schema-e-veredito-do-critic-virou-parafrase"
interage_com: "2026-08-12-autarca-critic-fresco-devolveu-achados-fora-do-canal-de-resposta-em-2-de-3-aneis-observaveis"
interage_com: "2026-08-12-autarca-oraculo-verde-2x-no-mesmo-minuto-aprovou-assercao-flaky-que-o-anel-seguinte-estourou"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-hefesto-god-mode-6-stories-verdes-critic-fresco-pegou-os-2-blockers-e-checkpoint-manuscrito-duplicou"
---

# AUTARCA — postmortem do god mode v3.5 (sessão poker-club-os, cadeia contínua)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo | `autarca` — `~/oracfit/core/modes/autarca.yaml`, commit `6a16fd7`. Diferencial declarado: PLANEJAMENTO também no frontier — fechado um anel, o próprio host escolhe a próxima story do backlog e abre o seguinte sem pedir. Nasceu com 9 cláusulas de `hardening` destiladas dos incidents do ouroboros e do "aprovou-4-ciclos-dono-deu-3.72" da manhã |
| Alvo | `~/poker-club-os` (monorepo Fastify + Socket.io + Postgres RLS multi-tenant, backlog BMAD de 15 stories em `_bmad-output/planning-artifacts/epics/epics.md`) |
| Duração / anéis | **1h46min07s de parede, 7 anéis** (ledger: `chain_open` 00:15:57Z → fechamento A-7 02:02:04Z). Por anel (deltas de `ts` no ledger): A-1 16m52s, A-2 24m54s, A-3 16m33s, A-4 10m22s, A-5 12m25s, A-6 13m27s, A-7 10m53s. Cadeia parou por backlog esgotado, não por teto |
| Papéis | Planner+spec+executor+judge+checkpoint = frontier no MESMO contexto QUENTE (que atravessou 1 sumarização no meio do A-5 — satélite próprio). Critic = frontier em contexto FRESCO, 1 Task subagent por anel (7 vereditos; A-5/A-6/A-7 com ids `f63ff322`, `c3a21195`, `2ebe95bc` no transcript; A-1..A-4 registrados em `CHECKPOINTS.md`). Zero dispatch a modelo free |
| Oráculos | `npm test` (vitest) + `npm run typecheck`, 2 rodadas por fechamento; `set -o pipefail` a partir do A-3 (o A-3 descobriu que `npm test \| tail` mascarava exit code — registrado no ledger A-3). Suíte cresceu 97→174 testes ao longo da cadeia (ledger, campo `tests` de cada fechamento) |
| Quem pegou cada bug | **Critic fresco: 7🔴 no total** (2+1+1+1+2+0+0 por anel, ledger) — incl. vazamento da sala cash (A-5), ordenação que expulsaria mesas abertas do broadcast (A-5), "mesmo ato" prometido em spec mas implementado em 2 transações (A-6), seleção fantasma multi-tablet (A-7), DO UPDATE que deixava rota pública reescrever PII (A-4). **Oráculo:** a flaky plantada no A-5 (1 failed/158 passed na 1ª rodada do A-6 — satélite próprio). **Autoauditoria quente:** coluna `display_name` errada e asserção de ordenação torta, ambas pegas ANTES do oráculo rodar (transcript). **Ninguém no anel:** a flaky do A-5 passou verde 2x e fechou anel |
| Ledger | **13 linhas** `"mode":"autarca"` (`rg -c` em `ledger/ledger.jsonl`): 1 chain_open + 5 ring_open + 4 ring_close com `event` + **3 fechamentos SEM campo `event`** (A-5/A-6/A-7 — drift de schema, satélite próprio) |
| Granularidade | 1 anel = 1 commit cirúrgico, **manteve-se 7/7** (git log do alvo: `f125c2e`, `e06c5f7`, `6b666e2`, `913592d`, `6a9c029`, `3768e37`, `5cfa94a`) — não derivou como no pythia (C0+C1 fundidos) |
| Falhas de ambiente | Colima/Docker morreu NO MEIO do A-3 com o preflight de anel PULADO (auto-registrado: `CHECKPOINTS.md:174` "EU pulei o preflight pg_isready deste anel" + ledger A-3 campo `incidentes`); preflight do A-6 rodou `pg_isready` com nome de container ERRADO (`poker-club-os-db-1` não existia; real: `club-os-db`; exit 127 no transcript, recuperado via `docker ps`); preflight do A-7 não re-executado (inferido de estado de ~1 min antes — transcript) |
| Decisões autônomas | 9+, todas registradas: late-registration e vírgula-decimal (`specs/payout-4.3.md`), dedup DO NOTHING (`specs/leads-6.2.md`), tela-sem-sessão + fechar-não-expulsa + janela-12h (`specs/mesas-cash-5.1.md`), uma-fila-por-clube + RNF-05-como-contrato (`specs/fila-espera-5.2.md`), floor-sem-game (`specs/tela-floor-a7.md`), pausa da cadeia com 4 pendências de dono (`CHECKPOINTS.md`, bloco final). **Inclui 1 decisão de ESCOPO: o anel A-7 não é story do backlog** — o planner criou um anel próprio (declarado no spec) para fechar o RNF-05 |
| Custo | Sem medição de tokens disponível na sessão (não cito número). Tempo: oráculo ~9–11s por rodada dupla (terminal); 1 subagent critic por anel; o resto da parede é o frontier quente escrevendo spec/código/teste — diferente do ouroboros (I/O de pipeline), aqui não há fatia óbvia para descer de tier além da redação de checkpoint |

## Contexto

Terceiro-e-tantos god mode do dia (ouroboros, pythia, hefesto, demiurgo,
aion, talos vieram antes — ver incidents irmãos). O autarca foi desenhado
DEPOIS de ler os postmortems da manhã: a promessa era converter as lições
em cláusulas de `hardening` no yaml e rodar em CADEIA (multi-anel, planner
autônomo, humano só audita checkpoints). É o único dos irmãos com
`stop_when`/`skip_when` explícitos para colisão com sessão paralela e
decisão de dono pendente.

Resultado bruto (medido): **7 anéis, 7 commits, backlog de 15 stories
100% entregue** (o alvo tinha 8 stories commitadas antes da cadeia; a
cadeia entregou 4.1, 4.2, 4.3, 6.2, 5.1, 5.2 + anel A-7 de superfície),
suíte de 97→174 testes (ledger), 3 telas servidas (`tv.html` pré-cadeia;
`salao.html`, `floor.html` na cadeia), zero intervenção humana entre
`chain_open` e a pausa final.

## O que funcionou (com evidência e contraprova)

1. **A cadeia como forma**: 7 anéis encadeados sem humano, granularidade
   1-anel-1-commit mantida 7/7 (git log), e a parada final foi
   AUTO-aplicada pela regra certa (`skip_when: decisao_de_dono_pendente`
   — backlog esgotado, 4 pendências de dono registradas em vez de
   inventar escopo). Contraprova: teria quebrado se o backlog tivesse
   ambiguidade — o único teste dessa borda foi o A-7, onde o planner
   ESTICOU "backlog do workdir" para um anel não-numerado; deu certo
   porque havia promessa registrada no checkpoint do A-5, mas nada
   mecânico limitava o tamanho da esticada.
2. **Critic fresco por anel pagou o aluguel**: 7🔴 ao longo da cadeia
   (ledger), nenhum estilístico. Os dois melhores: o vazamento da sala
   cash (A-5 — join sem validar existência do tenant, com comentário
   alegando falsa paridade com a TV) e o "mesmo ato" do spec A-6 que a
   implementação não cumpria (2 transações; janela onde o jogador
   sentado segurava a posição 1 da fila). Confirma hefesto/ouroboros por
   caminho independente. Contraprova: nos anéis A-6/A-7 o critic deu
   0🔴 — sem nota real do dono ainda (cláusula de calibração inerte),
   não dá para distinguir "executor aprendeu" de "critic amoleceu".
3. **Preflight de anel PEGOU o que devia quando rodou**: a sessão
   paralela (que commitou stories 1.x–3.x mais cedo, git log 16:14–19:50)
   ficou quieta a noite toda e os preflights A-5/A-6 verificaram isso
   (git log/status no transcript) antes de abrir anel. Contraprova: é
   protocolo — no A-3 foi pulado e o colima morreu no meio; no A-7 foi
   inferido em vez de re-executado (ficha).
4. **Oráculo com pipefail + suíte 2x**: depois do A-3, nenhum exit code
   mascarado; 174/174 no fechamento final (terminal). Contraprova direta:
   o satélite da flaky prova que "2x no mesmo minuto" é amostra
   correlacionada, não prova de determinismo.

## Contraste com os god modes irmãos (fonte: incidents citados)

| Modo (fonte) | Proteção central | O que o autarca acrescenta/confirma |
|---|---|---|
| ouroboros (incident irmão) | Critic fresco + oráculo soberano; tudo protocolo | Autarca IMPLEMENTOU as regras candidatas 1/2/3/6 do ouroboros como cláusulas yaml — e mediu que cláusula sem executável degrada NA MESMA SESSÃO (ver "o que quebrou") |
| pythia (incident irmão) | Validador mecânico na saída do juiz; autoauditoria quente fraca | Confirmado: aqui a autoauditoria quente pegou 2 erros triviais (coluna, asserção) e NENHUM dos 7🔴; identidade git default (`mini@Mac-mini-de-mac.local`) apareceu de novo nos 7 commits (3ª sessão — classe preflight) |
| hefesto (incident irmão) | Fábrica BMAD com stories escritas antes; critic fresco pegou os 2 blockers | Mesmo padrão de valor do critic; o autarca acrescenta a CADEIA (hefesto fechou 6 stories em 69min52s com contabilidade manuscrita que duplicou checkpoint — o autarca não duplicou, mas derivou schema do ledger: mesma classe, forma nova) |
| demiurgo (incident irmão) | sha256 da trave (único mecanismo real) | O `oraculo_monotonico` do autarca era a versão-cláusula do meio-termo proposto pelo ouroboros — passou a cadeia inteira SEM ser exercido (nenhum check removido), então segue não-testado |
| aion (incident irmão) | Mecanismo real de workdir, mas perpetuidade morreu com a sessão | O autarca não tentou perpetuidade (cadeia vive na sessão por design) — a sumarização no meio do A-5 é o análogo intra-sessão da morte de sessão do aion: o que era memória de protocolo se perdeu, o que era arquivo sobreviveu |
| talos (incident irmão) | mode-validate que falha no próprio yaml | Não observei validação de yaml no autarca: o modo nunca foi validado por ferramenta nenhuma (criado e usado como documentação) — consistente com o achado do talos |

## O que quebrou / ficou frágil (sintomas, com evidência e classe)

Auditoria cláusula a cláusula do `hardening` (9 cláusulas, autarca.yaml
commit `6a16fd7`) — o eixo mecanismo×protocolo aplicado ao próprio
hardening:

1. **`commit_cirurgico` nasceu violada** (classe: protocolo sem mecanismo,
   violado ANTES do primeiro anel): o commit `6a16fd7`, que CRIA o modo e
   contém a cláusula "git add sempre com pathspec explícito; -A/-u
   proibidos", varreu junto um incident de 177 linhas de OUTRO agente
   pré-staged na árvore compartilhada (`git show --stat 6a16fd7`: 2
   arquivos, o yaml + `2026-08-12-god-mode-ouroboros-aprovou-4-ciclos-e-o-.md`).
   Mesma classe do sintoma 3 do ouroboros, na sessão que acabara de LER
   aquele incident. Os 7 commits do alvo, depois, usaram pathspec
   explícito (transcript) — a disciplina segurou onde a cláusula estava
   fresca na atenção, e falhou exatamente onde a atenção estava no yaml
   e não no `git add`.
2. **`preflight_anel` degradou em horas** (protocolo): pulado no A-3 (com
   colima morrendo NO MEIO do anel — auto-registrado em
   `CHECKPOINTS.md:174` e no ledger A-3), rodado com container errado no
   A-6 (exit 127, recuperado na hora), inferido-sem-rodar no A-7. A
   cláusula `preflight_diario` diz textualmente "Regra promovida de manhã
   não pode ser redescoberta à tarde" — e foi exatamente o que aconteceu,
   dentro da MESMA sessão que escreveu a frase.
3. **`claims_check` foi letra morta os 7 anéis** (protocolo nunca
   exercido): a cláusula exige que todo número do checkpoint aponte
   artefato e que o critic RECONTE por amostragem. Nenhum dos 7 vereditos
   recontou número de checkpoint — impossível por construção: os
   checkpoints foram escritos DEPOIS do critic rodar (ordem visível no
   transcript). A cláusula era incompatível com o fluxo real e ninguém
   notou, porque nada executável a cobrava.
4. **`gate_de_classe_visual` foi letra morta com artefato visual na mesa**
   (protocolo nunca exercido): A-6 e A-7 entregaram telas (`salao.html`,
   `floor.html`) e **nenhuma tela da cadeia foi sequer renderizada** — 
   zero screenshots na sessão inteira (transcript). A "prova" das telas é
   smoke de fonte (HTTP 200 + substring `textContent`, declarado
   honestamente em `specs/fila-espera-5.2.md`, mas o gate prometia juízo
   de CLASSE contra referência externa). O produto tem 3 telas que nenhum
   olho — humano ou de modelo — viu montadas.
5. **`oraculo_monotonico` e `calibracao_nota_dono` seguem não-testadas**
   (não é falha, é ausência de exercício): nenhum check foi removido
   (suíte só cresceu 97→174) e o dono ainda não deu nota real (7
   previsões registradas no ledger, delta incomputável). Cláusulas que
   nunca dispararam não contam como proteção comprovada.
6. **Classe de 🔴 recorrente sem aprendizado mecânico** (processo): "spec
   alega teste que não existe" apareceu no A-1 (`paid_by` prometido e não
   testado), A-2 (RBAC floor/dealer alegado, só dealer testado) e A-4
   (idem — o próprio checkpoint chama de "O 🔴 de sempre",
   `CHECKPOINTS.md` bloco A-4). O executor só parou de cometer a classe
   quando o padrão entrou no hábito — 3 anéis pagando 1🔴 cada por algo
   que um linter spec↔teste pegaria de graça.
7. Satélites (modos de falha distintos, incidents próprios): **sumarização
   derrubou schema do ledger e o detalhe do veredito do critic**;
   **critic devolveu achados fora do canal de resposta em 2 de 3 anéis
   observáveis**; **oráculo verde-2x aprovou asserção flaky**.

## Causa raiz

A mesma do ouroboros e do pythia, agora com a variante mais incômoda
provada: **transformar lição de incident em CLÁUSULA de yaml não a
transforma em mecanismo** — o autarca é a prova de que nem a memória
fresca da manhã segura protocolo por uma sessão inteira. Das 9 cláusulas:
3 exercidas como escritas (preflight_diario, ledger_host_mode com drift,
biggest_gap por disciplina), 2 degradadas em horas, 2 letra morta, 2
não-testadas — e a única coisa que NUNCA falhou na cadeia foi o que era
executável (suíte de testes, typecheck, RLS/FKs no banco, git).

## Regras candidatas para a v4

Convergentes (reforço com evidência nova):

1. **`bin/oracfit ring open|close`** (= regra 1 ouroboros, regra 1
   pythia; 4ª sessão a precisar): aqui há evidência ADICIONAL — o ledger
   manuscrito existiu (13 linhas) e mesmo assim derivou de schema no meio;
   um runner com schema fixo torna o drift impossível, e o `ring open`
   é o lugar do preflight que foi pulado/inferido 2x (sintoma 2).
2. **claims-check mecânico spec↔teste** (= regra 6 ouroboros): evidência
   dupla — a cláusula manuscrita foi letra morta 7/7 anéis (sintoma 3) e
   a classe de 🔴 mais recorrente da cadeia (3 ocorrências, sintoma 6) é
   exatamente a que um extrator de claims de spec com busca no diff de
   teste elimina.
3. **Critic fresco obrigatório para anel de código** (= regra 4 pythia):
   7🔴 do critic vs 0 achados graves da autoauditoria quente. Reforço em
   3ª sessão independente.
4. **Preflight de ambiente no ring open** (= regra 3 pythia / ENOSPC):
   colima morto no meio do anel com preflight pulado + identidade git
   default nos 7 commits (mesma classe do pythia, sintoma 4 dele).

Novas (evidência só desta sessão):

5. **Estado de modo à prova de sumarização**: tudo que a cadeia precisa
   lembrar entre anéis (schema do ledger, formato exigido do veredito,
   cláusulas ativas, anel corrente) mora em ARQUIVO relido no open de
   cada anel (`ring-state.json` ou o próprio runner da regra 1), nunca
   só no contexto do host. Sintoma coberto: drift de schema do ledger +
   re-poll do critic pós-sumarização (satélite 1). Custo: 1 arquivo +
   1 read por anel.
6. **Suíte nova re-rodada descorrelacionada no ring close**: "verde 2x"
   em rodadas consecutivas do mesmo minuto é amostra correlacionada —
   o close deveria re-rodar OS TESTES NOVOS do anel N vezes isolados
   (vitest permite filtrar por arquivo) antes de aceitar o selo. Sintoma
   coberto: flaky do A-5 aprovada verde-2x e estourada no A-6 (satélite
   3). Custo: segundos por anel.
7. **Gate visual com gatilho mecânico por diff**: se o diff do anel toca
   `public/*.html|css|js` de tela, o close EXIGE artefato de screenshot
   referenciado no checkpoint (a cláusula existia e nunca disparou porque
   dependia do executor lembrar — sintoma 4; 3 telas shipped sem nenhum
   render na sessão). Custo: 1 screenshot por anel visual; o mecanismo é
   o gatilho por pathspec, não o juízo.

## Evidência preservada

- Modo: `~/oracfit/core/modes/autarca.yaml` (commit `6a16fd7` — o mesmo
  que varreu o incident alheio; `git show --stat 6a16fd7`).
- Ledger: `~/oracfit/ledger/ledger.jsonl` — 13 linhas
  `"mode":"autarca"` (10 com `event`, 3 sem; timestamps citados na ficha).
- Alvo: `~/poker-club-os` — commits `f125c2e`..`5cfa94a` (7, git log com
  horários 21:32–23:02 local); `CHECKPOINTS.md` (bloco por anel, 330
  linhas ao fim da cadeia; auto-registro do preflight pulado na linha
  174); specs por anel em `specs/*.md`; `docs/diario-fundacao.md`.
- Transcript da sessão (papéis, preflights, ordem checkpoint-depois-do-
  critic, zero screenshots): `~/.cursor/projects/Users-mini-poker-club-os/
  agent-transcripts/e336d9b1-cd63-46be-bba1-7c5fb1e9b904/`.
- Vereditos do critic pós-sumarização: subagents `f63ff322` (A-5),
  `c3a21195` (A-6), `2ebe95bc` (A-7) no transcript.
- Sessão paralela monitorada: git log do alvo, janela 16:14–19:50 sem
  commits durante a cadeia (21:32+).

## O que este incident PROVA pra v4

1. **Cadeia contínua funciona como forma de trabalho** — 7 anéis,
   granularidade mantida, parada auto-aplicada correta — e o gargalo não
   é o julgamento do frontier: é que TODA a instrumentação da cadeia
   (ledger, preflight, claims, gate visual) era manuscrita.
2. **Cláusula de hardening não é mecanismo nem quando escrita horas antes
   pelos mesmos incidents que ela cita**: a taxa de degradação medida
   (2 letra morta + 2 degradadas de 9, em 1h46) é o número que a
   convergência v4 precisava para parar de aceitar "o modo agora tem a
   lição no yaml" como correção.
3. Sumarização de contexto é superfície de falha ESPECÍFICA de cadeias
   longas (quanto mais anéis, mais certa ela é) — e divide o mundo
   exatamente no eixo da v4: o que era arquivo sobreviveu, o que era
   protocolo virou paráfrase.

## Pode acontecer de novo?

Sim, e com probabilidade crescente no tamanho da cadeia: qualquer god
mode em cadeia vai atravessar sumarizações (drift de protocolo garantido
sem estado-em-arquivo), vai abrir anéis com momentum (preflight pulado é
questão de quando), e vai continuar invisível ao ledger real até o runner
de host-mode existir. A recorrência da classe "cláusula nova violada na
própria sessão" está demonstrada aqui em dose dupla (commit de nascimento
+ preflight) — não há razão para acreditar que uma 10ª cláusula se
comportaria diferente das 9.
