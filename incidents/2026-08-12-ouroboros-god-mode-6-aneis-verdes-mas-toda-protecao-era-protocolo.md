---
id: 2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo
titulo: OUROBOROS (god mode v3.5) fechou 6 anéis com critic pegando 3 falhas graves — mas ledger vazio, oráculo móvel, vigia e cadeia-fonte mortos com a sessão provam que TODA proteção era protocolo, não mecanismo
data: 2026-08-12
recorrivel: sim
regra: nao — 7 regras candidatas para a v4 no corpo (host-mode sem contabilidade mecânica é a causa raiz comum)
status: aberto
interage_com: "core/modes/demiurgo.yaml (god mode irmão, oráculo congelado)"
interage_com: "2026-08-11-t3-judge-biggest-gap-vazio-max-iterations-20-loop-patologico"
interage_com: "2026-08-11-critic-sem-teto-trava-stage-e-run-morre-sem-run-finished"
interage_com: "2026-08-12-servidor-demo-morre-quando-a-sessao-do-s"
interage_com: "2026-08-12-dispatch-de-shell-de-agente-morre-com-o-"
interage_com: "2026-08-11-vision-gate-decorativo-run-passa-com-verdict-rejected"
---

# OUROBOROS — postmortem do god mode v3.5 (sessão TCC/prêmio-Nobel)

## Contexto

Teste da v3.5: modo `ouroboros` (`core/modes/ouroboros.yaml`) — TODOS os
papéis (spec, execução, judge, critic, refino, auditoria) no próprio frontier
model, em contextos frescos por papel (Task subagents do Cursor/Fable).
Nenhum dispatch a modelo free. Alvo: evoluir `~/isef-torcedores` (TCC de
Psicologia, índice ISEF) + `~/clubsurf` (pipeline-fonte Wikidata/Wikipedia)
no automático até o humano revisar checkpoints.

Resultado bruto: **6 anéis fechados (CP-1..CP-6) em ~7h**, dois repos
commitados, base sintética → base real (1731 linhas clube×ano, 133 clubes,
1959–2025, títulos de liga/copa/estaduais via Wikidata P1346, 46
rebaixamentos reais). Oráculos mecânicos: 30+16+19 checks verdes.

## O que funcionou (e é a tese do modo)

O **critic em contexto fresco com perfil `ouroboros-nobel`** pegou 3 falhas
que o executor sozinho não viu — todas empíricas, nenhuma estilística:

1. **NOBEL-01 REJECTED**: 17/55 campeões derivados errados (tabela de fase
   parseada como classificação final na era de mata-mata). Correção na raiz:
   campeão via P1346, não `position=1`.
2. **NOBEL-03 REJECTED**: efeito plantado no Grit-S era CANCELADO pelos
   itens reversos da escala — o seed fixo passava por ruído (11/12 seeds
   falhavam). Achado de qualidade rara: o oráculo estava verde e MENTIA.
3. **NOBEL-05 REJECTED**: perda SILENCIOSA de vitórias de copa (São Paulo
   2005, Vasco 2000) porque temporadas faltavam na fonte — o executor tinha
   declarado a base como completa.

Em todos, o veredito veio com `biggest_gap` preenchido e citação de
artefato; o refino convergiu em ≤2 rodadas. O critic também pegou deriva de
alegação: executor escreveu "282 perdidas" quando o artefato dizia 215+67 —
recontagem independente, não confiança no relato.

## Como as outras implementações de god/loop mode se saíram (comparação)

| Implementação | Proteção central | Resultado |
|---|---|---|
| `demiurgo` (tdah-loops-repo, branch demiurgo) | Oráculo CONGELADO (sha256 + freeze_check executável), 1 hipótese/iteração, reverte regressão, parada por convergência | Convergiu limpo: média 8.1→9.8 em 4 checkpoints, zero reversão, parou por convergência (não por teto) |
| `content_factory` (CrewAI multi-modelo) | `safety_ceiling: 4` no yaml | Loop patológico: T3-JUDGE com `biggest_gap: ""` 5x, CrewAI `max_iterations: 20` invisível ao oracfit, morto na mão após 1h19 |
| vision-gates (travelview/scentsurf/<host-local>) | Gate visual por prompt | Gate decorativo (run passou com verdict REJECTED), vereditos confabulados em fullpage downscale, barra inalcançável |
| `ouroboros` (esta sessão) | Oráculo mecânico soberano + critic fresco com profile | 6 anéis verdes, 3 rejeições legítimas — mas ver "o que quebrou" |

