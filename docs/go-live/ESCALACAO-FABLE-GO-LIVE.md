# ESCALADA → FABLE: go-live MVP integrado + v4 pública do llms.surf

> Cole isto numa sessão **nova** do Fable. Não é implementação. Não é
> screenshot. É direção + specs que o GLM executa com oráculo congelado.

---

## LEMBRETE PERMANENTE — leia antes de qualquer coisa

Você é caro. **Não escreva código. Não rode testes. Não edite YAML de modo.
Não faça deploy. Não toque `bestmodel-prod`, Vast, nem rig alugada.**

Seu trabalho: **estratégia de produto + syntax pública + specs executáveis**.
GLM (`glm_smart`) implementa depois, sob oráculos que **você** congela no
texto da spec. Se um item não cabe num oráculo mecânico, não é spec — é
decisão do dono, e você marca assim.

Arquivo pontual só se for spec / matriz de decisão / copy de lançamento.
Nunca implementação.

---

## 1. O pedido do dono (essência, desta conversa)

Ele vai lançar os dois produtos juntos, o mais rápido possível, e jogar
tráfego (Twitter replies, Twitter ads, Meta ads) no **site** e num
**repo público**. A ferramenta tem que viciar em **menos de 1 hora**.

Tese de negócio (não invente números em cima):

> A ferramenta viral cria demanda por **tokens leves e baratos**. Enquanto
> as 3090 (Paraguai) não estão inferindo, ele vende esses tokens **a preço
> de custo**. Quando as 3090 estão ociosas, elas passam a suar. Swell /
> hosted inference **não existe ainda**. Não invente $/M nem tok/s hosted.

Produto público do llms.surf, v4 definitiva, **simplificar atrito**:

- **3 modos padrão** (já existem no tree — não redesenhe o pipeline):
  1. tarefas **mecânicas** → modelos leves (`normal`)
  2. **destravar** problema → modelo caro planeja, barato sua (`unlock_plan`)
  3. **QA visual** → visão + reduce (`ui_visual_qa`) — **manter**
- **Foco desta escalada: o modo custom.** Criar modos próprios,
  **privados ou públicos** (comunidade). Syntax tem cara de **surf**.
  Curva de aprendizagem mínima. Gamificação **leve**.

Os outros ~17 YAMLs em `core/modes/` (god modes de workshop: pantocrator,
autarca, ouroboros, …) **não são o produto público**. Você decide o que
fazer com eles (arquivo interno, exemplos, sumir da UI) — não apague a
história sem o dono.

LICENSE hoje: **llms.surf é proprietary**. bestmodel.run é **AGPL/MIT**.
O dono falou em “repo opensource” para viralizar. **Você não vira a
LICENSE.** Você propõe o recorte (o que é o ímã OSS vs o dispatcher
proprietário) e deixa a virada como decisão do dono.

---

## 2. O que já existe (não redescubra)

Leia, na ordem, só o que precisa para não inventar produto:

| peça | fato no tree |
|---|---|
| Dispatcher | `bin/llms-surf` → `bin/oracfit`. Sem args = TUI (`bin/llms-surf-tui.sh`). Com args = passthrough. |
| 3 modos que o TUI já recomenda | `normal`, `unlock_plan`, `ui_visual_qa` (`MODES_RECOMMENDED` no TUI) |
| `normal` | 1 stage `run`, `tier`/flash, gauntlet, oracle. `core/modes/normal.yaml` |
| `unlock_plan` | 3 stages: unlock `tier:expensive` → plan `tier:mid` → run `tier:cheap`. Oracle no unlock e no run. `on_fail: halt`. |
| `ui_visual_qa` | map `tier:vision` → reduce `tier:cheap` + oracle. Runtime ainda aponta `bin/dispatch-vision-ui-qa.sh` (dívida: YAML multi-stage vs script). |
| Custom **já nasce** | `llms-surf mode init <id>` escreve YAML no **workdir** (`core/modes/<id>.yaml`), depois `mode validate` / `mode lint`. Overlay: workdir sombra o built-in. |
| Schema | `bin/lib-oracfit-mode-loader.py` — keys permitidas, roles `unlock\|plan\|run\|map\|reduce\|export\|render\|vision_gate`, tiers `cheap\|mid\|expensive\|vision`. |
| Clone 2 min | stub runner, **sem API key**. Hero do site já é clone-first. |
| Jornada site | `site/journey.js` human/agent/ask. `site/llms.txt`. Honesty: `tests/test-site-honesty.sh`. |
| Irmão | bestmodel.run = “cabe nesta GPU?”. L03 unificado. S25 **não** é o go-live. Cloud/Swell **hold**. |
| Ferro | 3090 Paraguai = lab + suor futuro. Tabela custo-benefício **pronta e não entregue**. Célula Flash Next **não publicada**. Não invente tok/s hosted. |
| Smoke antigo | `docs/SMOKE-WITH-FIRE.md` — desatualizado (ainda cita tabela Swell que **saímos** do site). Você reescreve o critério de go-live; não implementa. |

