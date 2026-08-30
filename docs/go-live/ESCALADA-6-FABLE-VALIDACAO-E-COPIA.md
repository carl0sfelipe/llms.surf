# ESCALADA-6 — VALIDAÇÃO FINAL + DECISÕES + COPIES (one-shot)

> **CONTEXTO DE CUSTO (o dono, 2026-08-31): estes são os ÚLTIMOS dólares
> dele no Fable. Isto é a última chamada cara do ciclo.** Seu veredito
> tem de ser COMPLETO e auto-contido: nada de "na próxima rodada eu
> vejo". Se algo não fechar com as checagens permitidas abaixo, marque
> `[A DEFINIR PELO DONO]` ou `ASSUMPTION: <sua premissa>` e siga —
> NUNCA devolva perguntas que exijam outra rodada.
>
> Papéis (mesma divisão das escaladas 2-5): você julga e escreve o que
> exige juízo; a implementação já está FEITA, VERIFICADA e COMMITADA —
> nada aqui pede código seu.

## 0. BOOT (nesta ordem, sem pular)

1. `git -C ~/llms.surf pull && git -C ~/llms.surf rev-parse --short HEAD`
   → deve imprimir **409879c**. `git -C ~/Work/bestmodel pull && git -C
   ~/Work/bestmodel rev-parse --short HEAD` → deve imprimir **604e7c2**.
   Se o pull não trouxer, PARE e reporte "checkout divergente" — não
   valide sobre árvore velha (lição da ESCALADA-3).
2. Checagens PERMITIDAS (todas locais/offline):
   - `cat` de qualquer arquivo citado por nome aqui;
   - `python3 bin/lib-oracfit-mode-loader.py resolve-tier tier:cheap`
     (llms.surf, offline);
   - `bash bin/check-spec.sh <spec>` (valida spec de qualquer repo);
   - `bash bin/test-free-path.sh` (offline, stub, ~13s) — opcional;
   - `git log --oneline` para conferir os commits citados.
3. PROIBIDO: fetch de rede (OpenRouter, freellm, freellm.net), 
   `opencode models` (quebra no seu sandbox — já mordeu na ESCALADA-5),
   `make gate` do bestmodel (custa minutos — já rodou PASS 2x), explorar
   arquivo além dos citados, propor reimplementação.
4. Todo número deste documento tem data de medição. **Você NÃO precisa
   re-medir nada** — as checagens permitidas existem para desconfiança
   pontual, não para auditoria completa.

## 1. DIGEST DO QUE FOI ENTREGUE (confira contra o disco se desconfiar)

### 1.1 E5 — caminho free íntegro (llms.surf, 8 commits, main 409879c)

A régua que abriu o incidente o fecha:

- **ANTES**: `bin/audit-registry-ids.sh` → **46/69 ids mortos** (21
  NAO-ENCONTRADO + 25 FANTASMA); o default `tier:cheap` servia um id
  (deepseek-v4-flash-free) com hint morto, em silêncio.
- **DEPOIS**: **0/23** (19 EXISTE + 4 PROVAVEL), audit re-carimbado
  2026-08-31.

Mecanismos (commit → uma linha):

