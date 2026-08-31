# SUPERPROMPT — Opus (max): transforme o site PROD do CanIRunIt na nossa rede social de captura — sem trocar o que é bonito

> Como usar: rode isto no Claude (Opus, esforço máximo) com o repositório
> `CanIRunIt` aberto (workdir `canirunit-web/`). É autocontido: os contratos
> de API estão AQUI, verbatim, direto do código da API pública. Não precisa
> de anexo.

## MISSÃO

O site que está em produção em https://bestmodel.run — este repositório — é
bonito e **permanece bonito**: a homepage, o explorador de hardware, a
narrativa em cenas, o seletor goal-first. Seu trabalho é transformar este
site numa **rede social funcional de captura de benchmarks**: as pessoas
hoje publicam números sem prova espalhados por Reddit, Twitter, GitHub e
blogs; nós damos a cada número uma casa, uma origem (`source_url`), votos da
comunidade e um caminho criptográfico pra prova (run assinada Ed25519).
Você constrói os órgãos sociais que faltam **dentro do corpo vivo que já
existe**. Não é redesign. Não é port. Não é zip: é trabalho direto neste
repo.

## A LEI Nº 1 — O DESIGN ATUAL É O PRODUTO

- `CONTRATO-GLOBAL.md` manda: `prototypes/` é a spec visual FINAL e
  `site/assets/theme.css` é a lei de tokens (`--bg:#0B0C0E`,
  `--surface/--surface-2/--surface-3`, `--hair`, `--amber:#E0A458`,
  `--green/--red`, Inter / Inter Tight / JetBrains Mono, mono para todo
  dado). Você EXTENDE via CSS novo; JAMAIS redefine token existente.
- A gramática visual do site é **narrativa em cenas** (`.scene`, reveals
  `.on`, microcopy `--mono`). As páginas novas falam essa língua.
- **index.html e hardware.html não mudam visualmente** — a única alteração
  permitida neles é a entrada das novas páginas na navegação, no padrão de
  nav que já existe.
- Se você sentir vontade de "melhorar" o hero, a paleta, a tipografia ou o
  grid: não. Isso já foi rejeitado uma vez pelo dono (round 1 de um design
  externo — "achei meio bosta" — e o protótipo manual dele venceu). Você
  está aqui porque o que existe é bom.

## BOOT — leia nesta ordem antes de escrever 1 linha

1. `canirunit-web/CONTRATO-GLOBAL.md` — o contrato da casa (stack, honestidade, layout do repo).
2. `canirunit-web/prototypes/` — a spec visual final (NÃO EDITAR NUNCA).
3. `canirunit-web/site/index.html` e `site/hardware.html` — o corpo vivo: estrutura, nav, cenas, seletor goal-first.
4. `canirunit-web/site/assets/theme.css`, `engine.mjs`, `goal-page.mjs`,
   `hardware-page.mjs`, `ui.mjs`, `load-data.mjs` — a lei visual e a lógica de dados existente (basis honesto: measured > reported > extrapolated > no data).
5. `canirunit-web/site/m/index.html` e uma amostra de `site/p/` — mobile e página por modelo.
6. Este documento inteiro (contratos abaixo).

Regra do disco: quando sua memória e o repo discordarem, o disco vence.
Divergência encontrada → anote no RELATÓRIO e siga pelo disco.

## O QUE CONSTRUIR — 4 páginas + 1 integração

Stack travada (contrato da casa): HTML/CSS/JS vanilla (ES modules), ZERO
frameworks, ZERO npm, ZERO build step. Caminhos relativos. Links seguros
pra cleanUrls (sem barra final). API same-origin base `""` (o deploy
reescreve `/v1/*` pro backend). Token de sessão: `localStorage.bm_token`
(quem emite é o console; suas páginas LÊEM, nunca re-implementam auth —
401 = CTA "sign in → /console").

### 1. `site/claims.html` — The Wall (feed público de captura)

`GET /v1/claims?status=open|settled_verified|refuted|retracted&sort=recent|controversial|strongest&limit=25&offset=0`
→ array de claims. Shape exato da linha (renderize só estes campos):

