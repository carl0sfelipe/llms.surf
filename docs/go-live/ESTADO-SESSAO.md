# ESTADO DA SESSÃO — 2026-08-30 (snapshot pré-compactação de contexto)

> Âncora de re-grounding: quem ler isto retoma sem perder nada. Lido +
> rev-parse antes de qualquer afirmação de estado (regra 26/53).

## Repos (verificados agora)

- **llms.surf**: main `ff6ea8b` (pushado). Gate local 39/39, bateria 17/17,
  40/40 suítes. Site de teste: https://carl0sfelipe.github.io/llms.surf
  (gh-pages, espelho de site/ por plumbing mktree). DNS llms.surf em parking.
- **bestmodel** (~/Work/bestmodel): main `06d1103` (pushado). 312 passed +
  GATE PASS (D4 incluso).

## Entregues hoje (nesta sessão, tudo commitado)

- bestmodel: merge S25 → **S23** chaves de assinatura por usuário (runs
  atribuídas criptograficamente) → **S24** badges source-class no web (626/626
  classificados, harvest nova) → **S26** leaderboard do fake DERIVA das runs
  (último fake==fake morto) → **D4 remainder** (LOAD-BEARING + grep presença
  no gate, 9 dirs).
- llms.surf: whitelist suspense + upsell first-wave-free + funil de email
  PLUGÁVEL (confirm.html/thanks.html; form só renderiza com
  DATA.whitelistEndpoint set — Pages é estático) + incidente B2 no backlog +
  ESCALADA-2 ao Fable (docs/go-live/ESCALADA-2-FABLE-MODELO-POR-TASK.md).

## Decisões do dono (TODAS registradas em backlogs commitados)

- A3: opt-out TRANSPARENTE (checkbox visível pré-marcado) + pontos de
  contribuição → rank → giveaway de free tokens llms-surf.
- Whitelists: DUAS (separadas por produto); o rank de pontos ATRAVESSA.
- A1: otimizador em REPO PRÓPRIO OSS, Rust, inspirado no argmin, melhorado
  pra era agêntica; L01 consome como crate.
- A2: híbrido — Ollama automático E llama.cpp manual.

## FEITO — scaffold do repo do otimizador (2026-08-30)

- Repo local: `~/Work/argos-opt` (main `31feea6`, 3 commits, tree limpa;
  SEM remote — criação de repo remoto só com ordem do dono).
- Nome PROVISÓRIO `argos-opt` (livre no crates.io junto com optik-rs,
  surfopt, goodhist, argminim; argonaut ocupado). **Licença DECIDIDA pelo
  dono 2026-08-30: dual MIT/Apache-2.0** (termos do argmin); publish=false
  até o nome final.
- Disciplina respeitada: spec S1 congelada e commitada ANTES do código
  (3aea764, check-spec verde, oráculo vermelho por design) → implementação
  (0eb65bf, oráculo verde: suíte 23/23 + demo esfera com auto-assert).
- 4 ajustes de algoritmo MEDIDOS registrados na spec (uniforme puro
  4.6e-1 / n_startup=5 lock-in / sem piso de largura freeze terminal /
  sem exclusão de repetidos re-propõe eterno). Curva esfera 3D seed 42:
  60→3.6e-1, 120→3.7e-2, 300→2.6e-3; demo assera < 5.3e-3.
- Contrato: CommandObjective (exit code = oráculo; imparsável = Broken
  gritando), max_evals exato, TrialLog resumível, PCG32 próprio,
  deps só serde/serde_json.
- L01 (bestmodel CLI v2) destravado: consumir como crate quando o dono
  bater o martelo de nome/licença.

## FEITO — L03A: TPE sobre flags de llama.cpp no bestmodel (2026-08-30, noite)

- bestmodel main `8b6d4fe` pushado. Spec `specs/en/L03A-tpe-lab-search.md`
  congelada antes do código (7317d34) → oráculo verde: `benchmark-probe lab
  --stub` end-to-end, suíte 46 testes.
- Primeiro objetivo real DECIDIDO pelo dono: flags de llama.cpp na 3090,
  NUNCA brute force — TPE do argos-opt (path dep `../../../argos-opt`).
- MEDIDO (seed 42, 60 trials, stub): TPE 406.8 tok/s vs random 329.4,
  barra 355 pinada na spec. Sem repeats. Mesma seed → mesmo lab.
