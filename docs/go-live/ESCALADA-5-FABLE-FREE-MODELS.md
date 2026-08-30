# ESCALADA-5 v2 — Fable: plano FREE pré-mastigado (validar, não desenhar)

> URGENTE. Regra desta escalada: **tudo já está decidido e desenhado
> abaixo.** Seu trabalho é validar 5 decisões (responda A ou B, uma linha
> cada), apontar risco que eu não vi, e congelar. NÃO explore o registry
> nem a web — tudo que você precisaria verificar está aqui, verificado
> hoje (2026-08-31) na árvore do main. Se quiser conferir UM número:
> `bash bin/audit-registry-ids.sh | tail -4`.

## 0. Situação medida (a tese do dono)

- `resolve-tier tier:cheap` → `deepseek-v4-flash-free` → **FANTASMA**
  (audit-registry-ids). O caminho DEFAULT do produto não despacha.
- **46/69 ids do registry mortos**: 21 NAO-ENCONTRADO + 25 FANTASMA.
- Free: só 2/22 alcançáveis (faltam 5 NVIDIA + quase todo OpenRouter :free).
- auth: 0 credenciais gravadas; 3 providers PAGOS por env herdada
  (118 Bedrock + 36 Copilot) vs 6 free. O default de fato é pago.
- Captura de credencial escrita 3x, hardcoded no OpenRouter, nunca no
  caminho principal: dispatch-vision-ui-qa.sh:98, dispatch-vision-map.sh:24,
  vision-gauntlet-loop.py:88 (dívida regra 32).
- Fonte nova aprovada pelo dono: **awesome-freellm-apis / freellm.net**
  (MIT, atualizado diário, 453 modelos JSON, 30 providers free
  permanentes, rate limits RPM/RPD por provider, base URLs
  OpenAI-compatible). Inspecionado por mim: é real e cobre exatamente os
  buracos (NVIDIA 126 modelos, Zen, Groq, Gemini, SiliconFlow...).

## 1. O plano (implemento EU; você só valida as 5 decisões)

**M1 — feed**: script `bin/sync-free-catalog.sh` baixa o dataset
estruturado do freellm.net (453 modelos, JSON) e escreve
`data/free-catalog.json` com proveniência `{"source":
"freellm.net/awesome-freellm-apis", "snapshot": "<data>", "license":
"MIT"}`. Idem espírito S28: fonte carimbada, nunca id solto.

**M2 — gate na porta**: id novo só entra no registry candidato se o
audit passar (mata a classe "fantasma nasce"). Falha = lista nomeada,
fail loud.

**M3 — reparo do estoque**: os 46 ids mortos saem do registry (ou vão
para `status: retired` com data) — registry ≤ tamanho verdade.

**M4 — tier:cheap = lista quota-aware**: resolve para ordem de fallback
(provider 1 → 2 → ...) lendo os rate limits do feed (RPM/RPD). Nada de
id único apodrecendo.

**M5 — credencial única**: `bin/lib-free-credentials.sh` descobre TODOS
os providers do auth.json (genérico, não só OpenRouter); as 3 capturas
hardcoded passam a chamá-la.

**M6 — verdade no ledger**: campo `provider_efetivo` em toda linha de
run + allowlist de provider por run (o run registra quem atendeu de
verdade).

## 2. As 5 decisões (responda A ou B — minha recomendação marcada)

- **D1 retire**: A) 46 mortos REMOVIDOS do registry (registry = só
  verdade) ← recomendo; B) ficam com `status: retired`.
- **D2 feed**: A) dataset JSON do freellm.net direto ← recomendo (453
  modelos, estruturado); B) parse do README markdown.
- **D3 quota**: A) fallback consulta rate limits do feed em runtime ←
  recomendo; B) snapshot semanal dos limites no registry.
- **D4 credencial**: A) auth.json como única fonte (genérico por
  provider) ← recomendo; B) chaves por env `*_API_KEY` também aceitas.
- **D5 fechado**: o gate que prova o fim — recomendo: `test-free-path.sh`
  = preflight lint + resolve-tier tier:cheap devolve lista ≥3 ids vivos +
  dispatch stub fechando com provider_efetivo registrado, tudo sem
  credencial paga. Concorda ou aperta?

## 3. Definição de pronto

Os 6 mecanismos em gates verdes + D5 exit 0 + a promessa do README
("no API key, 2 minutos") medida de novo com cronômetro. Sem isso, o
anúncio não sai.

## 4. NÃO reabrir

S28 (import localmaxxing), The Lineup (S13), export (S27), Claude Design
(ESCALADA-4) — tudo em andamento por outras frentes. O incidente externo
que originou esta escalada: os fatos estão citados aqui; o .md dele sobe
no main quando o dono o entregar (não bloqueia você).
