# DECISIONS-E6 — veredito do Fable (2026-08-31), ingerido verbatim

> Fonte: dono colou a resposta da ESCALADA-6. Ingestão: copiada para o
> canônico sem edição (classe incidente dois-checkouts). Execução:
> S28 MELHORAR (0015), perna D5 extra, guard do risco 1, copies+dial no
> mesmo commit (risco 2) — commits citados no ESTADO-SESSAO.

---

CHECKOUTS
llms.surf=409879c ok — HEAD real é eb617a4 = 409879c + 2 commits doc-only (o próprio prompt da ESCALADA-6 + estado); git diff 409879c..HEAD excluindo esses 2 docs = vazio, árvore validada idêntica ; bestmodel=604e7c2 ok

VEREDITO E5
M4: OK — resolve-tier devolve 11 refs em ordem (keyless primeiro, conferido); nenhum consumidor sobrou: modos YAML→loader, run-with-fallback, dispatch-mode, dispatch-stages (tier:*)→run-with-fallback na linha 408), critic; bin/oracfit:256 só emite tier:cheap como default de scaffold e resolve pela mesma cadeia. M5: OK — lib lida por ARQUIVO com exit 3 loud em storage ilegível (código conferido); anel 2 mede só código (comentário excluído, com justificativa no próprio gate); cf-probe/vision-gauntlet contadas no anel 3. Suficiente — não exijo nada mais duro. M6: OK — default fora-do-escopo (nunca "ok" silencioso), provider_efetivo+ref gravados por quem SERVIU, allowlist adulterada→violado provado por perna do gate; fecha R4/R5 do meu veredito da ESCALADA-5. M1: OK — free = pricing==0 MEDIDO no feed, replace atômico com validação, feed morto mantém snapshot (perna PASS ao vivo aqui); R2 suficiente para o pior caso. D5: OK — rodei: 13/13 PASS em ~17s, envenenamento coberto; sugestão barata não-bloqueante: perna extra assertando storage ilegível → exit 3 (o fail-loud da lib hoje só existe em código, não em gate). S28: MELHORAR — reporter_user_id é nullable no 0014 (índice até prevê 'anon') enquanto a API exige auth; migration 0015 com NOT NULL fecha o contrato DB=API antes que um segundo write path apareça. Fora isso, S20+409+identidade cobrem o abuso no tamanho atual (moderador é o choke point de pontos). B2: OK — quiteiro aceito: é mecanismo em código (dispatch-stages roteia tier:* via run-with-fallback), não regra de prosa; camada 2 cursor documentada como vigência é suficiente.

RATIFICAÇÕES
RAT-1: OK — o /v1/models do próprio provider é exatamente o "feed JSON estruturado" que o D2 pedia; awesome-freellm-apis como diretório de curadoria é o uso certo do que ele de fato publica. RAT-2: OK — dial em data/free-provider-allowlist.json com nota de decisão explícita, conferido no disco; default casa com as duas pernas vivas. RAT-3: OK — env-list é proporcional a prod com 1 usuário; gatilho de migração para tabela de roles = existência do 2º moderador, não data.

DECISÕES
4.1: (a) ; 4.2: ok COM condição — canário de 1 chamada PELA CADEIA (dispatch tier:cheap após opencode auth login) conferindo na linha do ledger provider_efetivo=openrouter + allowlist_status=ok e custo 0 no painel, antes de anunciar a perna ; 4.3: propose (thresholds PROPOSTA abaixo; dono gira em data/lineup-points.json) 4.4: Standings a cada 2 semanas, event-driven — pula o drop se o rank não mudou (drop vazio ensina o leitor a ignorar). 4.5: Conversão = primeiro signed run do indicado em ≤30 dias da criação da conta; sem run, expira sem retroativo (join não converte — join é o 1 pt do próprio indicado). 4.6: Manter argos-opt — descritivo, dual-licenciado, rename custa mais que rende; ASSUMPTION: disponibilidade no crates.io não verificável nesta rodada (rede proibida).

COPY THE LINEUP
The Lineup
Points come from the export, and the export comes from signed activity. Nobody hands out clout here — you paddle for it.

