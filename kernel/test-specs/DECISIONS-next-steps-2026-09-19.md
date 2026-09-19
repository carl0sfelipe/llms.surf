# Decisions — próximos passos após A–E (Fable como CTO, BMAD tier:expensive, 2026-09-19 21:30 UTC)

Forma deste record: a do CTO em `docs/research/bmad-tiers-2026-09-19.md`
— entrada por ponteiros, saída em prosa estruturada, sem código, número
com fonte, uma tentativa, uma pergunta ao dono. Quem executa cada item é
o tier nomeado; o oráculo de cada item é um comando, nunca este texto.

## Estado medido (fonte de cada número)

- Cinco PRs abertos, todos draft, nenhum mergeado: #3 `aa2e23b` → main;
  #4 `00fd2ba` → main; #5 `c374613` → #3; #6 `8d1acb8` → #5; #7 `8cbae42`
  → #6 (fonte: `gh pr view 3..7`).
- Oráculos P1 verdes em cada head: `cargo test --release` 0,
  `check-laws.sh` 0, `test-free-path.sh` 18/18 (#5) e 20/20 (#6),
  `test-kernel-test-mode.sh` 5/5 (#7), `check-saude.sh` 0 nos quatro
  (fonte: `reports/MERGE.md`, `T18.md`, `T19.md`, `T20.md`).
- CI `suites` vermelho em #3, #4, #5, #6 por `tests/test-gui.sh` (rótulo
  ausente em `hitl.html`) ou `tests/test-gui-todo.sh` (`gui.css` não
  servido); em cada head o evento irmão (push ou pull_request) do mesmo
  SHA passou `suites` (fonte: `gh pr checks`, logs dos runs 35469293241,
  35469392426, 35469575029, 35469655002). Em `main`, 6 dos 8 últimos
  pushes de `check-saude.yml` também falharam (fonte: `gh run list
  --branch main`). O rótulo existe no arquivo estático `panel/hitl.html`
  linha 210. Não é P1.
- `kernel/dispatch-policy/src/**` não mudou em nenhuma das cinco PRs.
- Medição D-INC3 passo 1 não existe: binário zcode ausente no cloud;
  `measure-home-relocation.sh` sai 3 sem inventar linha (fonte: PR #4).
- T08 e T10 têm Verdict FAIL pelo oráculo da bateria (`l3_cheap_order`
  vermelho em main @ `1425b9c`, pré-existente), não pela pergunta que
  respondem; T10 pontua 13/13 vetores em consumidor só-docs (fonte:
  `reports/T08.md`, `reports/T10.md`).
- Nenhuma linha com `kernel_shadow_diff` no ledger da árvore: o shadow
  ainda não viu tráfego real (fonte: `rg kernel_shadow_diff ledger/`).

## D-NEXT-1 — Ordem de merge: #3, depois #5, #6, #7; #4 a qualquer hora

A pilha é linear por construção (cada PR tem o anterior como base). #4 é
independente: só toca `adapters/zcode/**` e `bin/test-zcode-config-
integrity.sh`, rebaseado em `main`. O dono mergeia na ordem; nenhum
rebase entre eles é necessário porque os footprints são disjuntos (T18:
run-with-fallback/lib-free-credentials/ledger-finalize/test-free-path;
T19: os mesmos três arquivos, aditivo; T20: modos, dispatch-mode,
dispatch-stages, check-saude).

Rejeitado: mergear #7 direto em `main` (perde a ordem e o receipt de
cada oráculo); esperar a medição do zcode para mergear #4 (D-INC3 §3 já
diz que `restore` funciona nos dois casos; a medição só decide se o
default vira `overlay`).

## D-NEXT-2 — O flake de GUI vira incidente e mecanismo, fora da pilha P1

Fato: a mesma revisão passa e falha `suites` conforme o evento; a
asserção que falha lê uma página logo após o servidor subir. A casa já
tem o incidente irmão `2026-08-12-autarca-oraculo-verde-2x-no-mesmo-
minuto-aprovou-assercao-flaky` — verde duas vezes não prova nada.

Terceira ocorrência na mesma família, mesma hora: `tests/test-corte-
review.sh` T9b (`curl` em `corte.html` sem tentativa) vermelho no push de
#7 `8cbae42`, run 35469954265; o `suites` do evento pull_request do
mesmo SHA passou.

Mecanismo exigido, tier:cheap via `dispatch-mode` (footprint
`tests/test-gui.sh`, `tests/test-gui-todo.sh`, `tests/test-corte-review.sh`,
`incidents/`): a espera
de prontidão do servidor tem de sondar a própria página sob teste, não só
`home.html`/`todo.html`; cada `curl` de asserção ganha tentativa com
recuo; o oráculo da spec é cinco execuções consecutivas de cada suíte
com exit 0 (cinco, não duas, pelo incidente do autarca). Um incidente
novo em `incidents/` pelo fluxo `fluxos/incident/SKILL.md`, com o
`check-docs` e `test-site-honesty` atualizados para 115.