Contrato que não negocia:

- Vitória = **exit 0 do oráculo no disco**, nunca a opinião do modelo.
- Número inventado = bug crítico (igual bestmodel).
- Não chame hosted de vivo. “no data yet — we say so”.

---

## 3. Onde está o ouro (foque aqui)

O on-ramp público são os 3 modos. **O vício e a viralidade são o custom.**

Hoje `mode init` é um scaffold de 15 linhas que um agente de workshop
entende e um estranho no Twitter **não**. Sua tarefa central:

**Transformar “criar um modo” no ato de 5 minutos que a pessoa mostra
pro amigo.** Syntax curta, vocabulário de surf, um arquivo, um validate,
um run, um oráculo. Privado por default. Público = publicar o YAML (e
só o YAML) para a comunidade — sem fingir uma app store.

Pense o custom como o **break** que cada um encontra: o lineup oficial
são 3 ondas; o resto é o pico que a pessoa nomeia.

Gamificação **leve** (não invente XP, ranking fake, nem tok/s):

- Primeiro oráculo verde em <1h (o clone stub já prova o *path*).
- Primeiro modo **próprio** que passa `mode validate` + um run com
  oráculo.
- Compartilhar o YAML (não o segredo, não a key).
- Wipeouts já existem (106 no corte) — use isso, não crie um segundo
  ledger de pontos.

---

## 4. Decisões que preciso de você

Uma decisão + porquê curto por item. Se for “dono decide”, diga a opção
recomendada e pare.

**D1 — Dois produtos, um go-live.** Qual é o recorte público mínimo
integrado? Não fundir repos. Proposta a confirmar ou refutar: site
llms.surf = fazer o trabalho (3 modos + custom); bestmodel.run = saber
o que cabe na máquina; tráfego ads no llms.surf; ímã OSS = bestmodel
(já é) **ou** um Lineup OSS do dispatcher (LICENSE flip = dono). O que
o anúncio promete em **uma linha** sem mentir.

**D2 — Nomes públicos dos 3 padrões.** Ids no tree podem ficar
(`normal`, `unlock_plan`, `ui_visual_qa`) com **alias de surf** na UI,
ou você renomeia. Constraints: 1 palavra, surf, não colidir com
“Swell” (SKU hosted que não existe). QA visual precisa de nome que um
humano clique sem ler YAML.

**D3 — Syntax do modo custom (o coração).** Gramática mínima para um
humano escrever um modo em <5 min. Deve caber numa ficha:

- id (surf, `[a-z0-9_]+`)
- 1–N stages (role + tier ou `command:` mecânico)
- oracle: comando cru, **sem crase** (incidente 2026-08-10)
- privado vs público (um campo, default privado)

Mostre **2 exemplos completos** no vocabulário que você escolher:
(1) clone do `normal` com outro oráculo; (2) um mini unlock de 2
stages. Não invente keys fora do schema atual sem marcar “requer
extensão de schema + teste no loader” — cada key nova é custo GLM.

**D4 — Privado vs público.** O que “público” significa no MVP: gist?
`modes/` no GitHub do usuário? um índice no site llms.surf? **Não**
desenhe marketplace, login, billing. Qual o menor mecanismo que um
ads click consegue entender.