| Commit | Mecanismo |
|---|---|
| 2662211 | **M4**: `tier:cheap` = LISTA fallback ordenada de `data/free-catalog.json` (keyless primeiro, contexto desc, empate lexicográfico — função pura do conteúdo); `run-with-fallback.sh` expande `tier:*` na cadeia RF-08. **M2**: `audit-registry-ids.sh --stamp` grava `id_status`+`id_checked_at` no registry; resolve-tier e a cadeia recusam FANTASMA/NAO-ENCONTRADO/NAO-VERIFICADO na porta com WARN alto. Catálogo ausente/ilegível = exit 2 LOUD (nunca degrada para default). |
| afeb8ed | **M3**: 46 mortos removidos em 1 commit (D1: git history = lista retired). Consumidores migrados: 7 modos YAML → `tier:cheap`/`tier:mid`; defaults do loader só com id vivo; escada do dispatch-escalate para ids verificados em `opencode models`; docs de exemplo atualizados. **B2 pago** no mesmo mecanismo: dispatch-mode, dispatch-stages e o critic do gauntlet roteiam `tier:*` via run-with-fallback — incidente 2026-08-30 fechado com quiteiro no arquivo. |
| b7100af | **M5/D4**: `bin/lib-free-credentials.sh` = leitora ÚNICA de credencial, POR ARQUIVO (auth.json do opencode + opencode.json custom; storage presente mas ilegível = exit 3; nenhuma função devolve material de chave). Gate `check-free-credential-exclusivity.sh` em 3 anéis: cadeia de dispatch com ZERO padrão de credencial fora da lib; adapters só citam prefixo do próprio CLI (comentário não normaliza leak); exceções fora da cadeia contadas (cf-probe, vision-gauntlet — API direta pré-E5). Gate provado que morde: vazamento injetado em usage-hub.py reprova. |
| 06b1a86 | **M6/R4/R5**: run-with-fallback grava `ref+provider` de quem SERVIU (DISPATCH_EFETIVO_FILE); ledger-finalize grava `provider_efetivo`, `provider_efetivo_ref`, `allowlist_status` na linha (fora-do-escopo / ok / violado / sem-allowlist). Allowlist = dial do dono em `data/free-provider-allowlist.json`, default **["opencode","openrouter"]**. R5: nenhum consumidor do ledger re-resolve id no registry (grep no gate). |
| 05371c3 | **M1/D2/R2**: `bin/sync-free-catalog.sh` regenera o catálogo de feed JSON estruturado (OpenRouter `/v1/models`, keyless-read; free = pricing.prompt==0 E completion==0 MEDIDO no feed) + perna zero-key do `opencode models` local. Atômico: temp → valida (schema, ≥3 refs, ref ∈ registry, free medido) → move; falha mantém snapshot (provado com endpoint morto e JSON lixo). |
| 710683d | **D5 apertado**: `bin/test-free-path.sh` — 13 pernas em 12.5s, incluindo **dispatch com envs pagas ENVENENADAS** (isca em AWS_*/OPENROUTER/GROQ/NVIDIA/DEEPSEEK: run fecha pela perna keyless, `allowlist_status=ok`, ZERO isca vazada em log/ledger/efetivo) e **allowlist adulterada → violado**. Registrado no check-saude. |
| 82f5e2d | Re-anúncio: `docs/go-live/RE-ANUNCIO-FREE-PATH.md` (régua + R1 + regras de copy). |

- **R1 medido antes de re-anunciar** (2026-08-31): perna zero-key =
  `mimo-v2.5-free` (16.0s) e `nemotron-3-ultra-free` (15.0s) responderam
  real, sem criar chave, custo zero. Perna free-key = 9 refs OpenRouter
  `:free` no catálogo (pricing 0 medido no feed; inclui nemotron-550b ctx
  1M e openrouter-free-router ctx 200K) — pula com aviso sem credencial
  em arquivo. **O feed também mostrou deepseek-v4-flash e gpt-oss-120b
  VIRANDO PAGOS** — ficaram fora do catálogo (a própria classe do E5,
  pega desta vez pelo mecanismo).
- Catálogo atual: **11 refs** (2 keyless + 9 openrouter).
- Saúde: **20/20** (novas pernas: exclusividade-credencial + free-path).
- README "Try it in 2 minutes — no API key" é claim do STUB e segue
  verdadeira; a claim nova permitida é a perna zero-key medida acima.

### 1.2 S28 — denúncia de run irreal + proveniência (bestmodel, main 604e7c2)

- Spec congelada antes do código: `specs/en/S28-run-report-and-provenance.md`
  (check-spec verde; commit e8423d9). Implementação 61be0b6. GATE PASS
  2× consecutivos.
