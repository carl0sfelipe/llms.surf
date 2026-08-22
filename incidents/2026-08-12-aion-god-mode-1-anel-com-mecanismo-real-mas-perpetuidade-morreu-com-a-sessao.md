---
id: 2026-08-12-aion-god-mode-1-anel-com-mecanismo-real-mas-perpetuidade-morreu-com-a-sessao
titulo: AION (god mode v3.5) fechou 1 anel com ledger não-vazio, teto contado e veredito falha-fechado em script de workdir — mas a perpetuidade prometida (o diferencial do modo) morreu aos 102s com o despertador de sessão, e a auto-direção executou 1 de 5 anéis planejados
data: 2026-08-12
recorrivel: sim
regra: nao — 5 regras candidatas para a v4 no corpo (3 convergem com ouroboros/pythia; 2 são novas)
status: aberto
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-god-mode-ouroboros-aprovou-4-ciclos-e-o-"
interage_com: "2026-08-12-aion-ring-close-grava-ledger-depois-do-commit-e-linha-dangla-ate-commit-externo"
interage_com: "2026-08-12-servidor-demo-morre-quando-a-sessao-do-s"
interage_com: "2026-08-12-dispatch-de-shell-de-agente-morre-com-o-"
---

# AION — postmortem do god mode v3.5 (sessão relay-juggler / demo de merger)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo (nome + config/doc) | `aion` — `core/modes/aion.yaml`, `core/critic-profiles/aion-comprador.md`, `docs/modes/aion.md` (untracked no repo oracfit, como os irmãos da 3.5) |
| Alvo(s) | `~/relay-juggler`, branch `demo/neural-loop` (protótipo Neural Loop, artefato da negociação de merger Relay × AI Juggler) |
| Duração de parede e anéis | 1 anel fechado (RING-1): open `2026-08-13T00:21:14Z` → close `00:31:06Z` = **9m52s** (timestamps do `aion/ledger.jsonl`). Anéis 2–5: nunca executados (despertador morto, ver sintoma 1). |
| Papéis frontier vs despachados | plan/build/refino: frontier QUENTE (host Cursor/Fable). Critic: frontier FRESCO (1 Task subagent generalPurpose com o profile no prompt). Zero dispatch a tier free. Oráculo: mecânico via `aion/ring.sh` (261 linhas bash, `wc -l`). |
| Oráculos mecânicos | 3 comandos no `ring.sh close`: `pnpm typecheck` (exit 0, 36s), `pnpm vitest run neural-loop content-classifier token-estimator` (exit 0, 4s), `pnpm test:stable` (exit 0, 3s; 75 testes passados, 7 arquivos — saída do terminal do close). Durações/exits gravados pelo script em `CHECKPOINTS.md`. |
| Quem pegou cada bug | Critic fresco: **4/4 achados** (`aion/verdicts/RING-1.json`, array `findings` com 4 itens) — 2 corrigidos no anel (data UTC "amanhã"; números re-declarados na mão no demo), 2 aceitos e registrados (`aion/notes/RING-1.md`). Oráculo: 0. Autoauditoria quente do executor: 0. Bug do próprio `ring.sh` (ordenação do ledger, incident satélite): **ninguém no run** — detectado só neste postmortem, via commit externo. |
| Entradas no ledger | `rg -c '"mode": "aion"' ~/oracfit/ledger/ledger.jsonl` → **2** (open+close). Workdir `aion/ledger.jsonl` → 2 linhas. Primeiro god mode do dia com ledger NÃO-vazio (ouroboros: 0; pythia: 0). |
| Granularidade de checkpoint | 1 anel = 2 commits feitos PELO SCRIPT com pathspec (`82c59a84` build, `3f1ee2a9` checkpoint). Sem deriva — mas n=1, sem valor estatístico. |
| Falhas de ambiente | Despertador do loop (sleep 1500s em terminal de sessão) morto aos **101,6s** (`terminals/844673.txt`: `status: aborted`, started `00:31:41.196Z`, ended `00:33:22.812Z`, exit unknown) — 4ª ocorrência do dia da classe sessão-mata-processo. O servidor da demo (porta 8899) já tinha morrido mais cedo na mesma sessão (incident próprio já existente). |
| Decisões autônomas sem o dono | nome do modo (AION); teto=5; composição do oráculo (3 comandos); ordem do backlog de 5 anéis (`aion/BACKLOG.md`); aceitar 2 achados do critic sem correção no anel. Registradas em: comentários do yaml, `aion/BACKLOG.md`, `aion/notes/RING-1.md`, `CHECKPOINTS.md`. |
| Custo | Tokens: **não instrumentados — não medido**. Tempo medido: anel de 9m52s, dos quais 44,4s de oráculo (terminal do close: "Command completed in 44392 ms"). 1 subagent (critic). Nada deste anel era despachável a tier free sem perder o objeto do teste (julgamento de fronteira em todas as pontas era a hipótese). |

