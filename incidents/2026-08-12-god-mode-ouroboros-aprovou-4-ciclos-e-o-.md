---
id: 2026-08-12-god-mode-ouroboros-aprovou-4-ciclos-e-o-
titulo: god mode ouroboros aprovou 4 ciclos e o dono deu 3.72 — vision gate em sessão mede correção, não classe de qualidade
data: 2026-08-12
recorrivel: sim
regra: mecanismo aplicado — bin/oracfit-ring.sh (ring score --real N: evento owner_score com delta previsão×real no ledger) + GUI HITL anti-âncora (bin/oracfit-panel-server.py, panel/hitl.html, rota hitl em bin/oracfit)
interage_com: "2026-08-12-ouroboros-god-mode-6-aneis-verdes-mas-toda-protecao-era-protocolo (postmortem gêmeo da MESMA v3.5, outra sessão: lá o buraco é mecanismo ausente no host-mode; aqui é eixo de julgamento errado + dono fora do loop — as duas listas de v4 se somam, não se sobrepõem)"
interage_com: reforça 49 (repetiu a classe no MESMO dia — Metro morto 2x + nohup morto); família do vision-gate (2026-08-12-barra-inalcancavel: juiz free sem sinal; aqui: juiz frontier COM sinal, mas no eixo errado); irmãos de modo: core/modes/ouroboros.yaml, core/modes/demiurgo.yaml, docs/modes/pythia.md
status: incorporado
---

# god mode ouroboros aprovou 4 ciclos e o dono deu 3.72 — vision gate em sessão mede correção, não classe de qualidade

Field test mais longo de god mode até agora: 3 sessões, 10 ciclos, 4 commits
(`~/primeiras-palavras`, app de fala para bebês, 12/08 16h-20h). Modo local
`oracfit/modes/ouroboros.yaml` — variante do core com vision gate = frontier
NA SESSÃO (primeira aplicação real da decisão do fundador de 12/08 ~14h30 em
um god mode completo). Este incidente registra o que o teste provou, o que
quebrou, e o que a v4 deve mudar.

## Sintoma

1. **O headline**: sessão 1 fechou 5 ciclos com TODAS as barras verdes
   (tsc + export + vision APPROVED + audit 0 CRITICAL, trilha em
   `~/primeiras-palavras/CHECKPOINTS.md`). O dono jogou no Ulefone e avaliou:
   **"foi de nota 1 para nota 3.72 apenas"** (barra declarada: 8). Quatro
   APPROVED consecutivos do juiz-em-sessão foram invalidados por uma frase
   do dono.
2. Na sessão seguinte, UMA troca de classe de arte (rosto SVG paramétrico →
   5 frames Pixar gerados por imagem com identidade consistente) moveu a
   qualidade percebida mais que os 4 ciclos de refino de parâmetro somados
   (evidência indireta: dono parou de reclamar do rosto e pediu para
   evoluir o resto; nota formal nova ainda pendente).
3. **Regra 49 repetida no mesmo dia em que foi escrita**: Metro/Expo morto
   2x em silêncio por limpeza de sessão do harness (17h05 e 17h40); tentativa
   de correção com `nohup + disown + supervisor em loop` morta segundos após
   "Tunnel ready" — exatamente o mecanismo que o incidente
   `2026-08-12-servidor-demo-morre-quando-a-sessao-do-s` (06h, poker-club-os)
   já tinha provado que não protege. O god mode não consultou o diário.
4. Vision gate quase julgou o artefato errado: porta 8081 compartilhada com
   `llama-server` (IPv4 loopback) fez o Playwright fotografar a web UI do
   llama em vez do VisemeLab. Detectado porque a imagem era obviamente outra
   aplicação — um screenshot superficialmente parecido teria sido julgado.
5. Flake de ferramenta no meio do run: `npx playwright` resolveu versão nova
   e perdeu o binário do Chromium (S3), parando o gate até `playwright
   install`.

## Causa