Este item não bloqueia D-NEXT-1: cada head já tem `suites` verde no
evento irmão, e o job não exercita nada que as cinco PRs tocam. Se a
proteção de branch exigir `suites` verde no evento pull_request, o dono
re-roda o job (`gh run rerun`) — não se afrouxa o gate.

Rejeitado: consertar o flake dentro de #3/#5 (fora do footprint
declarado das specs); marcar `test-gui*` como opcional no workflow (é a
cegueira que o HT1 de 2026-08-22 proibiu, ver comentário em
`.github/workflows/check-saude.yml`).

## D-NEXT-3 — Cutover `LLMS_KERNEL=on` por precondição, não por data

O default continua `off` até valerem, medidas no ledger do dono:

1. Toda linha com `kernel_shadow_diff` presente tem valor 0, e essas
   linhas cobrem um ciclo inteiro de Lineup (a unidade de D6.6 em
   `direction-kernel-rust-bend-lab-2026-09-19.md`; não fixo N de runs
   porque nenhuma fonte na árvore dá esse número — o dono fixa).
2. Qualquer linha com `kernel_shadow_diff` 1 vira, antes do cutover, um
   caso em `kernel/vectors/p1/cases.json` com `incident` apontando o
   ledger (README regra 1) — o diff é o achado, o vetor é o artefato.
3. `l3_cheap_order` verde em `main` (T08/T10 finding 1). Hoje verde na
   pilha (`cargo test --release` 0 em `aa2e23b`); permanece condição
   porque o cutover entrega ao binário a ordem da cadeia.

Mecanismo, tier:cheap: `bin/check-shadow-ledger.sh` lê o ledger, imprime
linhas em shadow, soma dos diffs e o intervalo de datas; exit 1 se soma
diferente de zero. Entra em `check-saude.sh` só quando existir linha em
shadow (padrão do bloco Fantasma). O cutover em si é um PR de uma linha
em `bin/run-with-fallback.sh` com o recibo desse script no corpo.

Como ligar o shadow no dia a dia do dono: exportar `LLMS_KERNEL=shadow`
no `env.sh` do adapter em uso, nada mais — T18 já re-emite o stderr do
kernel e serve o Python.

## D-NEXT-4 — E5 sai da primeira rodada real de `kernel_test`

Precondições: #7 mergeado; credenciais por arquivo (L4); máquina do dono
(o cloud só tem stubs — guardrail desta sessão). Rodar T01–T10 uma vez
cada por `oracfit run kernel_test <spec> p1-<ID>` com `KERNEL_TEST_ID`
correspondente. Teto: 10 specs × `max_attempts` 3 do YAML = 30
tentativas no pior caso (fonte: `core/modes/kernel_test.yaml`).

Saída que fecha D6.5: dez linhas em `.dispatch/ledger/mode.jsonl` com
`provider_efetivo`, `attempt`, `oracle_exit`. A leitura vai para
`kernel/BENCH.md` como tabela spec → tier → tentativas → veredito, com
o `run_id` de cada linha como fonte. Sem essas dez linhas, E5 continua
"não medido" — não se escreve taxa de fechamento em prosa.

Rejeitado: rodar a bateria com `tier:mid` para "garantir" verde (E5
pergunta exatamente o que o cheap fecha).

## D-NEXT-5 — BMAD: `dev_build.yaml` é `kernel_test` generalizado; nasce em `~/Work/bmad`

`bmad-tiers-2026-09-19.md` linha 33 define `kernel_test` como o
`dev_build` com a spec da bateria. A generalização (spec como input,
`command:` da própria spec como oráculo) e os dois oráculos de forma —
`spec.sh` para Winston e `decision-record.sh` para o CTO — moram na
casa do time, não neste repo. Este record é o primeiro insumo de
`decision-record.sh`: seções, sem bloco de código, números com fonte.
Se o oráculo do CTO reprovar este arquivo, a correção é aqui, não no
oráculo.

O que fica em llms.surf: nada até o BMAD pedir uma chave nova no
loader (`ALLOWED_STAGE` hoje já cobre `command`, `owner_question`,
`input`, `max_attempts` — suficiente para os três modos da tabela).

## D-NEXT-6 — Rust/Bend: D1–D7 inalterados; o próximo item da tabela D7 é o 3

