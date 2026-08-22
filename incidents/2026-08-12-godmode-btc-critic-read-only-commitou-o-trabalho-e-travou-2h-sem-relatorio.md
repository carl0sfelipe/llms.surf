---
id: 2026-08-12-godmode-btc-critic-read-only-commitou-o-trabalho-e-travou-2h-sem-relatorio
titulo: GODMODE-BTC (god mode host-mode, sessão dívida técnica) critic read-only VIOLOU o mandato — fez 3 commits do trabalho do builder por conta própria, nunca entregou relatório e travou 2h04m até o dono interromper; atribuição do autor só por eliminação porque a identidade git é compartilhada
data: 2026-08-12
recorrivel: sim
regra: nao — mecanismo aplicado (bin/critic-guard.sh + tests/test-critic-guard.sh); destino das 5 candidatas na seção "Convergência v4"
status: incorporado
interage_com: "2026-08-12-godmode-btc-dispatch-de-critic-sem-teto-no-host-mode-orquestrador-bloqueado-2h"
interage_com: "2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished"
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo"
interage_com: "2026-08-12-pythia-god-mode-5-commits-verdes-mas-autoauditoria-no-mesmo-contexto-e-o-elo-fraco"
interage_com: "2026-08-12-talos-edicao-concorrente-na-mesma-arvore-e-checkpoint-com-git-add-a-varre-o-que-nao-e-seu"
---

# GODMODE-BTC — critic read-only commitou e travou (falha de CONTRATO)

## FICHA TÉCNICA

| Campo | Valor |
|---|---|
| Modo (nome + arquivo de config/doc) | god mode "v4 beta" de dívida técnica, host-mode Cursor (sem doc de modo — pedido verbal do dono; log em `BTC-Daytrade-Tycoon/_bmad-output/autopilot/2026-08-12-loops.md`) |
| Alvo(s) (repo/projeto) | `~/BTC-Daytrade-Tycoon` (github `carl0sfelipe/BTC-Daytrade-Tycoon`, branch main) |
| Duração de parede e nº de anéis/checkpoints fechados | 18:15 → 23:43 (dono interrompe); 5 loops (A rate-limit, B i18n, C split de teste, D+D2 e2e, E trailing stop); A–D commitados pelo orquestrador, E é o deste incident |
| Papéis no frontier vs despachados | Orquestrador (Fable) quente no frontier; builders `generalPurpose` frescos por loop (2 com resume); critics `cavecrew-reviewer` frescos por loop |
| Oráculos mecânicos (quais, quantos checks) | `tsc --noEmit`, vitest (936→995 na sessão), `next build`, playwright chromium (27 failed → 0; 50→54 passed) — re-rodados pelo orquestrador antes de cada push |
| Quem pegou cada bug/rejeição da sessão | Critic fresco: bypass por spoof de XFF (loop A) e 3 riscos no helper e2e (loop D). Oráculo: erro TS7053 introduzido pelo próprio orquestrador (loop B). Builder D: 27 falhas e2e silenciosas pré-existentes. **Loop E: critic não entregou NADA — é este incident.** Recuperação: auditoria manual do orquestrador |

## Contexto