Cada sintoma tem causa própria (sem conflação):

1. **Critic profile mede o eixo errado.** O perfil local
   (`oracfit/critic-profiles/frontier-articulacao.md`) tinha 7 critérios,
   todos de CORREÇÃO articulatória ("lábios visivelmente pressionados",
   "língua visível no /l/"...). Elipses SVG bem parametrizadas satisfazem
   todos — e satisfizeram. Nenhum critério perguntava "esta arte é da CLASSE
   necessária para a barra declarada (nota 8, referência Ms. Rachel/Pixar)?".
   O juiz frontier TEM poder discriminativo (diferente do gemma free do
   incidente barra-inalcancavel): rejeitou C1 por defeito real, pegou bug real
   de escala web no PhotoFace e a Home que deixava o bebê iniciar sessão
   sozinho. Mas poder discriminativo no eixo de correção não transfere para o
   eixo de classe de qualidade — o loop `biggest_gap → refinar` só otimiza
   DENTRO da classe atual.
2. **Nota do dono não é métrica do loop.** O modo não tem `nota_alvo` nem
   registro de previsão do critic vs avaliação real. O critic nunca foi
   obrigado a prever "que nota o dono daria"; o primeiro ponto de calibração
   (previsto ≈aprovado/8, real 3.72) só existiu porque o dono voltou.
3. **Modo sem stage de infra + diário não consultado.** O yaml local tem
   stages de build/gate mas nenhum de saúde de serviços; o orquestrador
   relançou o servidor do jeito que a regra 49 (promovida às 06h do mesmo
   dia) já proibia. Correção que funcionou: LaunchAgent do macOS com
   KeepAlive (`com.<repo-cliente>.primeiras-palavras-expo`) — proteção mais forte que a
   da regra 49 (sobrevive à sessão do harness E ao app fechar).
4. **Gate sem sentinel de artefato.** O screenshot era julgado sem verificar
   que a imagem contém o artefato esperado; qualquer processo respondendo na
   porta vira "o artefato".
5. `npx` sem versão pinada resolve o pacote de novo a cada invocação.

## Correção aplicada

- `~/primeiras-palavras` (workdir): rosto trocado de classe (frames gerados,
  commits `a6631a4`, `2711c66`); servidor movido para launchd
  (`~/Library/LaunchAgents/com.<repo-cliente>.primeiras-palavras-expo.plist`);
  screenshots do gate passaram a usar `http://[::1]:8081` explícito (Metro
  ficou no IPv6, llama no IPv4) — workaround, não mecanismo.
- Este diário: incidente escrito; a comparação entre os 4 modos irmãos e as
  propostas de v4 ficam na seção abaixo (não existia doc consolidando o que
  cada god mode aprendeu).

## O que o field test PROVOU (não só o que quebrou)

Justiça com o experimento — em 10 ciclos:

- Juiz de visão frontier-em-sessão pegou 3 defeitos reais que nenhum juiz
  free articulou em runs anteriores (língua ilegível, crop de web, UX de
  co-play) — a decisão do fundador de 14h30 validada em god mode.
- Auditoria de código em contexto fresco por ciclo: 0 críticos entregues;
  achados verdadeiros em toda rodada (race de listener do expo-video, drift
  de timeline do crossfade, dose desonesta por clipe de vídeo).
- `biggest_gap` encadeou ciclos sem loop patológico (contraste: incidente
  t3-judge com 20 iterações); tetos respeitados (5/6, 1/1, 4/6).
- Checkpoint por ciclo funcionou como interface humana: o dono acompanhou
  por CHECKPOINTS.md sem abrir o chat.
- Geração de assets pelo frontier (imagens com referência de identidade) foi
  a maior alavanca de qualidade da história do projeto — capacidade que
  dispatch para executor free não tem.

## Comparação com os irmãos (o que cada um acerta que este não tinha)