**D5 — TUI / CLI de 1 hora.** Jornada estranho → viciado. Passos
contáveis. O TUI hoje pede spec path + mode + adapter — isso é
atrito. O que some, o que vira default (stub), o que espera a 2ª
hora. Clone-first do site já existe — alinhe CLI e site.

**D6 — Tokens a custo + 3090 ociosa.** Shape do produto **sem preço**.
Waitlist? “cole sua key, nós não vendemos inferência ainda”? Ponte
bestmodel (qual modelo cabe) → `model_ref` do modo. Critérios de
unlock para vender token (não calendário). Proibido: célula tps,
tabela $/M, SKU Swell.

**D7 — Ads e replys.** Promessa que o anúncio pode fazer e o site
**cumpre no 1º scroll** (clone, 3 modos, custom). O que o anúncio
**não** pode dizer (OSS se LICENSE proprietary; tok/s; hosted). CTA
único.

**D8 — Site v4.** O que entra na home pública vs o que fica no
`?as=agent` / `llms.txt`. Custom modes na home? Como, sem 20 cards.
Honesty test continua mandatório.

**D9 — Os 17 modos de workshop.** Visíveis onde? `llms-surf modes`
lista os 3 + customs do workdir, ou lista tudo? Default da lista
pública.

**D10 — Ordem de specs para o GLM.** 3–7 stories, cada uma com
oráculo de uma linha, teto de arquivo, o que **não** tocar
(prod, Vast, 500 páginas SEO do bestmodel, S25). Go-live é **este**
recorte, não o hardening crônico do bestmodel.

---

## 5. Entregáveis (nesta sessão)

1. **Matriz D1–D10** — decisão, porquê, “dono confirma?”.
2. **Ficha da syntax custom** — a gramática + 2 YAMLs exemplo válidos
   contra o schema atual (ou delta explícito do schema).
3. **Jornada <1h** — numbered, testável (comando + o que o humano vê).
4. **Pack de specs GLM** — um arquivo por story, formato llms.surf
   (`## Oraculo` com `- comando:` **sem crase**). Inclua:
   - UI pública: só 3 modos + custom
   - `mode init` / validate / lint: copy e defaults no vocabulário surf
   - privado/público (o mecanismo mínimo que você escolheu em D4)
   - TUI alinhado à jornada
   - site: home + `llms.txt` + honesty test atualizado
   - **não** incluir S25, S23, cloud, tabela Swell, regen de SEO
5. **Go-live checklist** que substitui `docs/SMOKE-WITH-FIRE.md` Phase A
   (host público, clone 2 min, 3 modos no stub, um custom init+validate+run,
   ads-promise = site). Phase B = só as specs deste pack.
6. **Copy de 1 linha** (anúncio) + **3 linhas** (bio/repo) honestas.

Idioma: decisões e specs em **inglês** (executor GLM + site). Esta
escalada pode responder em PT se for mais nítido; os artefatos que o
GLM vai commitar são EN.

---

## 6. Proibido

- Implementar. “Posso só ajustar o YAML” = não.
- Inventar tok/s, $/M, SKU, “Swell is live”, “open source” se LICENSE
  proprietary.
- Pedir Fable na próxima sessão para escrever Python.
- Unificar os dois git trees. Integração = produto, não monorepo.
- Marketplace, pontos, leaderboard de humanos, login.
- Apagar god modes do git. Esconder da UI pública ≠ delete.
- Tocar prod bestmodel, Vast, Paraguai, `incidents/uso/`.

---

## 7. Done when

O dono consegue colar o pack no `glm_smart` e saber, spec a spec, o
comando que fica verde. A syntax custom cabe numa ficha que um
estranho lê em 2 minutos. O anúncio não promete o que o git não tem.
As 3090 e a venda a custo têm um **shape** e critérios de unlock —
zero número inventado.

Se algo estiver ambíguo, **pergunte ao dono uma vez**, lista numerada,
em vez de preencher o buraco com produto.
