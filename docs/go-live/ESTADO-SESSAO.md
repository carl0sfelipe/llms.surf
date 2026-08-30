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

## EM VOO — scaffold do repo do otimizador (PRÓXIMO PASSO, não iniciado)

- Nomes no crates.io (checados com UA correto): **argonaut OCUPADO**;
  LIVRES: argos-opt, optik-rs, surfopt, goodhist, argminim. Nome final é do
  dono; trabalhar com nome provisório marcado.
- Plano v0 (desenho fechado na sessão): crate Rust com TPE-lite (split
  good/bad por quantil γ, KDE por dimensão, n candidatos, argmax
  log p_good/p_bad), dims contínua/inteira/categórica, RNG próprio PCG32
  seedado (deps: só serde/serde_json), budget max_evals first-class,
  TrialLog JSON resumível (estado sobrevive à sessão), CommandObjective =
  objetivo como subprocesso cujo EXIT CODE é o oráculo (stdout parse f64;
  não-zero = falha) — o DNA llms.surf portado pra otimização.
- Entrega: spec S1 congelada ANTES do código (oracle: cargo test + demo
  esfera com auto-assert de erro < limiar), README creditando argmin
  (copythief ético), AGENTS.md, LICENSE PENDENTE DO DONO (proposta dual
  MIT/Apache-2.0 como argmin). Local: ~/Work/<nome>. NÃO criar repo remoto
  sem ordem.
- L01 (bestmodel CLI v2) destravado depois disso (A1–A3 todas decididas).

## Fila de decisões do dono (pendentes)

1. Nome + licença do otimizador (proposta: dual MIT/Apache-2.0).
2. Cloud bestmodel: teto diário Vast (US$X), token a custo × margem.
3. Gatilho "sobe" a rig 3090.
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