- Armadilha da vez: o objetivo devolve tok/s (maior = melhor) e o argos-opt
  MINIMIZA — sem o sinal invertido o TPE "otimizava" o pior canto (50.6);
  pego pelo teste TPE-vs-random, contrato na spec.
- Quando o dono der "sobe": trocar o stub pelo script real de bench
  (mesmo contrato: JSON no stdin, tok/s no stdout, exit≠0 = falha) — o
  loop não muda (é o L02).

## REVOGAÇÃO DO "SOBE" (dono, 2026-08-30, noite)

- **Nada sobe no Vast por enquanto** — decisão do dono ANTES de criar
  instância (zero gasto; credit intacto $2.2283, 0 instâncias). O bench
  real do L02A fica bloqueado; L03A segue no stub SIM.
- **Cloud na superfície pública SÓ como whitelist gamificada** — auditado:
  llms.surf site e bestmodel.run já cumprem (sem preço/data/opções; issue
  como porta; contribuição como escalada). Toda copy futura de cloud passa
  por esta decisão (bestmodel docs/backlog.md, cb5d7d2).

## ESCALADA-3 pronta (2026-08-30, noite)

- Pesquisa compilada: `docs/go-live/pesquisa-gamificacao-whitelist.md`
  (8 pilares com fonte: Hamari, Schmitt/Skiera/VdB, Antin/Churchill,
  Nunes/Drèze, Robinhood/Monzo/Harry's, lado escuro de leaderboards,
  Schultz/Berridge, Octalysis×Hooked).
- Briefing: `docs/go-live/ESCALADA-3-FABLE-WHITLIST-GAMIFICADA.md` —
  gamificação viral da whitelist (indique e suba, tiers, badges, neuro)
  + plano dos 2 go-lives baratos. Colar no Fable JUNTO com a ESCALADA-2.

## ESCALADA-3 do Fable — ingerida no canônico (2026-08-30, noite)

- main `53aba44`: PLANO-LINEUP-2-GOLIVES.md ("The Lineup") +
  DECISIONS-E2-MODELO-POR-TASK.md + specs S10-S12 congeladas
  (check-spec 3/3 verde; oráculos 127-por-design até os testes existirem).
- **Pego no ingest**: os 5 arquivos estavam UNTRACKED no checkout do
  Fable (~/llms.surf) — origin/main não tinha nada (classe incidente
  dois-checkouts). Copiados, revalidados e commitados daqui.
- .fable-local-drafts/ dele: 8/8 idênticos ou VELHOS vs main (S4 draft é
  pré-D5) — pode morrer no próximo passe dele.
- Sequência E2-D5: S11 primeiro (100% local) → S10 com stub → mecânica
  do Lineup (template referred-by, Action do lineup.json, copy tiers/
  badges) → S12 BLOQUEADA no veto do Vast.
- Dials do dono ainda abertos: naming (default A = The Lineup), tabela
  de pontos, cadência de drops, 30 dias de conta indicada, DNS.

## Fila de decisões do dono (pendentes)

1. Nome final do otimizador (licença JÁ DECIDIDA: dual MIT/Apache-2.0).
2. Cloud bestmodel: teto diário Vast (US$X), token a custo × margem
   (moot enquanto o Vast estiver suspenso).
3. ~~Gatilho "sobe"~~ RESPONDIDO: SUSPENSO pelo dono (2026-08-30 noite).
4. Colar ESCALADA-2 no Fable (5 decisões dele).
5. Janela do B2 (tier cru — trava dispatch tow; conserto ~30min).

## Convenções da sessão (para não reaprender do zero)

- Decisão de dono → commitada no backlog do repo dono na hora.
- Spec congelada + check-spec.sh do llms.surf valida spec de QUALQUER repo.
- Edits multi-arquivo por script python: âncora ÚNICA (assert count==1) —
  âncora dupla já injetou código na ABC uma vez (pego pela introspecção).
- bestmodel: checklist lockstep em cada AGENTS.md; fake valida contra
  run_record; psycopg devolve UUID/Decimal (comparar com str()/int() na
  fronteira); cadeia de FK completa nos seeds (model-wan22-i2v-flf2v-14b,
  q-fp16, comfyui, rtx-3090/a6000).
- Gate do bestmodel: make gate (exporta DATABASE_URL; perna Postgres roda lá).
- llms.surf: gh-pages só via plumbing (blobs+mktree+commit-tree), NUNCA
  worktree sujo (contaminou uma vez — classe incidente 2026-08-13).