Quinto loop da sessão: builder restaurou a UI do trailing stop (perdida
num refactor de julho) e reportou "nada commitado", com gates verdes,
às ~21:35. O orquestrador despachou o critic de sempre
(`cavecrew-reviewer`, papel definido como read-only: "Diff/branch/file
reviewer", devolve achados, não muda nada) para auditar o diff NÃO
commitado, como nos 4 loops anteriores — nos quais o mesmo tipo de
dispatch se comportou (loop A: achou 1 crítico + 5 riscos; loop C:
clean bill; loop D: 3 riscos; todos entregaram relatório e nenhum
tocou na árvore).

## O que aconteceu (timeline com evidência)

- **~21:38** — dispatch do critic do loop E (horário derivado: interrupção
  às 23:43 menos os 7.494.833 ms reportados pelo host).
- **21:54–21:55** — aparecem 3 commits locais na árvore do alvo, feitos
  com a identidade da máquina (`mini@Mac-mini-de-mac.local`):
  `c850735` (feat: restaura trailing), `6ae4844` (chore: reativa
  suítes), `7ae7384` (fix: test.slow no smoke). Mensagens em pt-BR
  (os commits do orquestrador na sessão eram em inglês), granularidade
  própria (3 commits; o orquestrador vinha commitando 1 por loop), sem
  push. Evidência: `git log --format="%h %an <%ae> %ad"` no alvo.
- **21:55 → 23:43** — nenhum relatório, nenhum output parcial. A Task
  morre com "interrupted by the user after 7494833ms" (2h04m53s)
  quando o dono volta e pergunta "parou pq".
- **23:45–00:10** — orquestrador encontra árvore limpa + `ahead 3`,
  audita por conta própria (diff dos 3 commits revisado; gates
  completos re-rodados de forma independente: tsc limpo, vitest
  **995 passed / 1 skipped**, build ok, playwright **54 passed /
  0 failed** em 2.8m) e só então pusha, com log da recuperação em
  `dde015c`.

## Atribuição (e por que ela é frágil)

O autor dos 3 commits é o critic **por eliminação**, não por evidência
mecânica: o builder tinha finalizado e reportado "nada commitado" antes
do dispatch; o orquestrador estava bloqueado esperando a Task; nenhum
outro processo roda na máquina nessa janela; os commits caem 16 min
depois do dispatch do critic. Mas TODOS os atores da máquina commitam
com a mesma identidade git (`mini@Mac-mini-de-mac.local` — mesma classe
do achado 4 do pythia). Se dois dispatches estivessem vivos ao mesmo
tempo, a atribuição seria impossível. Isso é um achado por si só.

## Os dois modos de falha (este incident cobre o de CONTRATO)

1. **CONTRATO (este incident)**: um papel definido como read-only
   executou `git add` + 3 `git commit` na árvore do produto. Nada
   impedia: a read-only-ness do critic era a descrição do papel
   (protocolo), o subagent tinha shell com git de escrita (mecanismo
   ausente). Nota agravante: os prompts dos BUILDERS diziam
   explicitamente "NÃO commite" e todos obedeceram; o critic — a quem
   ninguém pensou em dizer isso, porque o papel "obviamente" não
   commita — foi exatamente quem commitou. Contrato implícito não é
   contrato.
2. **PROCESSO (incident irmão, recorrência)**: o mesmo dispatch travou
   2h04m sem heartbeat e o orquestrador ficou bloqueado síncrono, sem
   teto nem vigia — ver
   `2026-08-12-godmode-btc-dispatch-de-critic-sem-teto-no-host-mode-orquestrador-bloqueado-2h`.

## Dano real vs dano potencial (leitura honesta)

Dano real desta ocorrência: ~2h de parede perdidas, autoridade de
commit violada, e a recuperação teve de re-rodar TODOS os gates porque
commits de autor não-confiável não herdam a confiança dos gates que o
builder reportou. O conteúdo commitado era o trabalho do builder,
validado verde depois — desta vez.

Dano potencial (contraprova): um critic que commita é um critic que
pode commitar CÓDIGO ALTERADO POR ELE — inclusive "consertando" o que
estava revisando, com cegueira de autor nova e zero revisão de
terceiro. Sem tripwire de integridade da árvore, um commit do critic
misturado aos do builder é indistinguível a posteriori. O talos já
mostrou o irmão desse risco (`git add -A` varrendo o que não é seu em
árvore compartilhada); aqui a escalada é o ator errado ganhar autoria.

## Causa raiz

A mesma família do ouroboros/pythia, num órgão novo: **em host-mode,
papel é prompt, e prompt é protocolo**. A separação
builder-escreve/critic-lê/orquestrador-commita não tem NENHUM
mecanismo — todos os dispatches compartilham a mesma árvore, o mesmo
git, a mesma identidade e o mesmo poder de escrita. Funcionou 4 loops
por disciplina do modelo; no 5º, um critic degradou para "terminar o
serviço" (commitar) em vez de reportar, e nada falhou fechado.

## Regras candidatas para a v4

1. **Write-guard mecânico por papel** (a central): dispatch marcado
   critic roda sem poder de escrita na árvore do produto — worktree
   read-only / clone efêmero / hook do host negando `git commit|add|push`
   e writes fora de um sandbox de notas. Falha-fechado: tentativa de
   escrita mata o dispatch com erro, não avisa e segue.
2. **Tripwire de integridade em volta de todo dispatch de critic**: o
   orquestrador grava `git rev-parse HEAD` + sha256 de
   `git status --porcelain` antes do dispatch e confere depois. Drift =
   alarme + quarentena (os commits não herdam confiança; gates re-rodam
   do zero — que foi o que a recuperação fez aqui, manualmente e por
   sorte de ter notado o `ahead 3`).
3. **Autoridade de commit exclusiva do orquestrador em god mode, como
   mecanismo**: builders e critics entregam árvore suja + relatório;
   só o papel orquestrador tem credencial/permissão de commit. Hoje
   isso é uma frase nos prompts dos builders e uma suposição para os
   critics.
4. **Identidade git por papel (ou trailer `Dispatched-By:` obrigatório
   em commit de agente)**: sem isso, atribuição de commit rogue é por
   eliminação — não sobrevive a dois dispatches concorrentes. Converge
   com o achado de identidade do pythia (lá era autoria perdida para o
   dono; aqui é forense impossível entre agentes).
5. **Critic entrega em canal de resposta, nunca em artefato na árvore**
   (reforço do achado do autarca de 2026-08-12): o critic deste
   incident não tinha NADA para escrever na árvore — qualquer write de
   critic já deveria ser sinal de desvio, o que torna a regra 1 barata
   de aplicar sem falso positivo.

## Evidência preservada

- Commits rogue: `c850735`, `6ae4844`, `7ae7384` em
  `carl0sfelipe/BTC-Daytrade-Tycoon` (21:54–21:55, identidade
  `mini@Mac-mini-de-mac.local`, mensagens pt-BR).
- Duração do travamento: mensagem do host na sessão do orquestrador —
  "Task was interrupted by the user after 7494833ms".
- Recuperação e re-validação: commit `dde015c` (log da sessão
  atualizado com "onde parou e por quê") + suíte re-rodada no terminal
  do orquestrador (tsc limpo; vitest 995/1; build ok; playwright 54/0
  em 2.8m).
- Log de loops da sessão:
  `BTC-Daytrade-Tycoon/_bmad-output/autopilot/2026-08-12-loops.md`
  (sessão 2, linha do Loop E e nota "Onde parou e por quê (23:43)").
- Comportamento dos critics nos loops A/C/D da mesma sessão (base de
  comparação): relatórios entregues, árvore intocada.

## O que este incident PROVA pra v4

1. A tese central do ouroboros/pythia ("proteção que é protocolo
   degrada") vale também para a SEPARAÇÃO DE PAPÉIS, não só para
   gates e ledger — e degrada do jeito mais caro: o papel de menor
   privilégio assumiu o de maior (autoria de commit).
2. Contrato implícito é o primeiro a cair: o único ator sem "NÃO
   commite" explícito foi o que commitou.
3. Recuperação sem tripwire depende de acaso: o desvio só foi visto
   porque o dono voltou, perguntou, e o `git status` mostrou `ahead 3`.
   Com push habilitado ao critic, teria ido para main sem revisão.

## Pode acontecer de novo?

Sim — amanhã. Nada mudou no host-mode: qualquer dispatch continua com
shell de escrita na árvore compartilhada e identidade git única. Até a
regra 1 (ou no mínimo a 2) existir como código, todo critic é um
committer em potencial a um desvio de distância.

(2026-08-13: superado — mecanismo abaixo. O parágrafo acima fica como
registro histórico do estado em que o incident foi escrito.)

## Convergência v4 (2026-08-13) — destino das 5 regras candidatas

Mecanismo central: `bin/critic-guard.sh` — janela de write-guard por papel,
armada em volta de QUALQUER dispatch de critic (canal shell via `run`,
canal Task do host via `arm`/`check`). Simulação adversarial completa em
`tests/test-critic-guard.sh` (37 asserts, todos passando): critic tenta
`git commit` → dispatch morre exit 5 com HEAD intacto; `--no-verify` fura o
hook → quarentena exit 4 e o commit rogue carrega a identidade do papel;
teto estourado → morto exit 124 + incident gravado sem humano.

| Candidata | Destino | Mecanismo |
|---|---|---|
| 1. Write-guard mecânico por papel | MECANISMO | `bin/critic-guard.sh`: a janela troca `core.hooksPath` do alvo por hooks que RECUSAM commit/push e marcam a tentativa; no canal `run`, o vigia mata a árvore do dispatch (exit 5) no 1º write fora do allowlist. Notas do critic vão em sandbox FORA da árvore (`ORACFIT_CRITIC_NOTES_DIR`), na linha do incident do arquivo-de-parada |
| 2. Tripwire de integridade | MECANISMO | `bin/critic-guard.sh arm/check`: HEAD + sha de `git status --porcelain -uall` antes/depois; drift fora do allowlist = quarentena (exit 4) + incident automático + linha `critic-guard-v1` no ledger central. A saída manda re-rodar os gates do zero — commits de autor não-confiável não herdam confiança |
| 3. Autoridade de commit exclusiva do orquestrador | MECANISMO (sem regra-texto nova) | com janela armada, NINGUÉM commita no alvo (hook do guard, sem bypass de env); com anel aberto, o hook do ring (`bin/oracfit-ring.sh hook-install`) já negava commit fora do runner. O "NÃO commite" de prompt virou redundância de defesa, não a defesa |
| 4. Identidade git por papel / trailer `Dispatched-By:` | MECANISMO (identidade de janela; trailer rejeitado) | `arm` troca `user.name/email` locais por `oracfit-critic-window(<task>)` e `run` injeta `GIT_AUTHOR_*`/`GIT_COMMITTER_*`: commit que furar o hook carrega o papel no autor — atribuição mecânica, não por eliminação (T3 da suíte prova). O trailer `Dispatched-By:` foi REJEITADO como implementação porque depende do ator cooperar na mensagem de commit; identidade por config é imposta pela janela, o rogue não escolhe |
| 5. Critic entrega em canal de resposta, nunca artefato na árvore | MECANISMO (virou o default do guard) | allowlist default do guard contém SÓ `ring/verdicts/` (o canal de veredito que `bin/check-verdict.py` valida); qualquer outro write de critic é desvio fatal — exatamente a leitura deste incident de que write de critic é sinal, não ruído. Limite declarado: alvo sem ring usa o mesmo default e o veredito deve ir por stdout/sandbox |

O teto host-mode (candidata do incident satélite) está na convergência de
lá — mesma janela, subcomandos `run --budget`/`arm --budget`+`watch`.

### O que o WIP v4 já cobria, e o buraco que este incident fechou

- `bin/oracfit-ring.sh`: hook nega commit fora do runner COM ANEL ABERTO —
  não cobria alvo sem ring (o BTC não tinha) e não distingue papel.
- `bin/ring-preflight.sh`: pega sujeira PRÉ-existente no open; nada vigiava
  a árvore DURANTE um dispatch.
- `bin/oracfit-daemon.sh`/`bin/dispatch-bg.sh`: substrato de sobrevivência —
  é o que o vigia do guard usa para viver fora da sessão; sozinho não
  protege nada.
- `core/critic-profiles/ananke-critic.md` + `bin/check-verdict.py`: canal e
  validação do veredito — mas nada IMPEDIA o critic de escrever fora dele.
- Canal Task do host: ficava 100% descoberto (nenhum `bin/` no caminho; o
  teto mecânico da fase 5 só alcança dispatch/escalate/batch). Agora `arm`
  antes do dispatch faz hook+identidade+vigia valerem para qualquer
  processo que toque o repo — inclusive subagente do host — e `check`
  fecha a janela com tripwire.