Síntese da comparação: o demiurgo é o único cujas proteções são
ESTRUTURAIS (script de congelamento, git revert), e foi o único sem
incidente. Só que oráculo congelado funciona para artefato fechado (uma
skill, 8 casos) e é INCOMPATÍVEL com alvo cuja fonte de dados cresce em
background: no ouroboros a Série B entrou na fonte no meio do run e um
check do oráculo (vacuidade do rebaixamento) precisou virar CONDICIONAL —
com trave congelada, o anel teria travado num check obsoleto.

## O que quebrou nesta sessão (sintomas, com evidência)

1. **Cadeia-fonte e vigia morreram JUNTOS com a sessão de terminais do IDE**
   (21:19:31Z, mesmos ended_at): a cadeia 20k-clubes morreu a 2250/3265
   temporadas (69%) e o watcher que despertaria o anel NOBEL-07 morreu 80s
   depois de lançado (`status: aborted`, exit unknown). Três horas sem
   ninguém perceber. Mesma classe dos incidents "servidor-demo-morre" e
   "dispatch-de-shell-de-agente-morre" — terceira ocorrência EM UM DIA.
2. **Vigia com falso-positivo de padrão**: a 1ª versão casou `CHAIN-GREEN`
   no CABEÇALHO do arquivo de terminal (o `command:` continha o próprio
   `echo "[CHAIN-GREEN]"`) e saiu em 147ms. Corrigido com âncora
   `^\[CHAIN-GREEN\]` — mas a correção foi julgamento do executor, nada
   mecânico impedia o falso despertar.
3. **Commit paralelo varreu arquivos de outro agente**: commit `af029f7`
   (pipeline, `git add -A`) levou junto arquivos do subagent web que
   trabalhava na mesma árvore — o subagent reportou "eu não commitei nada".
   Árvore compartilhada entre agentes concorrentes sem pathspec = commits
   com autoria mentirosa.
4. **Ledger vazio**: `rg -c ouroboros ledger.jsonl` → zero. O modo roda
   como PROTOCOLO do host (model_ref `frontier-host` não é dispatchável),
   então nada passa por `bin/oracfit`: `safety_ceiling`, `run_attempt_budget`
   e vereditos não têm contabilidade mecânica. CHECKPOINTS.md é escrito à
   mão PELO PRÓPRIO EXECUTOR — autofiscalização.
5. **Oráculo móvel**: o executor editou o próprio oráculo entre anéis
   (21→30 checks). Todas as edições desta sessão APERTARAM ou acompanharam
   a realidade (check condicional da vacuidade) — mas nenhum mecanismo
   distingue apertar de afrouxar. O demiurgo proíbe por sha256; o ouroboros
   confia no critic notar.

## Causa raiz (comum aos 5 sintomas)

**A v3.5 só tem mecanismos (ledger, tetos, timeout, freeze, watchdog) para
modos DISPATCHÁVEIS. Quando o host frontier é o executor (god mode), o yaml
vira documentação e toda proteção degrada para protocolo + boa-fé do
próprio modelo que está sendo protegido.** O run deu certo porque o
protocolo foi seguido; os 5 sintomas mostram onde ele quebraria sem sorte
ou sem disciplina.

## Regras candidatas / sugestões para a v4

1. **Runner de host-mode (`bin/oracfit ring open|close`)**: mesmo com o
   host executando, abrir/fechar anel grava no ledger.jsonl (ring id,
   oracle_exit real, veredito do critic, commit hash, contagem contra
   `safety_ceiling`). Checkpoint humano continua em .md; a contabilidade
   deixa de ser manuscrita.