| Modo | Mecanismo que este field test validou como necessário |
|---|---|
| `demiurgo` | Oráculo CONGELADO antes da 1ª iteração + regressão reverte + halt por convergência ("2 iterações sem ganho"). O ouroboros local deixou o mesmo modelo escrever o critério E o artefato — a trave era móvel, e de fato ficou no eixo errado sem ninguém perceber por 4 ciclos |
| `ouroboros` (core) | "Frontier julga, mas NÃO decide vitória — vitória é oracle_exit=0 + critic sem 🔴". A variante local deixou o vision gate APPROVED valer como vitória visual; o dono era o oráculo real e estava fora do loop |
| `pythia` | Honestidade sobre viés: "complacência e cegueira de autor" mitigadas por checklist ESCRITO ANTES. O checklist do ouroboros local foi escrito pelo mesmo agente na mesma sessão em que construiu — checklist móvel |
| barra-inalcancavel (incidente) | Teste de falsificação do juiz (aprovar o bom E rejeitar o ruim conhecido). Nunca rodei falsificação no juiz-em-sessão: ele rejeita o ruim (provado no C1), mas aprova o mediano — que é exatamente o modo de falha que o dono pegou |

Nota sobre o postmortem gêmeo (`...6-aneis-verdes-mas-toda-protecao-era-protocolo`,
sessão TCC/clubsurf do MESMO dia): ele cobre o lado "yaml vira documentação
no host-mode" (ledger vazio, oráculo móvel, vigia morto) — nada aqui repete
aquilo. Um contraponto factual: a regra candidata 4 de lá sugere
"nohup/launchd" como equivalentes; este field test separou os dois —
supervisor com `nohup + disown` morreu segundos depois de "Tunnel ready"
(mesma classe da regra 49), o LaunchAgent com KeepAlive sobreviveu à sessão
inteira e a quedas. Para a v4: launchd/systemd, não nohup.

## Sugestões para a v4 (concretas, uma por linha de mecanismo)

1. **Gate de CLASSE antes do gate de correção**: novo stage `class_gate` que
   pergunta uma única coisa — "a classe deste artefato alcança `nota_alvo`
   com refino de parâmetros, ou precisa trocar de classe (arte, stack,
   abordagem)?" — com referências externas nomeadas no perfil (ex.: "compare
   com Ms. Rachel / Pixar, não com o ciclo anterior"). Se classe
   insuficiente, `biggest_gap` obrigatoriamente propõe TROCA, e refino fica
   proibido até a classe passar. Teria convertido 4 ciclos de elipse em 1
   ciclo de troca.
2. **`nota_alvo` + calibração previsto-vs-real no yaml**: critic prevê a
   nota do dono (0-10) a cada APPROVED; avaliação real do dono entra como
   evento (`incident.sh`/ledger) e o delta é telemetria do juiz. Juiz com
   |delta| > 2 em qualquer calibração perde autoridade de veredito e vira
   triagem (mesmo rebaixamento que o gemma free sofreu).
3. **Oráculo de percepção congelado** (do demiurgo): os critérios do critic
   profile são escritos e hasheados ANTES do ciclo 1; o executor não pode
   editar o perfil no meio da sessão (freeze_check já existe — reusar).
4. **Stage `services` declarativo**: serviços de longa duração do run
   (dev server, tunnel) declarados no yaml e materializados em supervisor de
   SO (launchd/systemd) com prova de vida EM CHAMADA POSTERIOR antes de cada
   render (regra 49 estendida: launchd > terminal gerenciado > nohup nunca).
5. **Sentinel de artefato no vision gate**: o screenshot só é julgado se
   contiver marcador esperado (string no DOM via CDP ou pixel-assinatura);
   porta respondida ≠ artefato certo (o llama-server provou).
6. **`pre_flight` que consulta o diário**: god mode abre com
   `incident.sh list` filtrado pelos mecanismos que o modo usa (vision gate,
   dev server, biggest_gap) e cita no 1º checkpoint quais regras se aplicam.
   Regra promovida às 06h não pode ser redescoberta às 17h do mesmo dia.
