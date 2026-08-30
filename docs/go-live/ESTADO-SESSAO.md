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

## S11 + S10 + S13 IMPLEMENTADAS (dono: "vai" — 2026-08-30, madrugada de 31)

- main `91b8466`, pushado, tree limpa. Sequência E2-D5 cumprida:
  - **S11** (b2ff5d1): lint recusa `tuned/` fantasma (4 casos) + higiene
    de contagem (incidents 107 — B2 de ontem nunca contado — e suites).
  - **S10** (a31b016): `bin/tuned-measure.sh` — 5 specs × 2 lados via
    DISPATCH_MODEL_REF, 10/10 rodadas conferidas no ledger por run_id +
    model_id; run fantasma reprova; `docs/registry-tuned-entries.md`
    congela o formato (NENHUMA entrada criada — GPU espera o "sobe").
  - **S13** (91b8466): máquina do The Lineup — `bin/lineup-build.sh`
    (byte-determinístico, fingerprint dos inputs, anti-sockpuppet:
    indicação só converte se indicado contribuiu), workflow cron 6h
    (identidade do bot via repo variable **BOT_EMAIL** — C2 recusa
    literal de e-mail e allowlist só com decisão humana), template da
    waitlist com `referred by:` + checkbox A3, `data/lineup.json`
    commitado VAZIO.
- Gates: check-spec 4/4 (S10-S13), gate local 43 pass, honesty verde.
- **FILA DO PRÓXIMO PASSO**: B-L01 no bestmodel (export por-contribuidor
  no contrato congelado na S13) → dials do dono (naming A, tabela,
  cadência, 30 dias) → copy The Lineup nos 2 sites → S12 segue
  BLOQUEADA no veto do Vast.

## B-L01 IMPLEMENTADO (bestmodel main 47d7b72, S27) — 2026-08-31

- export por-contribuidor verde nos 2 backends + GATE PASS; script
  fail-loud escreve data/contributor-export.json (formato exato que o
  workflow lineup do llms.surf consome). Primeiro export REAL nasce
  quando existir a primeira run assinada validada com usuário.

## DIALS PARCIAIS DO DONO (2026-08-31)

- Naming do programa de pontos do llms.surf: **"The Lineup"** (aprovado).
- Tiers: **de "Haole" até "The Legend"** — BLOQUEADOS no meio (dono fecha
  depois). CORREÇÃO do dono (2026-08-31): é HAOLE — o outsider havaiano
  que chega sem conhecer as regras do surf; a jornada da fila é haole →
  legend, e a moeda é contribuição. Tiers do meio: com o Fable na copy
  (sementes, não decisão: Grom → Local → ...).
- **bestmodel terá gamificação PRÓPRIA, profissional** (menos sarcástica) —
  desenho/nome separados, depois.
- **Copy do The Lineup nos sites: BLOQUEADA para modelos flash** — dono
  leva ao Fable (copy é crítica demais). Máquina (S13) não espera copy.

## PROD bestmodel: 0013 aplicada + QUADRO REAL DE DADOS (2026-08-31)

- Migração 0013 aplicada e verificada no DB de produção (docker exec no
  bestmodel-prod-api-1): signing_key + signature_key_id existem; runs
  legacy seguem válidas (D2 opt-in).
- **QUADRO REAL**: prod tem só **2 runs e 1 usuário** — os 626 runs
  classificados NÃO estão no prod (estão no harvest local/banco do gate).
  Dono queria lançar sem cold start: caminho honesto = importar dado OU
  dogfood assinado (ele registra chave S23 e assina runs da frota — cada
  uma vale 2 pontos no handle dele).
- **Pendência de deploy**: a imagem do prod-api é ANTERIOR a S23/S27 —
  não tem fetch_contributor_points nem rotas de signing key. Rebuild +
  restart do container é pré-requisito do export real.

## S28 DEFINIDA PELO DONO (2026-08-31): importar runs com fonte + botão de denúncia

- Dono quer IMPORTAR os runs colhidos pro prod **com a fonte de origem
  carimbada**, classe `reported` (não-verificados pelo CLI — ok, ajudam a
  achar os melhores modelos; badge honesto da S24 já cobre).
- **Botão "denunciar run irreal"** no web → endpoint + tabela run_report →
  confirmado = mecânica "fake pego" (5 pontos). É o contrapeso do import.
- IMPORTADORES JÁ EXISTEM: infra/scripts/import_localmaxxing.py
  (--apply --source pool.json) e import_lab_export.py — a S28 adapta pra
  prod com proveniência (source_url/name) + rota de denúncia + botão.
- Gate DB @5434: 36 runs (34 measured_signed, 2 derived). Os 626 vêm do
  pool do dono (perguntar onde está o pool.json / a fonte).

## POOL ENCONTRADO (dono acertou: estava no CanIRunIt) — 2026-08-31

