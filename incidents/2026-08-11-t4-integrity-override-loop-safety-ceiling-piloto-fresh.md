---
id: 2026-08-11-t4-integrity-override-loop-safety-ceiling-piloto-fresh
titulo: Piloto <host-local> v3 fresh — T1–T3 OK; T4-JUDGE loop INTEGRITY override + gap `>-` esgota Safety ceiling 2×
data: 2026-08-11
recorrivel: sim (T4-JUDGE APPROVED truncado → INTEGRITY override → iterar não conserta → teto 6 × 2 attempts)
regra: evidencia-integrity-stagnation + sentinela-block-scalar-vazio
status: aberto-correcao-em-andamento
interage_com: "2026-08-11-t2-safety-ceiling-piloto-<host-local>-v3-2"
interage_com: "2026-08-11-t2-judge-contract-error-piloto-<host-local>-v3-adr0005"
interage_com: "2026-08-10-veredito-sem-degrau-intermediario-faz-ju"
interage_com: "docs/architecture/ADR-0005-iteracao-sem-gap-e-falha-de-contrato.md"
---

# Piloto <host-local> v3 fresh — T4 morre no INTEGRITY override loop

## Contexto

Terceira rodada do piloto `cf-<host-local>-radeon680m-v3` no mesmo dia, com
**fresh-state** aplicado antes do despacho: checkpoint T2+ limpo, T1 preservado
(cache). Fixes do dia ativos:

- rubrica binária T2-JUDGE (10 itens sim/não)
- escalada por gap estagnado (`GAP_STAGNATION`)
- fallback `LLM_FALLBACK`
- extrator nested `biggest_gap` (BFS + `descricao` + sentinels vazios)
- input juiz 30k chars; `max_tokens: 16000` em T2/T3/T4

Primeiro launch morreu com `DISPATCH_RUNNER unset` (exit 3) — corrigido
`source adapters/opencode/env.sh`. Re-despacho gerou run abaixo.

## Resultado

| Campo | Valor |
|---|---|
| `run_id` | `A2C451B7-C50B-431F-A8F4-E327F1928B2A` |
| janela | **17:25–18:36** local (~**71 min**, `duration_s=4270`) |
| `status` | `fail` (Caminho B) |
| ponto de falha | **T4-JUDGE** — Safety ceiling (6) nas **2 tentativas** do stage |
| T1 | cache hit (HUNT + JUDGE) |
| T2 | APPROVED após **1** iteração gauntlet (rubrica nova OK) |
| T3 | APPROVED de primeira |
| T4 | loop até teto 6 → escalation → stage retry → teto 6 de novo |
| `run_finished` | sim em `events.jsonl` (`status: fail`); crew saiu `PARTIAL_EXECUTION` |
| canários ADR-0005 | **limpos** — zero `biggest_gap: ""`, zero `JudgeContractError`, zero `GAP_STAGNATION`, zero `LLM_FALLBACK` |

Comparativo com rodadas anteriores do mesmo dia:

| | v3#1 (`FB804AA5`) | v3#2 (`A743CE7F`) | **fresh (`A2C451B7`)** |
|---|---|---|---|
| falha | JudgeContractError T2 | Safety ceiling T2 (truncation) | Safety ceiling **T4** (INTEGRITY loop) |
| T2 | crash extração | 6 iter não-convergentes | **1 iter → APPROVED** |
| T3 | — | — | **APPROVED 1ª** |
| truncamento | — | artifact T2 no prompt juiz | output **T4-JUDGE/T4-CONTENT** (fence YAML) |
| gap lixo | gap aninhado não extraível | gaps articulados | **`biggest_gap: >-`** aceito pelo extrator |

## Causa raiz