7. **Asset generation como stage de 1ª classe**: `generate_assets` com gate
   próprio de consistência (imagem de referência obrigatória + checklist de
   identidade), em vez de improviso no meio do run — foi a maior alavanca do
   teste e não tem mecanismo.
8. **Pin de ferramentas do gate**: versões de playwright/browser resolvidas
   no início do run e reusadas (não `npx` solto por invocação).

## Post-scriptum ao vivo (21h15)

Enquanto este incidente era escrito, o commit `6a16fd7` de um god mode
PARALELO (modo AUTARCA, outra sessão, mesma árvore `~/.oracfit/current`)
varreu este arquivo para dentro do próprio commit via `git add -A` —
reprodução espontânea e datada do sintoma 3 do postmortem gêmeo ("commit
paralelo varreu arquivos de outro agente"). E no meio disso o disco bateu
98% (regra 51, segunda janela do dia) e o primeiro `git commit` deste
incidente falhou com `no space left on device`. Duas regras já promovidas
se manifestando DURANTE a escrita do incidente sobre god modes: a sugestão
de isolamento de árvore por agente (worktree/pathspec obrigatório em sessão
multi-agente) sobe de "candidata" para urgente na v4.

## Pode acontecer de novo?

Sim — qualquer god mode com juiz-em-sessão vai repetir o padrão "APPROVED
tecnicamente correto, reprovado pelo dono" enquanto (a) o critic não for
obrigado a julgar CLASSE contra referência externa e (b) a nota do dono não
entrar no loop como oráculo supremo com calibração. Regra candidata:

> VISION GATE EM SESSÃO JULGA DOIS EIXOS SEPARADOS, CLASSE PRIMEIRO:
> antes de refinar parâmetros, o critic responde "a classe deste artefato
> alcança a nota_alvo?" contra referência externa nomeada no perfil
> (congelado antes do ciclo 1); APPROVED de correção nunca encerra sessão
> sem previsão de nota registrada no checkpoint — e avaliação real do dono
> com |delta| > 2 rebaixa o juiz a triagem.

Promover com:
  bin/incident.sh promote 2026-08-12-god-mode-ouroboros-aprovou-4-ciclos-e-o- "<texto da regra>"

## Quitação por mecanismo (2026-08-13)

A dívida foi paga por MECANISMO (regra 32), não por promoção da candidata
acima: a parte mecanizável dela — a sugestão 2 da lista v4, o dono DENTRO
do loop com registro e calibração — virou código e foi usada em campo no
dia seguinte:

- `bin/oracfit-ring.sh` — o close de cada anel grava a previsão do critic
  (`owner_score_pred`); `oracfit ring score RING-N --real N` grava a nota
  REAL do dono como evento `owner_score` no ledger, com delta previsão×real
  por anel. O ponto de calibração deixou de depender de "o dono voltou"
  (causa 2): é subcomando do loop.
- GUI HITL de calibração — `bin/oracfit-panel-server.py` + `panel/hitl.html`,
  roteada como `oracfit hitl <target-dir>` em `bin/oracfit`: um anel por
  vez, anti-âncora (a previsão do critic só aparece DEPOIS da nota do dono).
- Uso real, não demo: 3 notas do dono gravadas em 2026-08-13 no ledger
  central (`ledger/ledger.jsonl`, eventos `owner_score` do run
  `ananke-20260813-0011`, deltas -0.6, +2.3, -1.5).

Limite honesto, DELIBERADO: a nota do dono continua sendo julgamento
humano — nenhum código a produz; o mecanismo garante que ela entra no loop
com registro. E o eixo "classe de qualidade vs correção" do juiz-em-sessão
(causa 1, sugestão 1/class_gate) NÃO foi mecanizado: o delta acumulado no
ledger torna o juiz descalibrado MENSURÁVEL, mas rebaixá-lo a triagem
(|delta| > 2) e o gate de classe seguem sendo protocolo/decisão do dono.