2. **Oráculo semi-congelado com guarda de monotonicidade**: diff do oráculo
   entre anéis auditado por script — ADICIONAR check é livre; remover ou
   relaxar exige bloco `DECLARACAO:` no checkpoint + aprovação explícita do
   critic no mesmo anel. (Meio-termo entre o sha256 do demiurgo e o oráculo
   móvel do ouroboros; resolve fonte-que-cresce sem liberar a trave.)
3. **`biggest_gap` como contrato falha-fechado também no host-mode**: o que
   salvou o ouroboros do loop do content_factory foi o critic-profile
   (prompt). Virar mecanismo: veredito ≠ APPROVED sem gap não-vazio = falha
   de estágio que conta no teto (lição direta do incident do T3-JUDGE).
4. **Primitiva "anel bloqueado por condição" fora da sessão do IDE**:
   watch-file/despertador via launchd/setsid com relançamento idempotente e
   padrão OBRIGATORIAMENTE ancorado (sintomas 1 e 2). Processo-dependência
   de longa duração (cadeia de dados, servidor) nunca em terminal de
   sessão. **Testado na sequência deste incident: `nohup ... &` NÃO basta —
   o harness do agente mata o grupo de processos ao fim da chamada (a
   cadeia relançada morreu em <60s). Só double-fork + `os.setsid()`
   sobreviveu.** A v4 deveria dar um `bin/oracfit daemon <cmd>` que faz o
   double-fork certo, escreve pidfile e loga em arquivo próprio.
5. **Isolamento de árvore por agente**: worktree git por agente concorrente
   ou proibição mecânica de `git add -A`/`-u` em sessão multi-agente
   (pre-commit hook que exige pathspec explícito quando há lockfile de
   outro agente).
6. **`claims-check` mecânico**: extrair números do resumo/checkpoint do
   executor e procurá-los nos artefatos citados; divergência = anel não
   fecha. (O critic fez isso na mão em 2 anéis; barato de automatizar.)
7. **Híbrido de custo**: anéis mecânicos (coleta, re-run de cadeia, export)
   não precisam de frontier — executor pode descer para tier free com
   oráculo igual, mantendo critic/judge frontier. O god mode puro custa
   frontier em TODAS as pontas e a maior parte do tempo de parede desta
   sessão foi espera de I/O de pipeline.

## Evidência preservada

- Checkpoints legíveis: `~/isef-torcedores/CHECKPOINTS.md` (CP-0..CP-6).
- Modo e perfil: `core/modes/ouroboros.yaml`, `core/critic-profiles/ouroboros-nobel.md`.
- Vigia falso-positivo: terminal 438820 (exit 0 em 147ms, header casado).
- Morte conjunta: terminais 438818 (cadeia, aborted 21:19:31.066Z,
  2250/3265) e 438821 (vigia, aborted 21:19:31.062Z); DB confirma 1015
  temporadas não parseadas (`SELECT parsed, COUNT(*) FROM seasons`).
- Commit com autoria varrida: `clubsurf@af029f7` (relato do subagent web).
- Ledger sem entradas do modo: `ledger/ledger.jsonl`.
- Comparativo demiurgo: `~/tdah-loops-repo/checkpoints/checkpoint-0{0..3}.md`.

## O que este incident PROVA pra v4

1. O valor do god mode é real e mensurável: 3 rejeições do critic com
   achados que oráculos verdes não viam (a rejeição do NOBEL-03 salvou a
   validade estatística do projeto inteiro).
2. O modo sobrevive HOJE por disciplina de protocolo — as 5 quebras são
   todas de mecanismo ausente, nenhuma de julgamento do frontier.
3. Congelar tudo (demiurgo) e mover tudo (ouroboros) são extremos; a v4
   precisa do meio-termo auditável (regra candidata 2).

## Pode acontecer de novo?

Sim — em qualquer sessão god mode com dependência de processo longo, a
morte silenciosa da sessão de terminais engole o run (3ª ocorrência hoje,
4ª contando a tentativa de relançar com nohup DURANTE este incident).
E qualquer host-mode continua invisível ao ledger até a regra 1 existir.
A cadeia-fonte foi relançada como daemon setsid (double-fork, log em
`~/clubsurf/data/chain-restart.log`, pid via pgrep) logo após este
incident; NOBEL-07 reabre quando ela fechar.