```json
{
  "id": "uuid",
  "claimant_handle": "string ou null (null = import do pool)",
  "source": "localmaxxing ou null",
  "external_ref": "string ou null",
  "model_release_id": "string",
  "quantization_profile_id": "string ou null",
  "gpu_model_id": "string ou null",
  "context_tokens": 32768,
  "claimed_metrics": { "decode_tok_s": 41.5, "prefill_tok_s": 940, "ttft_ms": 733, "peak_vram_mib": 23040 },
  "note": "string ou null",
  "source_url": "https://reddit.com/... ou null",
  "status": "open | settled_verified | refuted | retracted",
  "prior_snapshot": { "pool": { "basis": "measured", "p50_decode_tok_s": 38.2, "run_count": 4 } },
  "created_at": "2026-08-31T00:00:00+00:00",
  "tally": { "plausible_count": 3, "impossible_count": 1, "margin": 50, "voter_count": 4 }
}
```

- **`source_url` é o herói da página**: quando presente, chip de
  proveniência "found on reddit.com / x.com / github.com…" linkando pra
  fora (domínio extraído, fonte mono). O produto é isto: número sem prova
  capturado COM a origem.
- Badges de status na semântica existente: `open` (âmbar),
  `settled_verified` (verde, "measured"), `refuted` (vermelho),
  `retracted` (dim).
- Cross-signal honesto quando existe `prior_snapshot.pool`: "engine says:
  measured 38.2 tok/s median on this class of rig" — número alegado AO
  LADO do basis do engine, nunca misturados.
- Filtro por status (chips) + sort (select) + paginação "load more".
- CTA fixo pra `submit.html`: "found a run in the wild? capture it".
- **Estado vazio OBRIGATÓRIO e bonito** (verdade do prod hoje): "the wall
  is empty — be the first to capture a run". NUNCA invente linha.

### 2. `site/claim.html` — Detalhe do claim (`?id=<uuid>`)

- `GET /v1/claims/{id}` → mesmo shape + tally completo + branch roofline
  (`prior_snapshot.roofline.expected_decode_tok_s`, basis "formula").
- Seções: números alegados (grandes, mono) · a origem (chip source_url ou
  "self-reported") · cross-signal do engine · votos · ações.
- **Voto** (só com token): `POST /v1/claims/{id}/votes` body
  `{"verdict":"plausible"|"impossible"}`; 401 → CTA sign-in; auto-voto
  409 → mostrar mensagem da API. Tally como barra de margem.
- **⚑ Report**: `POST /v1/claims/{id}/reports` body
  `{"reason_category":"numbers_unreal|wrong_hardware|wrong_model|duplicate|other","reason_detail":"≤1000"}`
  (5 categorias, EXATAS, é o contrato da API); 401 → "sign in to report";
  409 → a API explica. Modal no padrão do console. Report confirmado =
  "fake caught, +5 points" — diga isto no modal, é a mecânica que mantém
  o pool honesto.
- **Bloco settle** (status open): o comando exato
  `benchmark-probe upload --settle-claim <id>` num chip copiável — "prove
  it with a signed run".
- Estados: 404 ("no such claim"), refuted (banner vermelho, report
  creditado), settled_verified (banner verde "verified by signed run",
  `benchmark_run_id` curto).

### 3. `site/submit.html` — O funil de captura (a porta de entrada da rede)

- **A entrada abre com as DUAS JORNADAS SEPARADAS — lei do dono —**
  portas distintas lado a lado (empilham no mobile), nunca um seletor só:
  - Porta **"I found it online"** → exige `source_url` (http/validado).
  - Porta **"I ran it myself"** → `source_url` opcional; `note` vira o
    contexto.
- Contrato `POST /v1/claims` (Bearer `localStorage.bm_token`,
  `Content-Type: application/json`):
  - `source_url` — string http(s), obrigatória na jornada "found online".
  - `model_release_id` — select populado do índice congelado que o site já
    serve (`data/derived/models.json`), agrupado por modalidade.
  - `claimed_metrics.decode_tok_s` — obrigatório, número.
  - opcionais: `quantization_profile_id`, `gpu_model_id`,
    `context_tokens`, `note`.
- Sem token: o form renderiza DESABILITADO com um único CTA honesto
  "sign in to capture → /console". Nunca poste sem auth.