- `/home/beelink/Work/CanIRunIt/canirunit-web/data/derived/pool.json`:
  **1310 células** (rigKey, modelSlug, bits, n, tokSOutMedian,
  tokSPrefillMedian, ttftMsMedian, peakVramGbMedian, maxContextTested,
  engines), snapshot 2026-08-13. É a fonte pro import S28 no prod.
- Próximo passo S28: (1) casar o schema do pool com os importadores
  existentes (import_localmaxxing.py / import_lab_export.py) — dry-run
  primeiro, --apply depois, classe `reported`, proveniência = "CanIRunIt
  pool snapshot 2026-08-13" + rigKey; (2) endpoint + tabela + botão de
  denúncia de run irreal (mecânica fake pego, 5 pts); (3) rebuild da
  imagem prod-api (S23/S27 dentro); (4) B2.

## ESCALADA-4 entregue pelo Fable (2026-08-31) — dials fechados por ele (veto barato)

- docs/go-live/PROMPT-CLAUDE-DESIGN-2-SITES.md: prompt-mestre (EN), 4
  rodadas com auto-auditoria, não-negociáveis testáveis (mobile-first sem
  gating min-width; régua de honestidade com whitelist de fatos medidos;
  HTML/CSS/JS puro, paths relativos no Pages, cleanUrls no Vercel).
- Dials fechados por ele (dono pode trocar barato): jornada do Lineup
  **Haole → Grom → Local → The Legend**, First Wave = PRÊMIO (top 25 por
  pontos, política D6/D9), não tier; bestmodel = **Track Record**,
  níveis Contributor → Replicator → Auditor (zero léxico de surf).
- Verificações dele: min-width 1024 confirmado nos 3 protótipos;
  gen-seo.mjs gera m/, p/ e sitemap.xml (proibido colar por cima);
  âncoras de copy extraídas verbatim.

## E5 CONGELADA (Fable, 2026-08-31) — implementação M1-M6 autorizada

- DECISIONS-E5-FREE-PATH.md ingerido do checkout do Fable. D1-D5 = A/A/A/
  A/A-紧 (D5 com 2 apertos: envs pagas ENVENENADAS no gate — isca prova
  imunidade; provider_efetivo ∈ allowlist do run, não só presente).
- 5 riscos dele viram requisitos: (R1) "no API key" ≠ "sem credencial
  paga" — checar keyless dos 2/22 alcançáveis ANTES de re-anunciar, D5
  tem 2 pernas (zero-key pra promessa, free-key via auth.json);
  (R2) sync atômico: temp → valida schema+contagem+amostra → move, falha
  mantém último snapshot bom; (R3) é limit-aware, não quota — copy
  pública NUNCA usa a palavra "quota" sem mecanismo de contador;
  (R4) allowlist default de provider = DIAL do dono; (R5) assertar que
  nenhum consumidor do ledger re-resolve id via registry antes do M3.
- Pronto += re-anúncio cita o audit ANTES e DEPOIS (46/69 → 0/N).

ORDEM DE IMPLEMENTAÇÃO (mim) — **CUMPRIDA 2026-08-31** (ver seção E5 FECHADA abaixo).

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

## E5 FECHADA — caminho free íntegro, M1-M6 + D5 + R1 (2026-08-31)

- **Régua**: audit ANTES 46/69 mortos (21 NAO-ENCONTRADO + 25 FANTASMA)
  → DEPOIS **0/23** (19 EXISTE + 4 PROVAVEL). Re-anúncio:
  docs/go-live/RE-ANUNCIO-FREE-PATH.md.
- Commits da cadeia: 2662211 (M4 catálogo+M2 --stamp/gate na porta) →
  afeb8ed (M3 retirada + B2 pago) → b7100af (M5 lib credencial por
  ARQUIVO + gate 3 anéis) → 06b1a86 (M6 provider_efetivo + allowlist
  R4) → 05371c3 (M1 sync atômico R2) → 710683d (D5: 13 pernas, envs
  pagas ENVENENADAS não vazam; allowlist adulterada = violado) → 82f5e2d
  (re-anúncio).
- `tier:cheap` = lista fallback do `data/free-catalog.json` carimbado
  (11 refs: 2 keyless opencode + 9 openrouter :free com pricing 0
  medido; sync regenera do feed JSON /v1/models, nunca scraping).
- **R1 medido**: perna zero-key responde de verdade (~15-16s, zero
  chave, custo zero); perna free-key pula com aviso sem credencial em
  arquivo. NUNCA dizer "quota-aware" (é limit/event-driven, R3).
- **B2 FECHADO** no mesmo mecanismo: dispatch-mode/dispatch-stages/critic
  roteiam `tier:*` via run-with-fallback — nenhum tier cru chega a runner.
- Saúde 20/20 (ganhou exclusividade-credencial + test-free-path).
- PRÓXIMOS NA FILA: S28 (import pool.json 1310 células + botão denúncia
  + rebuild prod-api), push pendente, dials do dono (allowlist default já
  setada: opencode+openrouter — R4 dial, dono pode trocar).

## S28 ENTREGA COMPLETA no prod (2026-08-31, madrugada de 09/01)