Item 2 de D7 (P1 em Rust atrás da CLI atual, leis + vetores) está
entregue pela pilha desta sessão. Item 3 (E1/E2 do Bend, "duas tardes")
é o próximo, e T10 dá o pré-requisito medido: 13/13 vetores em consumidor
só-docs, com nove inferências código-apenas listadas como o que a spec
ainda não pina (findings 2–9). Antes do item 4 (P1 em Bend), essas nove
viram vetores ou frases na spec — senão o Bend acerta os vetores e erra
o produto. Sincronia de D5 começa a contar no dia em que `LAWS.bend`
existir.

Nada desta sessão altera D6: o gate do 2.0 continua com seis
precondições, e D-NEXT-4 é o caminho da quinta.

## D-SHIP — o MVP é esta estrutura; Bend sai do caminho crítico; bestmodel vem depois (dono, 2026-09-19 21:33 UTC)

Decisão do dono, na hora: Bend está imaturo demais para receber atenção
agora. O que se shipa é o llms.surf com a estrutura nova — leis em
`kernel/laws/`, vetores em `kernel/vectors/`, kernel Rust atrás da flag
— desenhada para uma migração futura possível, não iniciada. Com esse
MVP no ar, a prioridade seguinte é terminar de polir o bestmodel usando o
próprio llms.surf como ferramenta.

Efeito sobre D7: o item 3 (E1/E2 do Bend) deixa de ser o próximo e fica
sem data; D6 permanece como gate do 2.0, apenas não há trabalho de lab
agendado. Nada no produto passa a depender de Bend. O ativo de prontidão
para a migração continua sendo o mesmo de D5 — leis + vetores como spec
única — e a única obrigação que fica é a de D-NEXT-6: os nove achados de
T10 virarem vetor ou frase de spec, porque isso é qualidade da spec, não
trabalho de Bend.

O que "shipado" significa, verificável na árvore:

1. #3, #5, #6, #7 e #4 mergeados em `main` na ordem de D-NEXT-1.
2. `LLMS_KERNEL` default `off` no corte. O kernel shipa presente e
   observável (shadow), não decidindo. O cutover segue D-NEXT-3, depois
   do corte, quando o ledger do dono responder.
3. O flake de GUI de D-NEXT-2 consertado antes da tag — cortar release
   com `suites` vermelho é a classe do incidente do autarca. Cinco
   execuções consecutivas verdes das três suítes no SHA da tag.
4. `check-saude.sh` 0, `kernel gates` 0 e `suites` 0 no SHA da tag, os
   três recibos no corpo do release; `check-docs.sh` e
   `test-site-honesty.sh` com os números do corte (hoje 114 incidentes,
   21 modos, 37 suítes na pilha; 115 se o incidente do flake entrar).
5. Copy pública continua dizendo "degrau", nunca "provado" — risco 3 de
   `direction-kernel-rust-bend-lab-2026-09-19.md`.

Número de versão: fixado pelo dono em **4.1.0** (2026-09-19 21:36 UTC).
Corte em PR #9 (`cursor/release-4-1-0-3a81`, topo da pilha): conserto do
flake + incidente 115 + bump. Oráculos no SHA do corte: 5× consecutivas
das três suítes de GUI 0, `incident.sh audit` 0, `check-docs` 0,
`test-site-honesty` 0, `check-saude` 0.

Sobre bestmodel: continua vinculante não tocar PR #2, optimizer 1.0.1 e
L03A 355 até ordem contrária. O polimento passa a ser feito **por**
llms.surf — specs com footprint e comando de aceitação despachadas em
modo dev (a forma de `kernel_test`), com ledger. Pré-condição única para
qualquer trabalho de nuvem lá: write de `cursor[bot]` no repositório
bestmodel (sessão anterior). Sem isso, o polimento é na máquina do dono.

Rejeitado: E1/E2 do Bend antes do corte; cutover do kernel no mesmo
corte que o introduz; tag com `suites` vermelho "porque é flake".

## Fora deste record

bestmodel PR #2, optimizer 1.0.1, L03A 355 (vinculantes da sessão
anterior: não tocar). `~/Work/bmad` (sem acesso daqui). Qualquer
despacho de modelo real a partir do cloud.

## Pergunta ao dono (S8: uma, com garfo)

pergunta: `HOME` relocado funciona no zcode AppImage da sua máquina? (rode `adapters/zcode/measure-home-relocation.sh` do PR #4; ele imprime três linhas sim/não)
se sim -> PR de uma linha muda o default para `ZCODE_CONFIG_STRATEGY=overlay`, re-roda `bin/test-zcode-config-integrity.sh`, e o incidente 3 recebe as três linhas medidas.
se não -> `restore` permanece default, as três linhas vão para o incidente 3 como medição, e o `flock` + `trap` do PR #4 é a proteção definitiva.