- Sucesso: card do claim criado + links pro wall e pro detalhe. Erro:
  mostre o `detail` da API verbatim.

### 4. `site/profile.html` — Track record do contribuidor (`?handle=...`)

- `GET /v1/users/{handle}` → shape exato:

```json
{
  "handle": "string", "display_name": "string", "created_at": "…",
  "reputation": { "points": 0, "tier": "L0", "updated_at": null },
  "badges": [ { "…": "…" } ],
  "follow": { "followers": 0, "following": 0, "viewer_is_following": false },
  "rigs": [ { "slug": "…", "nickname": "…", "is_public": true, "created_at": "…" } ]
}
```

- A escada Track Record só de sinais REAIS: runs assinadas validadas,
  reports creditados — **sinal ausente = nível "not yet", nunca escondido**.
  Copy congelada (aprovada pelo dono): Contributor → Replicator → Auditor;
  "granted by a verified act; levels are not self-declared and do not
  decay; every act is attributable to an Ed25519 key."
- Follow (`POST/DELETE /v1/users/{handle}/follow`, com token; 401 → CTA).
  Rigs listadas só quando `is_public`.
- 404: "no such handle".

### 5. Integração na navegação

- Nav existente do site ganha os links novos (The wall · Capture ·
  Profile) NO PADRÃO que já existe — nada mais muda em index/hardware.
- `site/assets/social.css` (blocos NOVOS, nunca redefinir tokens) e
  `site/assets/social.js` (fetch, render, estados; ES module).

## LEIS INEGOCIÁVEIS

1. **UX law (a reclamação nº 1 do dono, duas vezes)**: intent/modalidade,
   máquina/rig, quantização e contexto são SEMPRE controles separados,
   nunca fundidos, nunca no mesmo dropdown ou chip row. Vale pra TODA
   página que filtra. E as duas jornadas (found online × ran it myself)
   são portas separadas na entrada da captura.
2. **Honestidade**: o prod tem HOJE zero claims de rede social e zero
   contributors — estados vazios são OBRIGATÓRIOS e bonitos; dado de
   amostra só em modo fixture claramente `SAMPLE` que nunca se passa por
   real; nenhum preço, data ou contagem inventada; nenhum número sem
   fonte (API ou `data/derived/`); basis declarado em todo número
   (measured > reported > extrapolated > "no data yet").
3. **Mobile-first de verdade**: toda página funciona linda a 360px — sem
   scroll horizontal, sem min-width gate, alvos de toque ≥44px, tabelas
   largas em container com overflow ou viram cards. (Isto foi a dor que
   abriu todo este trabalho — leve a sério.)
4. **Pureza**: zero frameworks, zero npm, zero build, zero request externo
   novo (fontes já estão no site), caminhos relativos, cleanUrls-safe.
5. **Anti-invenção**: não invente número, nome de modelo, rig, endpoint,
   categoria ou copy de dado. Campo que não existe no contrato/JSON não
   renderiza. `prototypes/` é intocável.

## AUTO-AUDIT (rodadas obrigatórias antes de entregar — não são sugestões)

- R1 — cada página a 360px E 1440px: sem scroll horizontal, sem min-width,
  UX law respeitada, touch ≥44px, numerais mono alinhados.
- R2 — varredura de honestidade: com a API devolvendo zeros/vazio, alguma
  página mostra número que a API não produziu? (se sim: delete) Estados
  vazios renderizados? source_url é o herói do wall?
- R3 — pureza: zero frameworks/npm/build, requests externos zero, paths
  relativos, links sem barra final, token só de `localStorage.bm_token`.
- R4 — preservação: `git diff` em index.html/hardware.html mostra SÓ a
  nav; theme.css e prototypes/ intocados; nenhum token redefinido.
- Entregue o audit como tabela no fim, junto da lista de arquivos criados/modificados.

## ENTREGA

- Trabalhe num branch `social/capture-network`. Commits pequenos e
  descritivos. Nada de node_modules (não existe npm aqui — mantenha assim).
- Ao fim: RELATÓRIO.md no branch com o que fez, o que ficou de fora,
  divergências achadas no repo e a tabela de audit.
- Não mexa em: `prototypes/`, backend, deploy, DNS. Front-end apenas.