- bestmodel main `604e7c2` pushado. Migration 0014 aplicada no PROD
  (run_report + run_claim.provenance). As 551 claims localmaxxing com
  proveniência carimbada E VERIFICADA: 550/550 métricas idênticas ao
  snapshot 2026-08-13 (CanIRunIt/localmaxxing.com) — evidência, não
  presumição. Dry-run do pool: 551 existing, 0 novas, 411 nomodel
  (backlog catálogo), 348 multigpu (fora do escopo).
- Denúncia de run irreal NO AR: POST /v1/run-claims/{id}/reports e
  /v1/runs/{id}/reports (auth), moderação GET /v1/reports + confirm/
  dismiss (MODERATOR_HANDLES, default carl0sfelipe — DIAL do dono no
  compose). Confirmar = claim refuted + 5 pontos ao denunciante
  (fake pego; fetch_contributor_points em lockstep nos 3 backends).
- Imagem prod-api REFEITA (S23/S27/S28 dentro) + worker; containers
  healthy; smoke público verde (401 sem auth, 404 na rota inexistente).
  Falta: dono testar autenticado (passkey dele) e o botão no front
  (Claude Design).
- Commits: e8423d9 (spec) → 61be0b6 (implementação, GATE PASS x2) →
  604e7c2 (deploy + dial).

## Fila restante (pós-S28)

1. Dono: smoke autenticado da denúncia no prod (passkey) — 2min.
2. Dono: "dns setado" → Phase A com cronômetro + smoke log.
3. Fable: copy The Lineup + Track Record + post de lançamento (bloqueado
   para flash por decisão do dono).
4. Claude Design: bestmodel-ONLY redesign → dono cola resultado.
5. Botão de denúncia no front do bestmodel (chega com o redesign).

## ESCALADA-6 PRONTA (f7296cd) — última chamada cara

- docs/go-live/ESCALADA-6-FABLE-VALIDACAO-E-COPIA.md: validação E5+S28+B2
  por bloco, 3 ratificações (D2 feed=provider JSON, allowlist, moderator),
  decisões 4.1-4.6, e as COPIES destravadas (The Lineup, Track Record,
  2 posts de lançamento + tabela falta-pra-lançar). Esqueleto de veredito
  ingerível; checagens só locais; proibido rede/opencode models.
  DONO: colar o arquivo no Fable (pull para 409879c antes).

## E6 EXECUTADO (2026-08-31, sessão autônoma) — commits 2c4f417..60bc015+

Veredito do Fable em docs/go-live/DECISIONS-E6-FABLE-FECHAMENTO.md
(E5 OK com 1 MELHORAR; RAT-1/2/3 OK; decisões 4.1-4.6; copies prontas;
4 riscos). Execução:

- **S28 MELHORAR FECHADA** (bestmodel acd779a): migration 0015
  (reporter NOT NULL + índice único open/dismissed por reporter+alvo)
  aplicada no gate @5434 e no PROD; Fake lockstep (ValueError = índice);
  serviço 409 distinto para duplicada-vs-dismissed; find_existing
  substitui find_open. Imagem do prod REFEITA de novo (api+worker,
  healthy, smoke 401). Testes 7/7; GATE PASS.
- **D5 15 pernas** (33a6bd6): perna do Fable (auth.json corrompido →
  exit 3) + perna do risco E6-1 (sync sem opencode aborta loud, snapshot
  mantido). sync ganhou --allow-no-keyless.
- **Copies + dial no MESMO commit** (60bc015, regra anti-drift do risco
  E6-2): data/lineup-points.json com tiers PROPOSTA (Haole 1+, Grom 5+,
  Local 20+, Legend 50+, First Wave=prêmio top-25) + 4 arquivos verbatim
  (COPY-THE-LINEUP, COPY-TRACK-RECORD, LAUNCH-POST-LLMSSURF,
  LAUNCH-POST-BESTMODEL).
- 4.1=(a) re-anúncio dentro do post ✓ (já no copy). 4.6=manter argos-opt.

## PENDENTE DE RATIFICAÇÃO DO DONO (recomendações E6, sem código ainda)

- **4.5 (30 dias)**: conversão de referral = 1º SIGNED RUN do indicado
  em ≤30 dias da criação da conta (join não converte). Se ratificar:
  exige export S27 com created_at/first_signed_run_at + regra no
  lineup-build.sh (~1h de sessão).
- **4.4 (cadência)**: standings a cada 2 semanas, event-driven (pula
  drop se rank não mudou).
- **4.2 (canário da free-key)**: chave OpenRouter free do dono +
  `opencode auth login` + 1 dispatch tier:cheap pela cadeia conferindo
  provider_efetivo=openrouter + allowlist_status=ok no ledger ANTES de
  anunciar a perna.
- Risco E6-3 (First Wave esfriar): ter pronta a resposta "a fila existe
  quando a cloud existir; a prioridade já é sua".
- Ordem de lançamento do Fable: smoke autenticado (dono) ANTES do
  Claude Design congelar UI.