**INTEGRITY CHECK override** (×5): T4-JUDGE (e uma vez T4-CONTENT) emitia
`APPROVED`, mas o output saía **truncado** — fence YAML ``` não fechado. O
override automático reverte para `REVISIONS_REQUIRED`. Iterar **não conserta**
truncamento (mesma cota/contrato de output), então o feedback-loop queimou
**6 iterações × 2 attempts** = 12 passagens de juiz sem convergir.

Telemetria de truncamento nos logs:

| sinal | contagem |
|---|---|
| `INTEGRITY CHECK override` | **5** (mech-1: 1, mech-2: 4) |
| `biggest_gap: >-` (display/log) | **18** (mech-1: 8, mech-2: 10) |
| `FAIRNESS CHECK override` | 5 (disclosure/preço T4-CONTENT — ruído paralelo) |
| `chars truncated` | 15 (display CrewAI — não fatal) |

### Achado CRITICAL — gap `>-` passa no extrator

Na iteração **6/6** da tentativa 2, o truncamento deixou:

```yaml
biggest_gap: >-
```

(indicador YAML de block scalar fold **sem conteúdo**). O extrator nested
**aceitou a string literal `>-`** como gap válido e alimentou o builder —
iteração cega com feedback lixo. ADR-0005 previa sentinels vazios (`""`, `{}`,
`[]`, `null`) mas **não** indicadores YAML de fold vazio.

Evidência na escalation `_183652.json`: corpo do juiz diz `decision: APPROVED`
com parecer completo; INTEGRITY override imediatamente depois; `final_output_summary`
truncado mid-field.

### Hipóteses em investigação (max_tokens já em 16k)

`judge_content_copy` **já** tinha `max_tokens: 16000` — diferente do caso T2
de mais cedo (`A743CE7F`). Três hipóteses abertas:

1. **Contrato de output T4-JUDGE grande demais** — `specific_edits` linha-a-linha
   sobre bundle ~28KB; artifact truncado ~22KB.
2. **`max_tokens` não chega na chamada** — caminho de fallback de emergência
   do `_create_agent_llm` ignora override.
3. **Clamp da API DeepSeek em 8192** — pedido 16k, resposta cortada no provider.

## Timeline

```
17:25:45  mech-1 começa; T1 cache hit (HUNT rejected skip + JUDGE approved)
17:27–17:34  T2-ARCHITECT → T2-JUDGE loop 1/6 (gap articulado) → T2 APPROVED
17:37–17:38  T3-DESIGN → T3-JUDGE APPROVED (1ª passagem)
17:40–17:58  T4-CONTENT/T4-JUDGE loops; FAIRNESS override ×3; INTEGRITY override T4-CONTENT ×1
17:58–18:09  T4-JUDGE continua; `biggest_gap: >-` aparece; Safety ceiling (6) → escalation_180941
18:09–18:36  stage retry automático (mech-2); INTEGRITY override T4-JUDGE ×4
18:36:52  iter 6/6: juiz APPROVED truncado → INTEGRITY override → Safety ceiling (6) → escalation_183652
18:36:53  dispatch: stage run failed after 2 attempts; events.jsonl run_finished fail duration_s=4270
```

## O que funcionou

- Fresh-state + T1 cache: pulou ~15 min de T1.
- Rubrica binária T2-JUDGE: 1 iteração, gap acionável, APPROVED.
- T3-JUDGE: convergiu de primeira.
- Extrator nested + ADR-0005 canários: sem loop patológico de gap vazio.
- Escalation JSONs persistidos (`escalations/escalation_20260811_180941.json`,
  `_183652.json`).
- Stage retry automático do gauntlet (attempt 2) — fail contável, não hang.

## Relação com incidents/ADRs anteriores

- **ADR-0005**: teto-6 e contrato NOT-NULL **funcionaram** — não houve loop
  cego de 20 iter nem `JudgeContractError`. Falha é **conteúdo/truncamento**,
  não contrato vazio. Risco residual citado no ADR ("gap lixo genérico") materializou
  como **`>-`** — classe nova, não coberta pelos sentinels atuais.
- **T2 JudgeContractError** (`FB804AA5`): mesma família "juiz sabe, campo
  estruturado falha" — aqui o campo existe mas é **lixo de parser**, não ausência.
- **T2 Safety ceiling** (`A743CE7F`): mesmo padrão truncamento → loop
  não-convergente → teto 6 — mas no **T2** e sem INTEGRITY override explícito.
- **INTEGRITY CHECK** (`2026-08-10-veredito-sem-degrau-intermediario`): override
  já existia para T2-JUDGE; hoje atuou pesado em **T4** com bundle grande.

## Proteções propostas (working tree, outro agente)

1. **Encolher contrato T4-JUDGE quando APPROVED** — `specific_edits: []`, sem
   re-embarcar bundle inteiro no output do juiz.
2. **Sentinela block scalar vazio** — rejeitar `>-`, `>`, `|-`, `|` e folds sem
   conteúdo parseável no extrator (estende ADR-0005 item sentinels).
3. **Escalada precoce `INTEGRITY_STAGNATION`** — 2 INTEGRITY overrides
   consecutivos no mesmo task → human escalation antes de queimar 6 iter.

## Efeitos colaterais (fora do escopo imediato)

- Metric `attempt: 4` vs `oracle_result attempt: 1/2` — mesma inconsistência
  dos pilotos T2 anteriores.
- FAIRNESS CHECK override (disclosure/preço) competiu com INTEGRITY no T4 —
  corrigível pelo content, mas somou latência.

## Evidência

`incidents/evidence/2026-08-11-t4-integrity-loop/`

- `dispatch.log` — stdout do dispatch
- `mech-1.log.gz`, `mech-2.log.gz` — logs completos das 2 tentativas
- `escalation_20260811_180941.json`, `escalation_20260811_183652.json`
- `integrity-loop-snippet.log` — trechos INTEGRITY / `>-` / Safety ceiling

Run dir origem:
`~/<repo-cliente>.live-imports/.dispatch/logs/inbox/A2C451B7-C50B-431F-A8F4-E327F1928B2A.run.gauntlet/`

## Veredito

**Progresso real até T3** — fresh-state + fixes T2 validados. Caminho A ainda
bloqueado em **T4** por truncamento sistemático do output do juiz: INTEGRITY
override cria loop não-convergente que o teto-6 conta corretamente mas não
resolve. Prioridade: contrato menor no APPROVED + sentinela `>-` + escalada
INTEGRITY_STAGNATION. Não publicar; não escalar os 9 nichos até T4 verde.