## Contexto

Quarto god mode da v3.5 no mesmo dia (pythia → demiurgo → ouroboros → aion),
desenhado EXPLICITAMENTE a partir dos incidents dos irmãos: (a) do
"ouroboros aprovou 4 ciclos e o dono deu 3.72" veio o critic `aion-comprador`
que prevê a nota do dono (`owner_score_pred`, APPROVED exige ≥ 4.5); (b) do
"toda proteção era protocolo" vieram as proteções como script de workdir
(`aion/ring.sh`): teto contado no ledger, anel só fecha com oráculo exit 0,
veredito sem `biggest_gap` recusado, commit só com pathspec.

Diferencial declarado vs irmãos: **auto-direção** — o modo mantém backlog
próprio ordenado por leverage e escolhe o próximo incremento sozinho, em
loop perpétuo até o dono revisar checkpoints.

Resultado bruto: RING-1 fechado em 9m52s (`composeNeuralLoopHandoff` em
`@relay/shared`: 6 testes novos — `rg -c "^  it\(" .../neural-loop-handoff.test.ts`
→ 6 —, seção nova no demo script, oráculo 3/3 verde, critic APPROVED 4.6/5
com 4 achados). Anéis 2–5: **zero**. O loop perpétuo sobreviveu a zero
acordadas.

## O que funcionou (com evidência e contraprova)

1. **Ledger de host-mode deixou de ser vazio** — as regras candidatas 1 do
   ouroboros e 1 do pythia, implementadas como piloto em 261 linhas de bash
   de workdir. Evidência: 2 entradas com `"mode": "aion"` no
   `ledger/ledger.jsonl` do oracfit (rg acima), com oracle_exit real,
   veredito, score e commits. Contraprova: teria quebrado se o executor
   fechasse o anel por fora do script — nada impede mecanicamente chamar
   `git commit` direto; o ledger só é obrigatório porque o protocolo diz
   "feche via ring.sh". A obrigatoriedade continua protocolo.
2. **Critic fresco com régua de dono pegou o que oráculo não pega**: os 4
   achados do `verdicts/RING-1.json` incluem um bug real invisível a
   typecheck/teste (data `toISOString()` UTC imprime o dia SEGUINTE em
   sessão noturna UTC-3 — visível na mesa de negociação) e uma fragilidade
   de coerência da demo (números re-declarados na mão). Contraprova: o
   mesmo critic APROVOU com 4.6 — se a régua do dono real vier abaixo
   disso, é o incident "4 ciclos/3.72" de novo; a diferença é que agora a
   previsão está GRAVADA no ledger (`rg -c owner_score_pred ledger.jsonl`
   → 1) e o delta previsão×real será medível.
3. **Validador falha-fechado do veredito existe como código** (`ring.sh`:
   APPROVED exige `biggest_gap` não-vazio E `owner_score_pred ≥ 4.5` E
   `buyer_value` não-vazio; senão exit 1 e anel fica aberto). Honestidade:
   **nunca foi exercitado por veredito inválido nesta sessão** — o único
   veredito recebido era válido. Cobertura provada por leitura de código,
   não por execução. As recusas de `open` (teto, anel duplicado, dois anéis
   simultâneos) também não dispararam — caminho feliz do início ao fim.
4. **Claims-check barato**: o checkpoint é montado pelo script com os
   números que o próprio script mediu (exits, durações, commits) — o
   executor escreve só prosa (`aion/notes/`). Contraprova: os números de
   CONTAGEM da prosa (ex.: "6 testes") continuam manuscritos e o script
   não os verifica — a recontagem foi feita pelo critic (protocolo do
   profile), não por mecanismo.

## Contraste com os god modes irmãos