- **Import já estava no prod** (551 claims, 2026-08-26) — o que faltava
  era prova e proveniência: **550/550 métricas idênticas ao snapshot
  2026-08-13** do pool (CanIRunIt/localmaxxing.com) → proveniência
  carimbada com evidência, não presumição. Dry-run do pool completo:
  551 existing (idempotente), 0 novas, 411 nomodel (backlog de catálogo),
  348 multigpu-v1 (fora do escopo v1).
- Migration 0014 aplicada no prod E no gate DB: `run_report` (alvo
  claim/run com CHECK de exclusividade; reporter identificado; categorias
  fechadas; awarded_at) + `run_claim.provenance` jsonb.
- Mecânica **fake pego**: POST `/v1/run-claims/{id}/reports` e
  `/v1/runs/{id}/reports` (auth obrigatória — anônimo não pontua);
  moderação GET `/v1/reports` + `/confirm`+`/dismiss` protegida por env
  **MODERATOR_HANDLES** (default `carl0sfelipe`, dial no compose).
  Confirmar = claim → `refuted` + **+5 pontos** ao denunciante em
  `fetch_contributor_points` (lockstep ABC+Fake+Postgres — contrato S27
  estendido). Denúncia NUNCA altera o alvo por si só. Teto 10/dia
  (padrão S20); duplicada em aberto = 409.
- Imagem do prod-api REFEITA (S23/S27/S28 dentro) + worker; containers
  healthy; smoke público: rotas novas 401 sem auth, 404 na inexistente.
- Falta (fora do meu alcance): smoke autenticado (passkey do dono);
  botão no front (chega com o Claude Design).

### 1.3 Estado dos gates (2026-08-31)

llms.surf: check-saude **20/20** (exit 0); loader tests 14/14; dívida de
incidente zerada (B2 quitado). bestmodel: GATE PASS ×2; test_run_report
8/8 (com DATABASE_URL); README/site com números da árvore (107
incidentes; registry 23).

## 2. O QUE VOCÊ VALIDA (veredito por bloco: OK | MELHORAR + instrução)

1. **M4/M2** — catálogo carimbado como fonte do tier + id_status stampado
   como gate na porta. Contrato novo do resolve-tier é MULTI-LINHA (lista
   ordenada); consumidores mapeados: run-with-fallback, dispatch-mode,
   dispatch-stages, critic do gauntlet. Sobrou consumidor?
2. **M5** — credencial por ARQUIVO como fechamento da classe + as exceções
   dos 3 anéis (cf-probe e vision-gauntlet fora da cadeia; CURSOR_/ZCODE_
   como prefixo próprio). Aceitável, ou exige algo mais duro?
3. **M6** — `allowlist_status` na linha do ledger + allowlist como dial em
   arquivo. Suficiente para R4/R5 do seu veredito da ESCALADA-5?
4. **M1** — free = pricing==0 medido no feed JSON do provider (ver
   RATIFICAÇÃO R1 abaixo). Validação R2 suficiente (schema + contagem +
   amostra viva) para o pior caso "feed quebrado"?
5. **D5** — as 13 pernas fecham a classe a seu ver? Falta alguma perna de
   envenenamento que você exija?
6. **S28** — mecânica fake-pego (confirm = refuted + 5pts;
   MODERATOR_HANDLES sem conceito de admin; reporter obrigatório, anônimo
   fora). Risco de abuso que a S20 (10/dia) + 409 + identidade não cubra?
7. **B2** — quiteiro no incidente (mecanismo, não regra; camada 2 cursor
   documentada como vigência). Aceito?

## 3. RATIFICAÇÕES (refinamentos que saíram do congelado — OK | NÃO + motivo)

- **RAT-1 (D2)**: a promessa era usar o dataset do
  awesome-freellm-apis. AS-BUILT: o repo NÃO publica JSON de catálogo
  (só README/tabelas — o scraping que o D2 rejeitou; feed.json de lá é
  notícia). Então: **runtime feed = `/v1/models` JSON do próprio
  provider** (OpenRouter hoje; Groq/NVIDIA quando o dono guardar chave —
  a lib M5 detecta); awesome-freellm-apis fica como DIRETÓRIO de
  onboarding/curadoria (quais providers ligar, links de chave). É o
  endpoint que o próprio audit já usava.