How you score (owner's dial, data/lineup-points.json): open your join issue (1) · referral that actually converts (3) · signed run (2) · reproduce someone else's run (3) · catch a fake (5) · share a custom mode (2).

Haole
You just showed up and you're paddling in everyone's way. It's fine — every Legend was a haole once.

Badge: "Foam Board" — a beat-up soft-top, nose pointed the wrong way.
Promotion in: open your join issue and you're in the water. PROPOSTA: 1+ point.
Grom
You've caught something real. Small, but real — and it's signed, so nobody can say you didn't.

Badge: "First Real Wave" — a small clean wave with a signature scrawled in the whitewash.
Promotion: PROPOSTA — 5+ points including at least 1 signed run.
Local
You're here every session, and your runs hold up when reproduced. That's the whole job description.

Badge: "Peak Position" — a lineup-spot marker pinned on a wave peak.
Promotion: PROPOSTA — 20+ points including 3+ signed runs or 1+ reproduction.
The Legend
You don't just ride the pool, you defend it: reproducing runs, calling out fakes, keeping the water honest.

Badge: "Golden Longboard" — a gold-leaf longboard planted upright in the sand.
Promotion: PROPOSTA — 50+ points including 1+ confirmed fake caught or 3+ reproductions.
First Wave — prize, not a tier
Top-25 by points. When the cloud queue exists, First Wave gets priority in it. That's the prize: first in line when there's a line. No GPUs promised, no dates promised — priority is the promise, and it's the only one.

Sockpuppet note: referral only counts when the referred account actually contributes. That's not a policy we hope you respect — it's code.

COPY TRACK RECORD
Track Record
Why does replication outrank claiming? Because a claim is one machine and one voice; a replication is the same numbers surviving different hands. The community measures, the CLI signs, anyone can replicate — and every level below is computed from that signed record, nothing else.

Scoring (from the contributor export): validated signed run ×2 · reproduction of another contributor's run ×3 · confirmed fake caught ×5.

Contributor
Runs benchmarks on their own hardware and submits signed results.

Badge: "Contributor" — a single filled data point on a measurement axis.
Advancement: PROPOSTA — 1+ validated signed run.
Replicator
Independently reproduces other contributors' runs, confirming or contradicting reported numbers.

Badge: "Replicator" — two measurement traces converging on the same value.
Advancement: PROPOSTA — 3+ validated reproductions.
Auditor
Actively defends pool integrity: replicates high-impact cells and reports unreal runs through the moderation flow.

Badge: "Auditor" — a magnifier over a bar chart, one bar struck through.
Advancement: PROPOSTA — 1+ confirmed fake caught and 3+ reproductions.
POST LLMSSURF
The lineup is open — and the free path finally deserves its name

llms.surf is an orchestration framework for LLM dispatch: modes, tiers, ordered fallback chains, and a signed ledger that records who actually served every run. It runs locally, against providers you choose, and it keeps receipts — 107 incident postmortems live in the tree (2026-08-31), because the failures are part of the product.

The Lineup. A contribution program scored from signed activity only: signed runs, reproductions, fakes caught, custom modes shared. The door is a GitHub issue — open one and you're in the water. There is no hosted cloud today; everything runs on your machine. Tiers go Haole → Grom → Local → The Legend, and the top-25 by points take the First Wave: priority in the cloud queue when it exists.

The free path, re-announced. The same ruler that opened the incident closes it: the registry audit went from 46/69 dead model ids to 0/23 (2026-08-31). The zero-key leg is measured, not promised — two bundled models answered real prompts in ~15-16s without a single key created (2026-08-31). Nine OpenRouter :free models sit in the stamped catalog with pricing==0 measured in the feed, and a 13-check integrity gate — including a dispatch run with deliberately poisoned paid credentials — proves nothing paid sneaks in the back (2026-08-31). Local health battery: 20/20.

Paddle out. Bring a signature.

Registry audit: 46/69 dead model ids removed → 0/23 (2026-08-31)
Zero-key free path: two bundled models answered real prompts in ~15-16s, no key creation (2026-08-31)
Free-path integrity gate: 13 checks incl. poisoned paid credentials; local health battery 20/20 (2026-08-31)
[PT-BR: Framework de orquestração local com ledger assinado e 107 postmortems na árvore. The Lineup: entrada por issue, pontos só por atividade assinada, sem cloud hoje. Free path re-anunciado: régua 46/69→0/23, perna zero-key medida (~15-16s, sem criar chave).]

POST BESTMODEL
bestmodel.run: which model can your machine run — with receipts

bestmodel.run answers a practical question: which model can this machine run, how fast, and is it worth it — from measured data, not vendor spec sheets. The operating principle is a motto we intend to keep earning: reported ≠ verified.

Every benchmark cell in the pool carries structured provenance — where the number came from, which snapshot, which file. 551 community-reported benchmark cells were imported with verified provenance: 550/550 metrics identical to the 2026-08-13 pool snapshot. Not presumed equivalent — checked, cell by cell.

Numbers that look wrong should be easy to challenge. The "report an unreal run" mechanic is live in the production API (smoked 2026-08-31): reports are tied to an identified reporter and reviewed by a moderator; a confirmed report marks the claim refuted and credits the reporter. A report never silently alters its target.

Track Record is the contribution ladder: Contributor → Replicator → Auditor. Replication outranks claiming by design — a claim is one machine and one voice; a replication is the same numbers surviving different hands. The community measures, the CLI signs, anyone can replicate.

If you run models on your own hardware, your measurements are exactly what this pool is for.

551 community-reported benchmark cells imported with verified provenance (550/550 metrics identical to the 2026-08-13 pool snapshot)
"Report an unreal run" live in the prod API (smoked 2026-08-31)
Every imported cell carries structured provenance — source, snapshot, file hash — stamped with evidence, not presumption
[PT-BR: Ranking honesto de hardware local: dado medido com proveniência, lema "reported ≠ verified". 551 células importadas com proveniência verificada (550/550 idênticas ao snapshot de 2026-08-13). Denúncia de run irreal já no ar na API de produção; Track Record: Contributor → Replicator → Auditor.]

FALTA PRA LANÇAR
#	Item	Dono da ação	Dependência
1
DNS llms.surf → Phase A
dono
nenhuma
2
Smoke autenticado da denúncia (passkey)
dono
prod já no ar — fazer ANTES do item 4
3
Chave free OpenRouter (sem cartão) + opencode auth login + canário 4.2
dono
catálogo pronto; canário condiciona o anúncio da perna
4
Botão de denúncia no front + redesign bestmodel
Claude Design
prompt pronto (docs/go-live/PROMPT-CLAUDE-DESIGN-BESTMODEL-ONLY.md); ideal após 2
5
Subida das copies nos sites
dono (cola)
este veredito + dial 4.3 gravado em data/lineup-points.json no MESMO commit da copy
6
S12 (Vast runbook)
bloqueada — veto do Vast
fora do go-live
7
Pós-lançamento: Discussions + anúncio
dono
1–5 concluídos
ORDEM: certa, com 1 ajuste — o smoke autenticado (2) deve fechar antes do Claude Design (4) congelar UI, para qualquer correção de API acontecer antes do front nascer em cima dela.

RISCOS NÃO LISTADOS
Staleness do catálogo free: pricing :free vira pago sem aviso (a própria classe E5 — o feed já pegou 2 flips); não existe re-sync agendado. Rodar sync-free-catalog.sh no dia da colagem das copies e antes de ativar a perna free-key.
Copy/dial drift: data/lineup-points.json está com "dial":"pending-owner"; se as copies PROPOSTA subirem sem o dial gravado no mesmo commit, o site promete corte que a máquina não aplica.
First Wave preso ao veto do Vast: "prioridade em fila quando ela existir" é honesto, mas se o veto durar meses o prêmio esfria — ter resposta pronta para "quando existe a fila?".
Re-report após dismiss: o índice único do 0014 só trava denúncia ABERTA duplicada; alvo dismissido pode ser re-denunciado em loop (dano limitado pelo teto 10/dia, mas custa atenção do moderador único).