| Dimensão | ouroboros | pythia | demiurgo | **aion** |
|---|---|---|---|---|
| Critic | fresco (subagent+profile) | quente (mesmo contexto) | quente contra oráculo congelado | fresco (subagent+profile) com régua de nota-do-dono |
| Ledger | vazio | vazio | (não relatado no incident irmão) | **2 entradas** (mecanismo de workdir) |
| Teto de anéis | prometido no yaml | prometido | prometido (parou por convergência) | **contado no ledger pelo script** |
| Veredito falha-fechado | protocolo (profile) | mecanismo no produto (rank import) | n/a | mecanismo no runner do anel (não exercitado) |
| Commit | executor, `add -A` varreu árvore | executor, ciclos fundidos sob pressão | script por iteração | **script com pathspec, 2 commits/anel** |
| Anéis fechados / planejados | 6 / aberto | 5 / aberto | 4 / teto 4 | **1 / 5** |
| O que matou a continuidade | sessão matou cadeia+vigia | ENOSPC (satélite) + fim de janela | convergência (fim natural) | **sessão matou o despertador aos 102s** |

(Linha do content_factory omitida: não observado nesta sessão; ver tabela do
incident do ouroboros.)

## O que quebrou / ficou frágil

1. **A perpetuidade — o diferencial do modo — morreu aos 101,6s e ninguém
   percebeu por 73 minutos.** O despertador (`sleep 1500 && echo
   AGENT_LOOP_WAKE_AION ...`) era um terminal de sessão do IDE;
   `terminals/844673.txt` registra `status: aborted` com ended_at
   `00:33:22.812Z` — 101,6s dos 1500s. Nenhum wake, nenhum RING-2, silêncio
   até o dono voltar às ~22:46. Classe: **mecanismo ausente** (wake
   out-of-session) — 4ª ocorrência do dia da mesma classe (cadeia+vigia do
   ouroboros, servidor da demo, dispatch de shell). Agravante novo: o
   `aion.yaml` DECLARAVA esta exata limitação ("o despertador vive na
   sessão do IDE e morre com ela") — declarar não mitigou nada; o modo
   entrou de olhos abertos na falha que o seu próprio yaml descrevia.
2. **O evento `close` do ledger nasceu órfão de commit** — o `ring.sh`
   grava o close DEPOIS do commit de checkpoint; `git show
   3f1ee2a9:aion/ledger.jsonl | wc -l` → 1 (só o open). A linha danglou
   27 min não-commitada até o commit `a9cbf48e` (21:58:18), feito FORA
   desta sessão de agente (nenhum terminal desta sessão ativo no horário;
   autoria git idêntica não distingue). Classe: **mecanismo mal ordenado**
   + eco da árvore-compartilhada do ouroboros. Incident satélite próprio
   (interage_com).
3. **Auto-direção sem baseline de prioridade auditável**: o backlog de 5
   anéis foi ordenado pelo próprio executor por "leverage de negociação"
   sem critério mecânico nem aprovação do dono — se a ordem estiver errada,
   o teto de 5 anéis queima nos itens errados. Classe: **protocolo** (a
   ordenação está registrada em `aion/BACKLOG.md`, auditável a posteriori,
   mas nada valida a priori).
4. **Obrigatoriedade do runner é protocolo**: nada impede o executor de
   commitar por fora do `ring.sh` (sintoma observado por construção, não
   por violação — nesta sessão o protocolo segurou). Mesmo elo fraco
   apontado na causa raiz do ouroboros, um nível acima: o mecanismo agora
   existe, mas aderir a ele ainda é disciplina.

## Causa raiz

**Mecanizar o anel não mecaniza o LOOP.** O `ring.sh` converteu em código as
proteções de UM anel (teto, oráculo, contrato, commit) — e funcionou. Mas a
promessa do modo é a sequência de anéis, e a continuidade entre anéis
(despertador, retomada, percepção de morte) continua 100% protocolo +
infraestrutura de sessão que já tinha 3 incidents no mesmo dia. O elo mais
fraco migrou do anel para o intervalo entre anéis.

## Regras candidatas para a v4

CONVERGENTES (reforçam regra já proposta por incident irmão):

1. **Runner de anel com ledger no core** (= regra 1 do ouroboros, regra 1 do
   pythia; 3ª sessão a precisar). Novidade do aion: o piloto de workdir
   custou 261 linhas de bash e produziu o primeiro ledger não-vazio —
   viabilidade provada. Promover para `bin/oracfit ring open|close` COM a
   correção transacional do incident satélite (close grava ledger antes do
   commit e o commit o inclui; pós-condição: `git status --porcelain` limpo
   nos paths do modo). Cobre sintomas 2 e 4. Custo: portar script existente.
2. **Critic fresco obrigatório para anel de código** (= regra 4 do pythia).
   Evidência adicional: 4/4 achados do run vieram do critic fresco; 0 da
   autoauditoria quente; 0 do oráculo — e um dos achados (data UTC) é
   invisível a oráculo por construção. Custo: 1 subagent por anel.
3. **Wake/heartbeat de god mode NUNCA em terminal de sessão** (= regra 4 do
   ouroboros, forma específica). Evidência: 101,6s de vida; 4ª ocorrência
   da classe em 24h. Mecanismo: launchd/nohup com pidfile + arquivo de
   sinal que o host consome ao acordar; relançamento idempotente. Custo:
   plist de ~10 linhas ou nohup + watch-file.

NOVAS (evidência só desta sessão):

4. **Lint de claim de modo no registro**: modo cujo diferencial DECLARADO
   na description depende de componente sem mecanismo correspondente não
   registra — e "limitação declarada" no yaml não conta como mitigação.
   Evidência: o `aion.yaml` prometia perpetuidade auto-dirigida, declarava
   a fragilidade do despertador de sessão, e ela o matou aos 102s — a
   declaração serviu de auto-absolvição, não de proteção. Mecanismo: check
   no load do modo cruzando claims (auto-direção/perpetuidade/watchdog)
   com uma lista de mecanismos presentes (wake out-of-session, runner de
   anel, etc.). Custo: tabela de claims→mecanismos + validação de yaml.
5. **Série de calibração previsão×real da nota do dono**: todo veredito de
   god mode grava `owner_score_pred` no ledger (aion já grava: 1 entrada);
   a v4 adiciona o comando para o dono registrar a nota REAL pareada ao
   anel. O delta acumulado calibra o critic e transforma o incident
   "aprovou 4 ciclos e o dono deu 3.72" de anedota em métrica. Custo:
   1 subcomando de ledger + 1 campo.

## Evidência preservada

- Modo e profile: `~/oracfit/core/modes/aion.yaml`,
  `~/oracfit/core/critic-profiles/aion-comprador.md`, `~/oracfit/docs/modes/aion.md`.
- Mecanismo: `~/relay-juggler/aion/ring.sh` (261 linhas), `aion/BACKLOG.md`,
  `aion/ledger.jsonl` (2 linhas), `~/oracfit/ledger/ledger.jsonl` (2 linhas
  `"mode": "aion"`).
- Anel fechado: commits `82c59a84` (build) e `3f1ee2a9` (checkpoint) na
  branch `demo/neural-loop` do relay-juggler; `CHECKPOINTS.md` (exits e
  durações do oráculo); `aion/verdicts/RING-1.json` (APPROVED, 4.6, 4
  findings); `aion/notes/RING-1.md` (refino e achados aceitos).
- Morte do despertador: `~/.cursor/projects/Users-mini-relay-juggler/terminals/844673.txt`
  (status aborted, started 00:31:41.196Z, ended 00:33:22.812Z).
- Commit externo varrendo o ledger: `a9cbf48e` (21:58:18 -0300, 1 insertion
  em `aion/ledger.jsonl`); `git show 3f1ee2a9:aion/ledger.jsonl | wc -l` → 1.
- Critic fresco: subagent da sessão (veredito também em disco, path acima).

## O que este incident PROVA pra v4

1. O runner de anel mecânico é barato e funciona (261 linhas, ledger
   não-vazio pela primeira vez em god mode) — a regra 1 do ouroboros/pythia
   sai de proposta para piloto validado, faltando a correção transacional.
2. Mecanizar o anel não basta: a CONTINUIDADE entre anéis é o novo elo mais
   fraco, e é infraestrutura (wake out-of-session), não julgamento.
3. Declarar limitação em yaml não protege nada — claims de modo precisam de
   lint mecânico contra os mecanismos realmente presentes.

## Pode acontecer de novo?

Sim, determinística e imediatamente: qualquer god mode auto-dirigido que
armar o próximo anel em terminal de sessão morre na primeira reciclagem da
sessão (4 ocorrências da classe em 24h), e qualquer `ring close` com a
ordenação atual volta a deixar o ledger órfão de commit. Ambos têm correção
mecânica de custo baixo (regras 3 e 1/satélite).