- **RAT-2 (R4)**: allowlist default `["opencode","openrouter"]` — dial em
  `data/free-provider-allowlist.json`, editável pelo dono.
- **RAT-3**: moderação por `MODERATOR_HANDLES` (env, default
  carl0sfelipe) em vez de tabela de roles. Prod tem 1 usuário; conceito
  novo de admin custaria migration + UI sem necessidade hoje.

## 4. DECISÕES QUE FALTAM (sua resposta fecha o dial)

Para cada: decida (você tem mandato do dono para as 4.1-4.3) ou dê
RECOMENDAÇÃO ÚNICA com uma linha de implicação.

- **4.1 Re-anúncio do free path**: (a) seção dentro do post de
  lançamento de cada produto, (b) post/tópico separado, (c) só no
  README. *Recomendo (a) — uma voz só, a régua 46/69→0/23 vira prova de
  maturidade do processo, não lavagem de roupa suja.*
- **4.2 Ativação da perna free-key**: plano é dono criar chave free
  OpenRouter (sem cartão) + `opencode auth login` (~2 min); catálogo já
  tem os 9 refs e a cadeia passa a usá-los sozinha. Alguma condição que
  você exija ANTES (ex.: teste canário de 1 chamada)?
- **4.3 Copy de thresholds dos tiers do Lineup**: os números de corte de
  pontos são POLÍTICA (proposta de design, não fato medido) — proponha
  os thresholds como proposta explícita marcada `PROPOSTA`, ou deixe
  `[A DEFINIR PELO DONO]`. *Recomendo propor — dono gira dial editando
  um JSON; copy pronta é o gargalo, não o número.*
- **4.4 [RECOMENDAÇÃO só] Cadência de drops do Lineup** (ex.: post de
  standings a cada X). Uma linha.
- **4.5 [RECOMENDAÇÃO só] Regra dos 30 dias da conta indicada** (janela
  para conversão de referral valer pontos extra ou expirar). Uma linha.
- **4.6 [RECOMENDAÇÃO só] Nome final do otimizador OSS** (atual
  `argos-opt` provisório, dual MIT/Apache, publish=false). Se tiver
  candidato melhor que `argos-opt` (livre no crates.io), 1 linha.

## 5. COPIES (o que estava BLOQUEADO para modelo flash — é SUA entrega aqui)

Idioma das copies: **EN** (superfície pública), com resumo PT-BR de 3
linhas cada para o dono. Tom: llms.surf sarcástico-surf; bestmodel
profissional, ZERO léxico de surf (decisão do dono).

**Whitelist de fatos (só isto, com as datas):**
- 107 incident postmortems (tree, 2026-08-31);
- registry audit: 46/69 dead model ids removed → 0/23 (2026-08-31);
- zero-key free path: two bundled models answered real prompts in
  ~15-16s, no key creation (2026-08-31);
- 9 OpenRouter :free models in the stamped catalog (pricing==0 measured
  in the feed, 2026-08-31);
- 551 community-reported benchmark cells imported with verified
  provenance — 550/550 metrics identical to the 2026-08-13 pool snapshot;
- "report an unreal run" live in the prod API (smoked 2026-08-31);
- free-path integrity gate: 13 checks incl. poisoned paid credentials
  (2026-08-31); local health battery: 20/20.

**PROIBIDO (régua da casa)**: preço, data de lançamento, "quota"
(palavra banida em copy — é limit/event-driven), contagem de usuários
(prod tem 1 — NUNCA implique comunidade), depoimento, promessa de
receita, feature futura no tempo verbal de presente.

### 5.1 The Lineup (llms.surf) — copy completa do programa

Inputs congelados: jornada **Haole → Grom → Local → The Legend** (você
fechou na ESCALADA-4); **First Wave = PRÊMIO (top-25 por pontos), não
tier**; tabela de pontos (dial do dono, pode propor cortes como
`PROPOSTA` em 4.3):

```
{"join_issue":1,"referral_converted":3,"signed_run":2,"run_reproduction":3,"fake_caught":5,"shared_custom_mode":2}
```

Export que alimenta o rank (contrato S27):
`{"generated_at","contributors":[{"handle","points","validated_runs"}]}`.

Entregue por tier: nome (congelado), 1-2 frases de descrição, sugestão de
badge (nome + ideia visual em palavras), regra de promoção com threshold
(`PROPOSTA` ou `[A DEFINIR]`) + copy da First Wave (o que o top-25
ganha: prioridade na fila de cloud quando ela existir — tempo verbal
honesto, NADA de prometer GPU/data) + 1 linha anti-sockpuppet em tom de
casa ("referral só conta se o indicado contribuir de verdade" — já é
código, pode dizer).

### 5.2 Track Record (bestmodel) — copy do programa profissional

Níveis **Contributor → Replicator → Auditor** (você fechou). Mesmo
formato do 5.1: descrição, badge, regra de subida. Pontos: mesma fonte
(validated run assinada ×2; fake caught ×5). Sem sarcasmo, sem surf.
1 parágrafo de topo explicando POR QUE replicação vale mais que claim
("a comunidade mede, o CLI assina, qualquer um replica").

### 5.3 Posts de lançamento

- **llms.surf** (≤300 palavras EN): framework de orquestração + The
  Lineup + whitelist (issue como porta, sem cloud ativa — veto do dono
  vale) + re-anúncio do free path (decisão 4.1).
- **bestmodel** (≤300 palavras EN): ranking honesto de hardware local +
  Track Record + 551 células reportadas com proveniência + botão de
  denúncia + "reported ≠ verified" como lema.
- Cada um com: título, corpo, 3 bullets de prova (da whitelist), PT-BR
  3 linhas.

### 5.4 "Falta pra lançar" — feche a tabela

Preencha a tabela final (item | dono da ação | dependência) cobrindo no
mínimo: DNS llms.surf→Phase A (dono), smoke autenticado da denúncia
(dono, passkey), chaves free-key (dono), botão de denúncia no front +
redesign bestmodel (Claude Design — prompt pronto em
`docs/go-live/PROMPT-CLAUDE-DESIGN-BESTMODEL-ONLY.md`), subida das copies
nos sites (dono cola), S12 (bloqueada no veto do Vast — fora), pós-lança
(Discussions/anúncio). Sinalize se a ORDEM está errada.

## 6. FORMATO DO SEU VEREDICTO (cole exatamente este esqueleto, preenchido)

```
## CHECKOUTS
llms.surf=409879c ok|diverge ; bestmodel=604e7c2 ok|diverge
## VEREDITO E5
M4: OK|MELHORAR — <1 linha>   (repetir para M5, M6, M1, D5, S28, B2)
## RATIFICAÇÕES
RAT-1: OK|NÃO — <1 linha>     (RAT-2, RAT-3)
## DECISÕES
4.1: <letra> ; 4.2: <condição|ok> ; 4.3: <propose|defer>
4.4: <1 linha> ; 4.5: <1 linha> ; 4.6: <1 linha>
## COPY THE LINEUP
<markdown pronto pra colar>
## COPY TRACK RECORD
<markdown pronto pra colar>
## POST LLMSSURF
<EN> ... [PT-BR: <3 linhas>]
## POST BESTMODEL
<EN> ... [PT-BR: <3 linhas>]
## FALTA PRA LANÇAR
<tabela markdown>
## RISCOS NÃO LISTADOS
<o que você vê que eu não perguntei — ou "nenhum">
```

Regra final: **não saia do esqueleto**. O dono vai colar sua resposta
direto no ingest; qualquer prosa fora dele vira custo, não valor.
